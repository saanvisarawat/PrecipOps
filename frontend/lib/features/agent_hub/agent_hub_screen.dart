import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/agent_hub_models.dart';
import '../../api/models/auth_models.dart';
import '../../core/constants/national_metros.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_button.dart';
import '../../widgets/district_dropdown.dart';
import '../../widgets/section_header.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/app_toast.dart';
import '../profile/role_gate.dart';

/// Friendly checklist label + icon for each of the four backend agents
/// (`agent_manager.py`'s "Risk Analyst" / "Resource Allocator" /
/// "Communications" / "Coordinator") — commanders see plain progress
/// steps here, never raw agent-role labels. Order is the checklist's own
/// display order, independent of the order steps arrive in the chain.
const _agentChecklist = [
  (agentName: 'Risk Analyst', label: 'Situation analysed', icon: Icons.travel_explore_rounded),
  (agentName: 'Communications', label: 'Reports analysed', icon: Icons.campaign_outlined),
  (agentName: 'Resource Allocator', label: 'Resources evaluated', icon: Icons.inventory_2_outlined),
  (agentName: 'Coordinator', label: 'Recommendation ready', icon: Icons.task_alt_rounded),
];

enum _Decision { none, approved, rejected }

class AgentHubScreen extends ConsumerStatefulWidget {
  const AgentHubScreen({super.key});

  @override
  ConsumerState<AgentHubScreen> createState() => _AgentHubScreenState();
}

class _AgentHubScreenState extends ConsumerState<AgentHubScreen> {
  String _district = NationalMetros.all.first.name;
  AgentHubResponse? _result;
  bool _loading = false;
  bool _showTechnicalDetail = false;
  _Decision _decision = _Decision.none;

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _result = null;
      _decision = _Decision.none;
    });
    final api = ref.read(preciopsApiProvider);
    AgentHubResponse? res;
    try {
      res = await api.runAgentHubAnalysis(_district);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, "Couldn't reach the Intelligence Hub — try again shortly.",
            kind: AppToastKind.error);
      }
    }
    if (!mounted) return;
    setState(() {
      if (res != null) _result = res;
      _loading = false;
    });
  }

  int get _completedCount {
    if (_result == null) return 0;
    final names = _result!.executionChain.map((s) => s.agentName).toSet();
    return _agentChecklist.where((c) => names.contains(c.agentName)).length;
  }

  // NOTE: the backend has no approve/reject persistence endpoint for agent
  // recommendations (only POST /api/agents/trigger exists, and main.py
  // never mounts that router) — this is a UI-only demo state: confirm ->
  // local state flip -> toast, not a real dispatch.
  Future<void> _confirmDecision(_Decision decision) async {
    final isApprove = decision == _Decision.approved;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isApprove ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
                color: isApprove ? AppColors.accent : AppColors.dangerStrong,
                size: 26,
              ),
              const SizedBox(height: 14),
              Text(
                isApprove ? 'Approve deployment?' : 'Reject this recommendation?',
                style: AppTypography.sectionTitle(),
              ),
              const SizedBox(height: 8),
              Text(
                isApprove
                    ? 'This confirms the recommended resources should be dispatched for $_district.'
                    : 'The recommendation for $_district will be marked rejected and no resources dispatched.',
                style: AppTypography.body(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: AppButton.tertiary(
                      label: 'Cancel',
                      expand: true,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(
                      label: isApprove ? 'Approve' : 'Reject',
                      color: isApprove ? null : AppColors.dangerStrong,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _decision = decision);
      AppToast.show(
        context,
        isApprove ? 'Deployment approved for $_district.' : 'Recommendation rejected.',
        kind: isApprove ? AppToastKind.success : AppToastKind.neutral,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Intelligence')),
      body: RoleGate(
        allowed: const [UserRole.official],
        currentRole: auth.user?.role,
        featureName: 'Emergency Intelligence',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.sm,
            AppSpacing.screenPadding,
            AppSpacing.xxl,
          ),
          children: [
            DistrictDropdown(
              value: _district,
              label: 'Sector / District',
              onChanged: (v) => setState(() => _district = v),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: _loading ? 'Analysing…' : 'Run Situation Analysis',
              icon: Icons.hub_outlined,
              isLoading: _loading,
              onPressed: _run,
            ),
            if (_result != null) ...[
              const SectionHeader(title: 'Progress'),
              AppCard(
                child: Column(
                  children: [
                    for (final step in _agentChecklist)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Row(
                          children: [
                            Icon(
                              _result!.executionChain.any((s) => s.agentName == step.agentName)
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: _result!.executionChain.any((s) => s.agentName == step.agentName)
                                  ? AppColors.accent
                                  : AppColors.textTertiary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Icon(step.icon, size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Text(step.label, style: AppTypography.body()),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SectionHeader(title: 'Recommendation'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _alertBadge(_result!.alertLevel),
                        const Spacer(),
                        Text(_result!.district, style: AppTypography.cardTitle()),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _result!.coordinatorSummary,
                      style: AppTypography.body(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _completedCount >= _agentChecklist.length
                          ? 'Confidence: High — $_completedCount/${_agentChecklist.length} agents completed'
                          : 'Confidence: Moderate — partial analysis ($_completedCount/${_agentChecklist.length})',
                      style: AppTypography.label(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_decision == _Decision.none)
                Row(
                  children: [
                    Expanded(
                      child: AppButton.secondary(
                        label: 'Reject',
                        icon: Icons.close_rounded,
                        color: AppColors.dangerStrong,
                        onPressed: () => _confirmDecision(_Decision.rejected),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: 'Approve Deployment',
                        icon: Icons.check_rounded,
                        onPressed: () => _confirmDecision(_Decision.approved),
                      ),
                    ),
                  ],
                )
              else
                StatusBadge(
                  label: _decision == _Decision.approved ? 'Deployment Approved' : 'Recommendation Rejected',
                  color: _decision == _Decision.approved ? AppColors.accent : AppColors.dangerStrong,
                  icon: _decision == _Decision.approved ? Icons.check_circle : Icons.cancel,
                  filled: true,
                ),
              const SizedBox(height: AppSpacing.section),
              GestureDetector(
                onTap: () => setState(() => _showTechnicalDetail = !_showTechnicalDetail),
                child: Row(
                  children: [
                    Text('View AI Insights', style: AppTypography.label(color: AppColors.info).copyWith(fontWeight: FontWeight.w600)),
                    Icon(
                      _showTechnicalDetail ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: AppColors.info,
                      size: 18,
                    ),
                  ],
                ),
              ),
              if (_showTechnicalDetail) ...[
                const SizedBox(height: AppSpacing.sm),
                for (final step in _result!.executionChain)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: AppCard(
                      color: AppColors.surfaceRaised,
                      padding: const EdgeInsets.all(13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(step.agentName, style: AppTypography.cardTitle().copyWith(fontSize: 13.5)),
                          const SizedBox(height: 4),
                          Text(step.finding, style: AppTypography.body(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _alertBadge(AlertLevel level) {
    final color = switch (level) {
      AlertLevel.green => AppColors.accent,
      AlertLevel.yellow => AppColors.warning,
      AlertLevel.orange => AppColors.danger,
      AlertLevel.red => AppColors.dangerStrong,
    };
    // Orange vs. red are both real backend alert levels — told apart by
    // fill weight since the palette only has one strong red.
    final filled = level == AlertLevel.red || level == AlertLevel.green;
    return StatusBadge(
      label: level.label,
      color: color,
      icon: Icons.notifications_active_outlined,
      filled: filled,
    );
  }
}
