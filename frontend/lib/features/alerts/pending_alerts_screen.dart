import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models/alert_models.dart';
import '../../api/models/auth_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_badge.dart';
import '../profile/role_gate.dart';

/// HITL gate for the citizen-facing high_risk_alert push: a model-detected
/// high-risk transition creates a pending row here instead of pushing
/// straight to citizens (see the hourly flood-risk pipeline job in main.py). Only
/// once a volunteer or official approves it does the actual push fire
/// (POST /api/alerts/{id}/approve), matching this app's "no alert reaches
/// citizens without a human sign-off" requirement.
class PendingAlertsScreen extends ConsumerWidget {
  const PendingAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pending Alerts')),
      body: RoleGate(
        allowed: const [UserRole.volunteer, UserRole.official],
        currentRole: auth.user?.role,
        featureName: 'Pending Alerts',
        child: const _PendingAlertsBody(),
      ),
    );
  }
}

class _PendingAlertsBody extends ConsumerStatefulWidget {
  const _PendingAlertsBody();

  @override
  ConsumerState<_PendingAlertsBody> createState() => _PendingAlertsBodyState();
}

class _PendingAlertsBodyState extends ConsumerState<_PendingAlertsBody> {
  List<PendingAlert>? _alerts;
  bool _loading = true;
  final Set<int> _resolving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final api = ref.read(preciopsApiProvider);
    List<PendingAlert> alerts = const [];
    try {
      alerts = await api.getPendingAlerts();
    } catch (_) {
      if (mounted) {
        AppToast.show(context, "Couldn't load pending alerts — check your connection and try again.",
            kind: AppToastKind.error);
      }
    }
    if (!mounted) return;
    setState(() {
      _alerts = alerts;
      _loading = false;
    });
  }

  Future<void> _decide(PendingAlert alert, bool approve) async {
    setState(() => _resolving.add(alert.id));
    final api = ref.read(preciopsApiProvider);
    try {
      if (approve) {
        await api.approveAlert(alert.id);
      } else {
        await api.rejectAlert(alert.id);
      }
      if (mounted) {
        setState(() => _alerts?.removeWhere((a) => a.id == alert.id));
        AppToast.show(
          context,
          approve
              ? 'Alert approved — citizens in ${alert.district} are being notified now.'
              : 'Alert rejected — no push sent for ${alert.district}.',
          kind: approve ? AppToastKind.success : AppToastKind.neutral,
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, "Couldn't record your decision — check your connection and try again.",
            kind: AppToastKind.error);
      }
    }
    if (mounted) setState(() => _resolving.remove(alert.id));
  }

  Color _levelColor(String level) => switch (level.toUpperCase()) {
        'CRITICAL' => AppColors.dangerStrong,
        'WARNING' => AppColors.warning,
        _ => AppColors.accent,
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.4));
    }
    final alerts = _alerts ?? const [];
    return RefreshIndicator(
      onRefresh: _load,
      child: alerts.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Text('No pending alerts', style: AppTypography.body(color: AppColors.textSecondary)),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.md,
                AppSpacing.screenPadding,
                AppSpacing.xxl,
              ),
              itemCount: alerts.length,
              itemBuilder: (context, i) {
                final alert = alerts[i];
                final busy = _resolving.contains(alert.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(alert.district, style: AppTypography.cardTitle()),
                            ),
                            StatusBadge(
                              label: alert.alertLevel,
                              color: _levelColor(alert.alertLevel),
                              icon: Icons.warning_amber_rounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(alert.message, style: AppTypography.body(color: AppColors.textSecondary)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (alert.riskScore != null) ...[
                              Text('Risk score: ${alert.riskScore}',
                                  style: AppTypography.caption(color: AppColors.textTertiary)),
                              const SizedBox(width: 10),
                            ],
                            Text(DateFormat.MMMd().add_Hm().format(alert.createdAt),
                                style: AppTypography.caption(color: AppColors.textTertiary)),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: AppButton.secondary(
                                label: 'Reject',
                                color: AppColors.dangerStrong,
                                isLoading: busy,
                                onPressed: busy ? null : () => _decide(alert, false),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: AppButton(
                                label: 'Approve',
                                isLoading: busy,
                                onPressed: busy ? null : () => _decide(alert, true),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
