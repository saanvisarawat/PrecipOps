import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models/admin_report_models.dart';
import '../../api/models/auth_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_badge.dart';
import '../profile/role_gate.dart';

/// Official-only view of every citizen SOS report regardless of status
/// (GET /api/officials/reports) — distinct from the citizen/volunteer
/// Community Reports feed, which only ever shows status=="verified" rows,
/// and from a volunteer's own task list, which only shows reports already
/// assigned to them. Lets an official manually dispatch a report to a
/// specific volunteer (POST /api/officials/reports/{id}/assign) — the
/// fallback for when allocate_resources_for_sos found nobody available
/// within 5km at creation time.
class OfficialSosDashboardScreen extends ConsumerWidget {
  const OfficialSosDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('SOS Dashboard')),
      body: RoleGate(
        allowed: const [UserRole.official],
        currentRole: auth.user?.role,
        featureName: 'the SOS Dashboard',
        child: const _SosDashboardBody(),
      ),
    );
  }
}

class _SosDashboardBody extends ConsumerStatefulWidget {
  const _SosDashboardBody();

  @override
  ConsumerState<_SosDashboardBody> createState() => _SosDashboardBodyState();
}

class _SosDashboardBodyState extends ConsumerState<_SosDashboardBody> {
  List<AdminReport>? _reports;
  List<AdminVolunteer> _volunteers = const [];
  bool _loading = true;
  final Set<int> _assigning = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final api = ref.read(preciopsApiProvider);
    List<AdminReport> reports = const [];
    List<AdminVolunteer> volunteers = const [];
    try {
      final results = await Future.wait([api.getAllReportsAdmin(), api.getAllVolunteersAdmin()]);
      reports = results[0] as List<AdminReport>;
      volunteers = results[1] as List<AdminVolunteer>;
    } catch (_) {
      if (mounted) {
        AppToast.show(context, "Couldn't load the SOS dashboard — check your connection and try again.",
            kind: AppToastKind.error);
      }
    }
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _volunteers = volunteers;
      _loading = false;
    });
  }

  Future<void> _pickVolunteerAndAssign(AdminReport report) async {
    final volunteer = await AppBottomSheet.show<AdminVolunteer>(
      context,
      builder: (context) => _VolunteerPickerSheet(volunteers: _volunteers),
    );
    if (volunteer == null || !mounted) return;

    setState(() => _assigning.add(report.id));
    final api = ref.read(preciopsApiProvider);
    try {
      final updated = await api.assignReportToVolunteer(report.id, volunteer.id);
      if (mounted) {
        setState(() {
          final index = _reports?.indexWhere((r) => r.id == report.id) ?? -1;
          if (index != -1) _reports![index] = updated;
        });
        AppToast.show(context, 'Dispatched to ${volunteer.fullName}.', kind: AppToastKind.success);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, "Couldn't assign this report — check your connection and try again.",
            kind: AppToastKind.error);
      }
    }
    if (mounted) setState(() => _assigning.remove(report.id));
  }

  Color _statusColor(String status) => switch (status) {
        'dispatched' => AppColors.info,
        'verified' => AppColors.accent,
        'false_alarm' => AppColors.textTertiary,
        _ => AppColors.warning,
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.4));
    }
    final reports = _reports ?? const [];
    return RefreshIndicator(
      onRefresh: _load,
      child: reports.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Text('No citizen reports yet', style: AppTypography.body(color: AppColors.textSecondary)),
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
              itemCount: reports.length,
              itemBuilder: (context, i) {
                final report = reports[i];
                final busy = _assigning.contains(report.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(report.description, style: AppTypography.cardTitle()),
                            ),
                            StatusBadge(
                              label: report.status.replaceAll('_', ' ').toUpperCase(),
                              color: _statusColor(report.status),
                              icon: Icons.emergency_outlined,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${report.latitude.toStringAsFixed(4)}, ${report.longitude.toStringAsFixed(4)}',
                          style: AppTypography.caption(color: AppColors.textTertiary),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text('${report.yesCount} confirmed · ${report.noCount} disputed',
                                style: AppTypography.caption(color: AppColors.textTertiary)),
                            if (report.clientTimestamp != null) ...[
                              const SizedBox(width: 10),
                              // client_timestamp arrives as a UTC-aware
                              // ISO timestamp (Report.client_timestamp is a
                              // `DateTime(timezone=True)` column) — without
                              // .toLocal() this rendered the raw UTC clock
                              // instead of the official's own local time.
                              Text(DateFormat.MMMd().add_Hm().format(report.clientTimestamp!.toLocal()),
                                  style: AppTypography.caption(color: AppColors.textTertiary)),
                            ],
                          ],
                        ),
                        if (report.isAssigned) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.person_pin_circle_outlined, size: 16, color: AppColors.info),
                              const SizedBox(width: 4),
                              Text('Assigned to ${report.assignedVolunteerName ?? 'volunteer #${report.assignedVolunteerId}'}',
                                  style: AppTypography.caption(color: AppColors.info)),
                            ],
                          ),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        AppButton.secondary(
                          label: report.isAssigned ? 'Reassign' : 'Dispatch a Volunteer',
                          isLoading: busy,
                          onPressed: busy ? null : () => _pickVolunteerAndAssign(report),
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

class _VolunteerPickerSheet extends StatelessWidget {
  final List<AdminVolunteer> volunteers;
  const _VolunteerPickerSheet({required this.volunteers});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dispatch to', style: AppTypography.sectionTitle()),
        const SizedBox(height: AppSpacing.sm),
        if (volunteers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text('No volunteers registered yet.', style: AppTypography.body(color: AppColors.textSecondary)),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: volunteers.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, i) {
                final v = volunteers[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => Navigator.of(context).pop(v),
                  leading: StatusBadge(
                    label: v.status.toUpperCase(),
                    color: v.isAvailable ? AppColors.accent : AppColors.textTertiary,
                    icon: Icons.circle,
                    dot: true,
                  ),
                  title: Text(v.fullName, style: AppTypography.body()),
                  subtitle: v.skills != null ? Text(v.skills!, style: AppTypography.caption(color: AppColors.textTertiary)) : null,
                );
              },
            ),
          ),
      ],
    );
  }
}
