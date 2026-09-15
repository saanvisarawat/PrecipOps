import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models/dashboard_event_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/service_providers.dart';
import '../../providers/stream_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_badge.dart';

/// Evacuation Alerts feed (Agent 3 spec) — every `sos_verified` event on
/// this same stream is the exact moment the backend's `verify_report`
/// handler both flips the ticket to "verified" AND fires the n8n webhook
/// that dispatches the automated Twilio SMS (see `app/main.py`), so an
/// alert appearing here is the visible confirmation that dispatch fired.
/// `new_sos_pending` events are also shown, one tier down, as "reported —
/// awaiting verification." No new backend call: this reuses the same
/// `dashboardEventStreamProvider` (ws://.../ws/dashboard) the Official
/// Command Center already listens to.
///
/// `high_risk_alert` events (model-determined, see `the hourly flood-risk pipeline job`
/// in `main.py`) are also shown here. The actual push notification for one
/// is fired app-wide by [riskPushNotifierProvider] (watched from
/// `ShellScreen`, not here) so it still fires even when this tab isn't
/// open — this screen only renders the feed.
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  final List<DashboardEvent> _events = [];
  bool _requestingPermission = false;

  void _handleEvent(DashboardEvent event) {
    setState(() {
      _events.insert(0, event);
      if (_events.length > 50) _events.removeLast();
    });
  }

  /// Browsers (Chrome included) routinely suppress a Notification-permission
  /// prompt that isn't triggered by a direct user gesture — requesting it
  /// silently at app launch, as this app also does as a best-effort, can
  /// leave permission stuck at "default" forever. A real button tap here
  /// gives the browser a genuine user gesture to attach the prompt to.
  Future<void> _enablePushAlerts() async {
    setState(() => _requestingPermission = true);
    await ref.read(notificationServiceProvider).init();
    if (!mounted) return;
    setState(() => _requestingPermission = false);
    AppToast.show(
      context,
      'If your browser/device just asked for notification permission, choose Allow — '
      'otherwise the in-app banner below is still guaranteed to show verified alerts.',
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dashboardEventStreamProvider, (previous, next) {
      next.whenData(_handleEvent);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Evacuation Alerts')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.sm,
              AppSpacing.screenPadding,
              0,
            ),
            child: AppCard(
              color: AppColors.surfaceRaised,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.campaign_outlined, color: AppColors.info, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Verified emergencies are automatically dispatched via SMS to nearby '
                          'responders through the n8n/Twilio pipeline.',
                          style: AppTypography.caption(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton.secondary(
                    label: 'Enable Push Alerts',
                    icon: Icons.notifications_active_outlined,
                    isLoading: _requestingPermission,
                    onPressed: _enablePushAlerts,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _events.isEmpty
                ? Center(
                    child: Text('No alerts yet', style: AppTypography.body(color: AppColors.textSecondary)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenPadding,
                      AppSpacing.md,
                      AppSpacing.screenPadding,
                      AppSpacing.xxl,
                    ),
                    itemCount: _events.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _AlertTile(event: _events[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final DashboardEvent event;
  const _AlertTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final (icon, iconColor, title, body, badgeLabel, badgeColor, badgeIcon) = switch (event) {
      SosVerifiedEvent(:final ticketId, :final confirmCount) => (
          Icons.sms_rounded,
          AppColors.dangerStrong,
          'Emergency SMS Dispatched',
          'Ticket $ticketId verified by $confirmCount nearby users — responders alerted.',
          'Verified',
          AppColors.accent,
          Icons.verified_rounded,
        ),
      HighRiskAlertEvent(:final district, :final riskScore, :final alertLevel) => (
          Icons.warning_amber_rounded,
          AppColors.dangerStrong,
          'High Flood Risk — $district',
          'Model risk score $riskScore% ($alertLevel).',
          alertLevel,
          AppColors.dangerStrong,
          Icons.warning_amber_rounded,
        ),
      NewSosPendingEvent(:final description) => (
          Icons.report_gmailerrorred_rounded,
          AppColors.warning,
          'New SOS Reported',
          description,
          'Awaiting verification',
          AppColors.warning,
          Icons.hourglass_bottom_rounded,
        ),
      VolunteerAssignedEvent(:final ticketId, :final assignedVolunteerName) => (
          Icons.groups_rounded,
          AppColors.info,
          'Volunteer Assigned',
          assignedVolunteerName != null
              ? '$assignedVolunteerName was dispatched to ticket $ticketId.'
              : 'A volunteer was dispatched to ticket $ticketId.',
          'Dispatched',
          AppColors.info,
          Icons.groups_rounded,
        ),
      VolunteerEnRouteEvent(:final ticketId, :final volunteerName) => (
          Icons.directions_run_rounded,
          AppColors.accent,
          'Volunteer On The Way',
          volunteerName != null
              ? '$volunteerName accepted and is en route to ticket $ticketId.'
              : 'A volunteer accepted and is en route to ticket $ticketId.',
          'En Route',
          AppColors.accent,
          Icons.directions_run_rounded,
        ),
      AdvisoryBroadcastEvent(:final district, :final alertMessage) => (
          Icons.campaign_rounded,
          AppColors.dangerStrong,
          'IMD Advisory — $district',
          alertMessage,
          'Broadcast',
          AppColors.dangerStrong,
          Icons.campaign_rounded,
        ),
      GroundTruthSubmittedEvent(:final district, :final observedWaterDepthMeters, :final description) => (
          Icons.fact_check_rounded,
          AppColors.info,
          'Ground Report — $district',
          '${observedWaterDepthMeters.toStringAsFixed(2)}m observed. $description',
          'Ground Truth',
          AppColors.info,
          Icons.fact_check_rounded,
        ),
    };
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.cardTitle().copyWith(fontSize: 14.5)),
                const SizedBox(height: 4),
                Text(body, style: AppTypography.body(color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    StatusBadge(label: badgeLabel, color: badgeColor, icon: badgeIcon),
                    const SizedBox(width: 8),
                    Text(DateFormat.Hm().format(event.timestamp), style: AppTypography.caption()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
