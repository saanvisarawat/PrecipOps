import 'package:flutter/animation.dart';

/// Centralized motion language — soft, quick, physically believable.
/// Never slow 1-2s animations for normal interaction.
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 260);
  static const Duration modal = Duration(milliseconds: 380);

  static const Curve curve = Curves.easeOutCubic;
  static const Curve curveInOut = Curves.easeInOutCubic;

  /// Press-down scale for tappable surfaces (buttons, cards).
  static const double pressScale = 0.97;
}
