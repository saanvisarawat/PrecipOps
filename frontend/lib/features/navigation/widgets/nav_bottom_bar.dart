import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../utils/format.dart';

/// Bottom bar during active navigation: remaining ETA/distance + End
/// Route. Kept as its own small bar (not `AppBottomSheet`) since it must
/// stay fixed at the bottom throughout the drive, not be draggable.
class NavBottomBar extends StatelessWidget {
  final Duration remainingDuration;
  final double remainingDistanceMeters;
  final VoidCallback onEndRoute;

  const NavBottomBar({
    super.key,
    required this.remainingDuration,
    required this.remainingDistanceMeters,
    required this.onEndRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised.withValues(alpha: 0.96),
        borderRadius: AppRadius.panelR,
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppColors.softShadow(opacity: 0.35, blur: 20),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatDuration(remainingDuration), style: AppTypography.hero().copyWith(fontSize: 24)),
              Text(formatDistance(remainingDistanceMeters), style: AppTypography.label()),
            ],
          ),
          const Spacer(),
          Material(
            color: AppColors.dangerStrong,
            borderRadius: AppRadius.buttonR,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onEndRoute,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Text(
                  'END ROUTE',
                  style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
