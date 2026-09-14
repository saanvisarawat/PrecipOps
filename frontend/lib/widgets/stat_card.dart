import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radius.dart';

/// Premium metric surface: small muted label, a dominant value, an
/// optional icon and trend line — sits on the bg-colored screen so it
/// visibly lifts off the background via a hairline border + soft shadow,
/// never a heavy Material drop shadow.
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? accent;
  final Color? valueColor;
  final String? trend;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accent,
    this.valueColor,
    this.trend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardR,
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppColors.softShadow(opacity: 0.24, blur: 16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: accent ?? AppColors.textTertiary),
            const SizedBox(height: 10),
          ],
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Inter',
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
          if (trend != null) ...[
            const SizedBox(height: 3),
            Text(
              trend!,
              style: const TextStyle(
                fontFamily: 'Inter',
                color: AppColors.accent,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 2-column grid of [StatCard]s, spaced so each card reads as its own
/// lifted surface rather than a packed table.
class StatGrid extends StatelessWidget {
  final List<StatCard> cards;

  const StatGrid({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.25,
      children: cards,
    );
  }
}
