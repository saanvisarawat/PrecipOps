import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';

/// One floating glass circular control — current-location recenter,
/// compass reset, etc. Deliberately not `AppButton` (which is
/// text-first with a minimum 44-54px tap target); map controls are
/// icon-only circles floating over the map, Apple-Maps style.
class MapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;
  final double size;

  const MapControlButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconColor,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised.withValues(alpha: 0.85),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: AppColors.softShadow(opacity: 0.3, blur: 14),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              splashColor: AppColors.accentGlow,
              highlightColor: Colors.transparent,
              child: Icon(icon, color: iconColor ?? AppColors.textPrimary, size: size * 0.46),
            ),
          ),
        ),
      ),
    );
  }
}

/// Appears only while the map is rotated away from north-up — tapping it
/// resets rotation, exactly like Apple Maps' compass affordance.
class RotationCompassButton extends StatelessWidget {
  final double rotationDegrees;
  final VoidCallback onTap;

  const RotationCompassButton({super.key, required this.rotationDegrees, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final visible = rotationDegrees.abs() > 1;
    return AnimatedScale(
      scale: visible ? 1 : 0,
      duration: AppMotion.fast,
      curve: AppMotion.curve,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.fast,
        child: MapControlButton(
          icon: Icons.explore_rounded,
          onTap: onTap,
          iconColor: AppColors.dangerStrong,
          size: 42,
        ),
      ),
    );
  }
}
