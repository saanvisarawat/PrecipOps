import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
class AppTypography {
  AppTypography._();

  static TextStyle _base({
    required double size,
    required FontWeight weight,
    Color color = AppColors.textPrimary,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// Hero numbers — 40-52px, dominant.
  static TextStyle hero({Color color = AppColors.textPrimary}) =>
      _base(size: 46, weight: FontWeight.w600, color: color, letterSpacing: -1.2, height: 1.05);

  /// Main screen heading — 28-34px.
  static TextStyle screenTitle({Color color = AppColors.textPrimary}) =>
      _base(size: 30, weight: FontWeight.w600, color: color, letterSpacing: -0.6, height: 1.1);

  /// Section heading — 18-22px.
  static TextStyle sectionTitle({Color color = AppColors.textPrimary}) =>
      _base(size: 19, weight: FontWeight.w600, color: color, letterSpacing: -0.2);

  /// Card title — 15-17px.
  static TextStyle cardTitle({Color color = AppColors.textPrimary}) =>
      _base(size: 16, weight: FontWeight.w600, color: color, letterSpacing: -0.1);

  /// Body — 14-16px regular.
  static TextStyle body({Color color = AppColors.textPrimary}) =>
      _base(size: 15, weight: FontWeight.w400, color: color, height: 1.4);

  /// Secondary label — 12-14px medium, muted.
  static TextStyle label({Color color = AppColors.textSecondary}) =>
      _base(size: 13, weight: FontWeight.w500, color: color);

  /// Tiny caption — for timestamps, fine print.
  static TextStyle caption({Color color = AppColors.textTertiary}) =>
      _base(size: 11.5, weight: FontWeight.w500, color: color);

  /// Small green indicator text (e.g. "+12.4%").
  static TextStyle accentValue({Color color = AppColors.accent}) =>
      _base(size: 13, weight: FontWeight.w600, color: color);

  /// Button label.
  static TextStyle button({Color color = AppColors.textPrimary}) =>
      _base(size: 16, weight: FontWeight.w600, color: color, letterSpacing: -0.1);
}
