// apps/swar_desktop/lib/design_system/swar_theme.dart

import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_colors.dart';

abstract final class SwarTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: SwarColors.leaf,
      brightness: Brightness.light,
      surface: SwarColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: SwarColors.canvas,
      fontFamily: 'Arial',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: SwarColors.ink,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.7,
        ),
        titleMedium: TextStyle(
          color: SwarColors.ink,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: SwarColors.ink, fontSize: 16, height: 1.5),
        bodyMedium: TextStyle(
          color: SwarColors.mutedInk,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      cardTheme: const CardThemeData(
        color: SwarColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: SwarColors.border),
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SwarColors.leaf,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
