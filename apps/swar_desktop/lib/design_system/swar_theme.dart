// apps/swar_desktop/lib/design_system/swar_theme.dart

import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_tokens.dart';
import 'package:swar_desktop/design_system/swar_typography.dart';

/// App theme — wires the [SwarTokens] design system into Material.
///
/// Light is the primary theme (spec); dark applies the §12 neutral remap. Both
/// register the matching [SwarTokens] extension so `context.tokens` resolves,
/// and both default text to Manrope at weights 400/500 only.
abstract final class SwarTheme {
  static ThemeData light() => _build(SwarTokens.light);
  static ThemeData dark() => _build(SwarTokens.dark);

  static ThemeData _build(SwarTokens t) {
    final isDark = t.isDark;
    final colorScheme =
        (isDark ? const ColorScheme.dark() : const ColorScheme.light())
            .copyWith(
              primary: t.spruce,
              onPrimary: t.spruceInk,
              surface: t.surfaceCard,
              onSurface: t.ink,
              secondary: t.saffron,
              error: const Color(0xFFC24A4A),
            );

    final baseText = SwarType.body.copyWith(color: t.ink);

    return ThemeData(
      useMaterial3: true,
      brightness: t.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: t.bgPage,
      fontFamily: 'Manrope',
      fontFamilyFallback: const ['.AppleSystemUIFont', 'Segoe UI', 'Arial'],
      extensions: [t],
      textTheme: TextTheme(
        displaySmall: SwarType.serifTitle.copyWith(color: t.ink),
        headlineMedium: SwarType.greeting.copyWith(color: t.ink),
        titleLarge: SwarType.cardHeading.copyWith(color: t.ink),
        titleMedium: SwarType.rowTitle.copyWith(color: t.ink),
        bodyLarge: baseText,
        bodyMedium: baseText,
        bodySmall: SwarType.caption.copyWith(color: t.inkSecondary),
        labelLarge: SwarType.nav.copyWith(color: t.ink),
      ).apply(bodyColor: t.ink, displayColor: t.ink),
      dividerColor: t.border,
      splashFactory: NoSplash.splashFactory,
      dialogTheme: DialogThemeData(
        backgroundColor: t.surfaceCard,
        elevation: 18,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
    );
  }
}
