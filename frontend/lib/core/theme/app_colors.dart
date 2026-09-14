import 'package:flutter/material.dart';

/// Premium graphite/glass palette — modeled on iOS system surfaces (Apple
/// Maps/Weather/Health): true-black-adjacent neutrals, warm off-white
/// typography, and a calm desaturated green accent used sparingly for CTAs,
/// active states and key values — never a neon flood fill, never a glow
/// bloom. Structural spacing/typography/radius/motion tokens are unchanged;
/// only color values live here.
class AppColors {
  AppColors._();

  // ---------------------------------------------------------------------
  // Background — true black, tonal layers.
  // ---------------------------------------------------------------------
  static const Color bg = Color(0xFF000000);
  static const Color bgElevated = Color(0xFF0A0A0B);

  // ---------------------------------------------------------------------
  // Surface — near-black steps for stacked depth (iOS grouped-background
  // tiers: systemBackground -> secondarySystemBackground -> tertiary).
  // ---------------------------------------------------------------------
  static const Color surface = Color(0xFF111113);
  static const Color surfaceRaised = Color(0xFF1C1C1E);
  static const Color surfaceHigh = Color(0xFF2C2C2E);

  /// Hairline border for cards — white at very low opacity, never a
  /// visible outline.
  static const Color cardBorder = Color(0x14FFFFFF); // ~8% white
  static const Color cardBorderSubtle = Color(0x0DFFFFFF); // ~5% white
  static const Color divider = Color(0x14FFFFFF);

  /// Translucent floating-surface tokens for glass panels (bottom nav,
  /// search pills, map overlays, bottom sheets) — pair with a
  /// `BackdropFilter` blur. Formalizes what several screens previously
  /// spelled out as `surfaceRaised.withValues(alpha: 0.8)` inline.
  static const Color glassSurface = Color(0xC71C1C1E); // surfaceRaised ~78%
  static const Color glassBorder = Color(0x1FFFFFFF); // ~12% white

  // ---------------------------------------------------------------------
  // Accent — calm, desaturated system-green. Never neon.
  // ---------------------------------------------------------------------
  static const Color emeraldDeep = Color(0xFF1D6B3E);
  static const Color emerald = Color(0xFF27A159);
  static const Color emeraldBright = Color(0xFF30D158);
  static const Color emeraldHighlight = Color(0xFF30D158);
  static const Color emeraldMuted = Color(0xFF8FE3AC);

  /// The single accent color used for CTAs/active states/key values.
  static const Color accent = emeraldBright; // #30D158 — iOS systemGreen (dark)
  static const Color accentPressed = emerald;
  static const Color accentGlow = Color(0x1F30D158); // ~12% accent

  // ---------------------------------------------------------------------
  // Typography — warm off-white, never pure white; muted gray tiers.
  // ---------------------------------------------------------------------
  static const Color textPrimary = Color(0xFFF3F5F3);
  static const Color textSecondary = Color(0xFFA9B2AC);
  static const Color textTertiary = Color(0xFF6E766F);
  static const Color textDisabled = Color(0xFF4B514C);

  // ---------------------------------------------------------------------
  // Semantic — iOS system-color adjacent, never saturated Material
  // defaults. `info` (blue) marks GPS/live/location state.
  // ---------------------------------------------------------------------
  static const Color info = Color(0xFF409CFF); // iOS systemBlue (dark)
  static const Color infoStrong = Color(0xFF0A84FF);
  static const Color danger = Color(0xFFE0655A);
  static const Color dangerStrong = Color(0xFFFF453A); // iOS systemRed (dark)
  static const Color warning = Color(0xFFE5A73B); // amber, iOS systemOrange-adjacent
  static const Color success = accent;

  static List<BoxShadow> softShadow({double opacity = 0.22, double blur = 16, Offset offset = const Offset(0, 6)}) => [
        BoxShadow(color: Colors.black.withValues(alpha: opacity), blurRadius: blur, offset: offset),
      ];

  /// Very subtle elevation glow — deliberately restrained (small blur, low
  /// opacity) so it reads as a soft lift, never a neon bloom.
  static List<BoxShadow> glow({Color color = accentGlow, double blur = 18, double spread = 0}) => [
        BoxShadow(color: color, blurRadius: blur, spreadRadius: spread),
      ];

  /// PS 26071 inundation-polygon fill by water depth: 0.3-0.7m (traffic
  /// halt, minor waterlogging) reads [warning]; >=1.2m (submerged vehicles,
  /// evacuation required) reads [dangerStrong]. Mapped onto the existing
  /// accent/warning/danger palette rather than a new ad-hoc scale.
  static Color depthColor(double meters) {
    if (meters >= 1.2) return dangerStrong;
    if (meters >= 0.3) return warning;
    return accent;
  }

  /// IMD alert-level color (RED/ORANGE/YELLOW/GREEN) used across the
  /// Predictor/Responder advisory panels.
  static Color alertLevelColor(String level) => switch (level.toUpperCase()) {
        'RED' => dangerStrong,
        'ORANGE' => warning,
        'YELLOW' => warning,
        _ => accent,
      };
}
