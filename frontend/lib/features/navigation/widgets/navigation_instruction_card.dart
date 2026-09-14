import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/route_option.dart';
import '../utils/format.dart';

/// Top card during active navigation: maneuver icon, distance to it, and
/// the road name — the only thing the driver needs to glance at.
class NavigationInstructionCard extends StatelessWidget {
  final NavStep step;
  final double distanceToManeuverMeters;
  final bool isOfflineEstimate;

  const NavigationInstructionCard({
    super.key,
    required this.step,
    required this.distanceToManeuverMeters,
    required this.isOfflineEstimate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised.withValues(alpha: 0.96),
        borderRadius: AppRadius.cardR,
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppColors.softShadow(opacity: 0.3, blur: 18),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            child: Icon(step.icon, color: Colors.black, size: 26),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOfflineEstimate ? 'Head toward destination' : step.instruction,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.cardTitle().copyWith(fontSize: 17),
                ),
                const SizedBox(height: 3),
                Text(
                  isOfflineEstimate
                      ? '${formatDistance(distanceToManeuverMeters)} • offline straight-line guidance'
                      : [
                          formatDistance(distanceToManeuverMeters),
                          if (step.roadName != null) step.roadName!,
                        ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
