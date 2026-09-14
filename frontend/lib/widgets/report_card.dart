import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/models/report_models.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import 'app_card.dart';
import 'app_button.dart';
import 'status_badge.dart';

class ReportCard extends StatelessWidget {
  final ReportSummary report;
  final VoidCallback? onConfirm;
  final VoidCallback? onFalseAlarm;
  final bool compact;

  const ReportCard({
    super.key,
    required this.report,
    this.onConfirm,
    this.onFalseAlarm,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isVerified = report.status == ReportStatus.verified;
    final badgeColor = isVerified ? AppColors.dangerStrong : AppColors.warning;
    final distanceLabel = report.distanceMeters < 1000
        ? '${report.distanceMeters.round()} m'
        : '${(report.distanceMeters / 1000).toStringAsFixed(1)} km';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Emergency-report row: a plain status strip (never a circular
          // avatar) plus location/time/distance metadata — deliberately
          // reads as an incident record, not a social feed post.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 40,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isVerified ? Icons.verified_rounded : Icons.report_problem_outlined,
                          color: badgeColor,
                          size: 15,
                        ),
                        const SizedBox(width: 6),
                        Text(report.ticketId, style: AppTypography.caption()),
                        const Spacer(),
                        Text(
                          // reportedAt comes off the wire as a UTC-aware
                          // DateTime (server's client_timestamp) — format it
                          // in the viewer's own timezone, not raw UTC.
                          '$distanceLabel · ${DateFormat.Hm().format(report.reportedAt.toLocal())}',
                          style: AppTypography.caption(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      report.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.cardTitle().copyWith(fontSize: 14.5, height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    if (isVerified)
                      const StatusBadge(
                        label: 'Verified',
                        color: AppColors.dangerStrong,
                        icon: Icons.verified,
                        filled: true,
                      )
                    else
                      StatusBadge(
                        label: '${report.confirmCount}/3 verified',
                        color: AppColors.warning,
                        icon: Icons.hourglass_bottom,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (!compact && !isVerified && (onConfirm != null || onFalseAlarm != null)) ...[
            const SizedBox(height: AppSpacing.comfortable),
            Row(
              children: [
                Expanded(
                  child: AppButton.secondary(
                    label: 'False Alarm',
                    icon: Icons.close,
                    onPressed: onFalseAlarm,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'Confirm Hazard',
                    icon: Icons.check,
                    onPressed: onConfirm,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
