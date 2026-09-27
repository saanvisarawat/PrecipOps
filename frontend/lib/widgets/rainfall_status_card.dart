import 'package:flutter/material.dart';

import '../api/models/kerala_telemetry_models.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import 'app_card.dart';
import 'status_badge.dart';

/// A compact, plain-language rainfall reading for one district — powered
/// by the same POST /api/ml/predict-kerala feed as the Predictor
/// Dashboard's 4-Pillar HUD, but boiled down to the one number a citizen
/// or volunteer actually cares about day-to-day: how hard is it raining
/// right now. Shown alongside whatever else is already on a screen, not a
/// replacement for it.
class RainfallStatusCard extends StatelessWidget {
  final String district;
  final KeralaPredictionResponse? data;
  final bool loading;
  final String? error;

  const RainfallStatusCard({
    super.key,
    required this.district,
    required this.data,
    required this.loading,
    this.error,
  });

  ({String label, Color color}) _status(double rateMmh) {
    if (rateMmh <= 0) return (label: 'No Rain', color: AppColors.textTertiary);
    if (rateMmh < 2.5) return (label: 'Light Rain', color: AppColors.info);
    if (rateMmh < 7.5) return (label: 'Moderate Rain', color: AppColors.warning);
    if (rateMmh < 35) return (label: 'Heavy Rain', color: AppColors.danger);
    return (label: 'Very Heavy Rain', color: AppColors.dangerStrong);
  }

  @override
  Widget build(BuildContext context) {
    if (loading && data == null) {
      return const AppCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.4)),
        ),
      );
    }
    if (error != null && data == null) {
      return AppCard(
        child: Text(error!, style: AppTypography.body(color: AppColors.textSecondary)),
      );
    }

    final aws = data?.telemetryPillars.observationalAws;
    final rate = aws?.currentRainRateMmh ?? 0;
    final status = _status(rate);

    return AppCard(
      child: Row(
        children: [
          Icon(Icons.water_drop_rounded, color: status.color, size: 24),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rainfall — $district',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.cardTitle(),
                ),
                const SizedBox(height: 2),
                Text('${rate.toStringAsFixed(1)} mm/hr', style: AppTypography.body(color: AppColors.textSecondary)),
              ],
            ),
          ),
          StatusBadge(label: status.label, color: status.color, icon: Icons.circle, dot: true),
        ],
      ),
    );
  }
}
