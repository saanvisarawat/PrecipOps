import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_typography.dart';
import '../models/route_option.dart';

/// Floating "21 min / Suggested" label anchored to a route's midpoint on
/// the map. The selected route reads visually stronger (filled accent);
/// others sit muted until tapped.
class RouteSummaryLabel extends StatelessWidget {
  final RouteOption route;
  final bool selected;
  final VoidCallback onTap;

  const RouteSummaryLabel({super.key, required this.route, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surfaceRaised.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.accent : AppColors.cardBorder),
          boxShadow: AppColors.softShadow(opacity: 0.25, blur: 12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              route.durationLabel,
              style: AppTypography.cardTitle(color: selected ? Colors.black : AppColors.textPrimary).copyWith(fontSize: 14),
            ),
            Text(
              route.rank.label,
              style: AppTypography.caption(color: selected ? Colors.black87 : AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
