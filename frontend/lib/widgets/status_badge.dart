import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// Semantic-color status indicator. Two styles:
///   dot   — a small colored dot + muted label (the default, preferred
///           "elegant" reading per the design system — e.g. "● Active").
///   badge — a soft-tinted (or filled) pill with an icon, for cases that
///           need more visual weight (e.g. "Verified Emergency").
/// Meaning never rests on color alone — always paired with text/icon.
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool filled;
  final bool dot;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
    this.filled = false,
    this.dot = false,
  });

  @override
  Widget build(BuildContext context) {
    if (dot) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    // A bright fill needs a dark foreground to stay legible.
    final onFill = color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: filled ? onFill : color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              color: filled ? onFill : color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
