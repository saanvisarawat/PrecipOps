import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/report_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/api_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/report_card.dart';

/// Crowdsourced verification radar (module 6). Confirm/False-Alarm votes
/// auto-tag a report "Verified Emergency" once the tally hits 3, mirroring
/// the mocked POST /api/reports/{ticket_id}/verify tally logic.
class VerificationFeedScreen extends ConsumerStatefulWidget {
  const VerificationFeedScreen({super.key});

  @override
  ConsumerState<VerificationFeedScreen> createState() => _VerificationFeedScreenState();
}

class _VerificationFeedScreenState extends ConsumerState<VerificationFeedScreen> {
  List<ReportSummary>? _reports;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(preciopsApiProvider);
    double? lat;
    double? lng;
    try {
      final pos = await ref.read(locationServiceProvider).getCurrentPosition();
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      // Proceed without a location fix — distances just won't be sorted.
    }
    List<ReportSummary> reports = const [];
    try {
      reports = await api.getReports(nearLat: lat, nearLng: lng);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, "Couldn't load reports — check your connection.", kind: AppToastKind.error);
      }
    }
    if (!mounted) return;
    setState(() => _reports = reports);
  }

  Future<void> _vote(ReportSummary report, VerifyVote vote) async {
    final api = ref.read(preciopsApiProvider);
    ReportSummary? updated;
    try {
      updated = await api.verifyReport(report.ticketId, vote);
    } catch (_) {
      // /api/reports/{id}/verify is a no-login citizen feature — a
      // failure here is a network/server issue, not an auth gate.
      if (mounted) {
        AppToast.show(context, "Couldn't record your vote — check your connection and try again.", kind: AppToastKind.error);
      }
    }
    if (!mounted || updated == null) return;
    setState(() {
      final index = _reports!.indexWhere((r) => r.ticketId == report.ticketId);
      if (index != -1) _reports![index] = updated!;
    });
    if (updated.status == ReportStatus.verified) {
      AppToast.show(context, '${updated.ticketId} auto-tagged Verified Emergency', kind: AppToastKind.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_reports == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.comfortable,
          AppSpacing.screenPadding,
          110,
        ),
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppSkeleton(height: 104, borderRadius: AppRadius.cardR),
            ),
        ],
      );
    }
    final pending = _reports!.where((r) => r.status != ReportStatus.verified).toList();
    final verified = _reports!.where((r) => r.status == ReportStatus.verified).toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      backgroundColor: AppColors.surfaceHigh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.comfortable,
          AppSpacing.screenPadding,
          110,
        ),
        children: [
          Text('Unverified (${pending.length})', style: AppTypography.sectionTitle()),
          const SizedBox(height: AppSpacing.sm),
          if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.section),
              child: Column(
                children: [
                  const Icon(Icons.verified_outlined, color: AppColors.textTertiary, size: 26),
                  const SizedBox(height: 8),
                  Text('Nothing to verify right now', style: AppTypography.body(color: AppColors.textSecondary)),
                ],
              ),
            ),
          for (final r in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ReportCard(
                report: r,
                onConfirm: () => _vote(r, VerifyVote.confirm),
                onFalseAlarm: () => _vote(r, VerifyVote.falseAlarm),
              ),
            ),
          if (verified.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Verified Emergencies (${verified.length})', style: AppTypography.sectionTitle()),
            const SizedBox(height: AppSpacing.sm),
            for (final r in verified)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ReportCard(report: r, compact: true),
              ),
          ],
        ],
      ),
    );
  }
}
