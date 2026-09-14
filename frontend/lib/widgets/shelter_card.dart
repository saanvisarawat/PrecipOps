import 'package:flutter/material.dart';

import '../api/models/shelter_models.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import 'app_card.dart';
import 'status_badge.dart';

class ShelterCard extends StatelessWidget {
  final ShelterFeature shelter;
  final VoidCallback? onTap;
  final double width;
  /// Optional straight-line distance from the viewer, shown next to the
  /// district when present (used by the "Shelters Near Me" list).
  final double? distanceKm;

  const ShelterCard({super.key, required this.shelter, this.onTap, this.width = 220, this.distanceKm});

  @override
  Widget build(BuildContext context) {
    final ratio = shelter.occupancyRatio;
    final Color statusColor;
    final String statusLabel;
    final IconData statusIcon;
    if (ratio >= 1.0) {
      statusColor = AppColors.danger;
      statusLabel = 'Full';
      statusIcon = Icons.block;
    } else if (ratio >= 0.75) {
      statusColor = AppColors.warning;
      statusLabel = 'Nearly Full';
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusColor = AppColors.accent;
      statusLabel = 'Space Available';
      statusIcon = Icons.check_circle_outline;
    }

    return SizedBox(
      width: width,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.home_work_outlined, color: AppColors.accent, size: 18),
                ),
                const Spacer(),
                StatusBadge(label: statusLabel, color: statusColor, icon: statusIcon),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              shelter.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.cardTitle().copyWith(fontSize: 13, height: 1.25),
            ),
            const SizedBox(height: 3),
            Text(
              distanceKm == null ? shelter.district : '${shelter.district} · ${distanceKm!.toStringAsFixed(1)} km',
              style: AppTypography.caption(),
            ),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio.clamp(0, 1),
                minHeight: 5,
                backgroundColor: AppColors.surfaceHigh,
                color: statusColor,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${shelter.currentOccupancy}/${shelter.capacity} occupied',
              style: AppTypography.caption(),
            ),
          ],
        ),
      ),
    );
  }
}
