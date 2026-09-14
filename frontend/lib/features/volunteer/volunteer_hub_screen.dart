import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models/auth_models.dart';
import '../../api/models/volunteer_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_button.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/app_toast.dart';
import '../profile/role_gate.dart';

class VolunteerHubScreen extends ConsumerStatefulWidget {
  const VolunteerHubScreen({super.key});

  @override
  ConsumerState<VolunteerHubScreen> createState() => _VolunteerHubScreenState();
}

class _VolunteerHubScreenState extends ConsumerState<VolunteerHubScreen> {
  DutyStatus _status = DutyStatus.offline;
  final Set<VolunteerSkill> _skills = {VolunteerSkill.medical};
  List<VolunteerTask>? _tasks;
  bool _updatingStatus = false;
  final Set<String> _accepting = {};

  Future<void> _loadTasks() async {
    final api = ref.read(preciopsApiProvider);
    List<VolunteerTask> tasks = const [];
    try {
      tasks = await api.getVolunteerTasks();
    } catch (_) {
      // Real backend requires a logged-in volunteer here (the mock never
      // did) — a guest or citizen gets a 401/403.
      if (mounted) {
        AppToast.show(context, "Couldn't load tasks — log in as a volunteer to see assignments.",
            kind: AppToastKind.error);
      }
    }
    if (mounted) setState(() => _tasks = tasks);
  }

  Future<void> _toggleStatus(bool onDuty) async {
    setState(() => _updatingStatus = true);
    final api = ref.read(preciopsApiProvider);
    double lat = 9.9816, lng = 76.2999; // Ernakulam fallback if GPS unavailable
    try {
      final pos = await ref.read(locationServiceProvider).getCurrentPosition();
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {}
    bool ok = true;
    try {
      await api.updateVolunteerLocation(VolunteerLocationUpdate(
        status: onDuty ? DutyStatus.available : DutyStatus.offline,
        skills: _skills.toList(),
        latitude: lat,
        longitude: lng,
      ));
    } catch (_) {
      ok = false;
      if (mounted) {
        AppToast.show(context, "Couldn't update duty status — please log in.", kind: AppToastKind.error);
      }
    }
    if (!mounted) return;
    setState(() {
      if (ok) _status = onDuty ? DutyStatus.available : DutyStatus.offline;
      _updatingStatus = false;
    });
    if (ok && onDuty && _tasks == null) _loadTasks();
  }

  Future<void> _accept(VolunteerTask task) async {
    setState(() => _accepting.add(task.taskId));
    final api = ref.read(preciopsApiProvider);
    final volunteerName = ref.read(authProvider).user?.fullName ?? 'Volunteer';
    try {
      final updated = await api.acceptTask(task: task, volunteerName: volunteerName);
      if (mounted) {
        setState(() {
          final index = _tasks?.indexWhere((t) => t.taskId == task.taskId) ?? -1;
          if (index != -1) _tasks![index] = updated;
        });
        AppToast.show(context, 'Accepted — the citizen has been notified you\'re on the way.', kind: AppToastKind.success);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, "Couldn't accept this task — check your connection and try again.", kind: AppToastKind.error);
      }
    }
    if (mounted) setState(() => _accepting.remove(task.taskId));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Volunteer Command Hub')),
      body: RoleGate(
        allowed: const [UserRole.volunteer],
        currentRole: auth.user?.role,
        featureName: 'the Volunteer Command Hub',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.md,
            AppSpacing.screenPadding,
            AppSpacing.xxl,
          ),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Duty Status', style: AppTypography.cardTitle()),
                      if (_updatingStatus)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                        )
                      else
                        CupertinoSwitch(
                          value: _status == DutyStatus.available,
                          activeTrackColor: AppColors.accent,
                          onChanged: _toggleStatus,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  StatusBadge(
                    label: _status == DutyStatus.available ? 'Active' : 'Offline',
                    color: _status == DutyStatus.available ? AppColors.accent : AppColors.textTertiary,
                    icon: Icons.circle,
                    dot: true,
                  ),
                  const SizedBox(height: AppSpacing.comfortable),
                  Text('Skills', style: AppTypography.cardTitle()),
                  const SizedBox(height: AppSpacing.compact),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final skill in VolunteerSkill.values)
                        FilterChip(
                          label: Text(skill.label),
                          selected: _skills.contains(skill),
                          onSelected: (sel) {
                            setState(() {
                              if (sel) {
                                _skills.add(skill);
                              } else {
                                _skills.remove(skill);
                              }
                            });
                          },
                          selectedColor: AppColors.accent.withValues(alpha: 0.16),
                          checkmarkColor: AppColors.accent,
                          labelStyle: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _skills.contains(skill) ? AppColors.accent : AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.section),
            AppCard(
              onTap: () => context.push('/responder'),
              child: Row(
                children: [
                  const Icon(Icons.analytics_outlined, color: AppColors.accent, size: 22),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Inundation & Storm Outlook', style: AppTypography.cardTitle()),
                        const SizedBox(height: 2),
                        Text('City-wide flood risk, radar & IMD advisory',
                            style: AppTypography.caption(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              onTap: () => context.push('/pending-alerts'),
              child: Row(
                children: [
                  const Icon(Icons.campaign_outlined, color: AppColors.dangerStrong, size: 22),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pending Alerts', style: AppTypography.cardTitle()),
                        const SizedBox(height: 2),
                        Text('Review and approve model-detected high-risk alerts',
                            style: AppTypography.caption(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.section),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Assigned Tasks', style: AppTypography.sectionTitle()),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
                  onPressed: _loadTasks,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_tasks == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.section),
                child: Center(
                  child: Text(
                    'Go on duty to load your task list.',
                    style: AppTypography.body(color: AppColors.textSecondary),
                  ),
                ),
              )
            else if (_tasks!.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.section),
                child: Center(
                  child: Text('No tasks assigned right now.', style: AppTypography.body(color: AppColors.textSecondary)),
                ),
              )
            else
              for (final task in _tasks!)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _TaskCard(
                    task: task,
                    accepting: _accepting.contains(task.taskId),
                    onAccept: () => _accept(task),
                  ),
                ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              color: AppColors.surfaceRaised,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.notifications_active_outlined, color: AppColors.info, size: 18),
                      const SizedBox(width: 8),
                      Text('Masked Call Push', style: AppTypography.cardTitle().copyWith(fontSize: 14.5)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  StatusBadge(
                    label: ref.watch(firebaseReadyProvider) ? 'Firebase connected — real push active' : 'Firebase not configured — demo mode',
                    color: ref.watch(firebaseReadyProvider) ? AppColors.accent : AppColors.warning,
                    icon: ref.watch(firebaseReadyProvider) ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                    dot: true,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      const Icon(Icons.bug_report_outlined, color: AppColors.warning, size: 18),
                      const SizedBox(width: 8),
                      Text('Debug Trigger', style: AppTypography.cardTitle().copyWith(fontSize: 14.5)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Simulates the FCM data payload (type: EMERGENCY_INCOMING_CALL) that a '
                    'real dispatch sends via POST /api/emergency/trigger-masked-call.',
                    style: AppTypography.body(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton.secondary(
                    label: 'Simulate Incoming Emergency Call',
                    icon: Icons.call,
                    color: AppColors.danger,
                    onPressed: () => ref.read(preciopsApiProvider).simulateIncomingCall(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final VolunteerTask task;
  final bool accepting;
  final VoidCallback onAccept;
  const _TaskCard({required this.task, required this.accepting, required this.onAccept});

  Color _priorityColor(TaskPriority p) => switch (p) {
        TaskPriority.critical => AppColors.dangerStrong,
        TaskPriority.high => AppColors.danger,
        TaskPriority.medium => AppColors.warning,
        TaskPriority.low => AppColors.accent,
      };

  @override
  Widget build(BuildContext context) {
    final color = _priorityColor(task.priority);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(Icons.route_outlined, color: color, size: 19),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.description, style: AppTypography.cardTitle().copyWith(fontSize: 14.5)),
                    const SizedBox(height: 4),
                    Text(
                      '${task.district} • ${task.sosTicketId} • ${task.status.label}',
                      style: AppTypography.caption(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusBadge(
                    label: task.priority.label,
                    color: color,
                    icon: Icons.priority_high,
                    filled: task.priority == TaskPriority.critical,
                  ),
                  const SizedBox(height: 6),
                  Text('${task.distanceKm.toStringAsFixed(1)} km', style: AppTypography.caption()),
                ],
              ),
            ],
          ),
          if (task.status == TaskStatus.assigned) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: accepting ? 'Accepting…' : 'Accept',
              icon: Icons.check_rounded,
              isLoading: accepting,
              onPressed: accepting ? null : onAccept,
            ),
          ] else if (task.status == TaskStatus.enRoute) ...[
            const SizedBox(height: AppSpacing.sm),
            const StatusBadge(
              label: 'En Route — citizen notified',
              color: AppColors.accent,
              icon: Icons.directions_run_rounded,
              filled: true,
            ),
          ],
        ],
      ),
    );
  }
}
