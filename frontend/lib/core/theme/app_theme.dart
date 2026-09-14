import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_radius.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final textTheme = GoogleFonts.interTextTheme(ThemeData(brightness: Brightness.dark).textTheme);

    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.bg,
        primary: AppColors.accent,
        secondary: AppColors.accent,
        error: AppColors.dangerStrong,

        onPrimary: Colors.black,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: textTheme,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      textTheme: textTheme.copyWith(
        headlineLarge: const TextStyle(
          fontFamily: 'Inter',
          color: AppColors.textPrimary,
          fontSize: 30,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
        ),
        headlineMedium: const TextStyle(
          fontFamily: 'Inter',
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        titleLarge: const TextStyle(
          fontFamily: 'Inter',
          color: AppColors.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: const TextStyle(
          fontFamily: 'Inter',
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: const TextStyle(fontFamily: 'Inter', color: AppColors.textPrimary, fontSize: 15, height: 1.4),
        bodyMedium: const TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary, fontSize: 14, height: 1.4),
        bodySmall: const TextStyle(fontFamily: 'Inter', color: AppColors.textTertiary, fontSize: 12),
        labelLarge: const TextStyle(
          fontFamily: 'Inter',
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardR),
      ),
      // No elevatedButtonTheme/outlinedButtonTheme/bottomNavigationBarTheme/
      // navigationBarTheme here on purpose: this app has exactly one button
      // system (AppButton) and one bottom nav implementation
      // (GlassBottomNav), both built directly on Material/InkWell rather
      // than themed Material widgets — see lib/widgets/.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smallR),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: AppRadius.buttonR,
          borderSide: const BorderSide(color: AppColors.cardBorderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.buttonR,
          borderSide: const BorderSide(color: AppColors.cardBorderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.buttonR,
          borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.buttonR,
          borderSide: const BorderSide(color: AppColors.danger, width: 1.2),
        ),
        labelStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary),
        hintStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.textTertiary),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceRaised,
        labelStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.textPrimary, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: const BorderSide(color: AppColors.cardBorderSubtle)),
        side: const BorderSide(color: AppColors.cardBorderSubtle),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smallR),
      ),
    );
  }
}
