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
      fontFamily: 'Manrope',
      fontFamilyFallback: const ['Segoe UI', '.AppleSystemUIFont', 'Arial'],
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: SwarColors.ink,
          fontSize: 32,
          height: 1.25,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.64,
        ),
        headlineMedium: TextStyle(
          color: SwarColors.ink,
          fontSize: 24,
          height: 1.33,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.24,
        ),
        titleMedium: TextStyle(
          color: SwarColors.ink,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: SwarColors.ink, fontSize: 16, height: 1.5),
        bodyMedium: TextStyle(
          color: SwarColors.ink,
          fontSize: 14,
          height: 1.43,
        ),
        bodySmall: TextStyle(color: SwarColors.ink, fontSize: 12, height: 1.33),
        labelLarge: TextStyle(
          color: SwarColors.ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: const CardThemeData(
        color: SwarColors.panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: SwarColors.border),
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      dividerColor: SwarColors.border,
      dialogTheme: const DialogThemeData(
        backgroundColor: SwarColors.surface,
        elevation: 18,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(26)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : SwarColors.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? SwarColors.leaf
              : const Color(0xFFC9C6BD),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
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
