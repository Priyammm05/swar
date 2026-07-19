// apps/swar_desktop/lib/design_system/swar_tokens.dart

import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_colors.dart';

/// Semantic design tokens — Theme Layer.
///
/// Resolves the raw [SwarColors] palette into the named, theme-aware roles the
/// UI actually consumes (spec §2 for light, §12 for the dark remap). Widgets
/// read these through `SwarTokens.of(context)` so a single light/dark switch
/// re-themes the whole app — including the brand logo, which is [spruce] on
/// light and [spruceSoft] on dark.
@immutable
final class SwarTokens extends ThemeExtension<SwarTokens> {
  const SwarTokens({
    required this.brightness,
    required this.bgPage,
    required this.surfaceCard,
    required this.surfaceSunken,
    required this.surfaceSunken2,
    required this.ink,
    required this.inkSecondary,
    required this.inkMuted,
    required this.border,
    required this.borderStrong,
    required this.spruce,
    required this.spruceMid,
    required this.spruceSoft,
    required this.spruceInk,
    required this.spruceBorder,
    required this.spruceTint,
    required this.spruceTint2,
    required this.saffron,
    required this.saffronInk,
    required this.saffronTint,
    required this.mixInk,
    required this.mixTint,
    required this.streakEmpty,
    required this.toggleOff,
    required this.streakRamp,
    required this.logo,
  });

  final Brightness brightness;

  // Neutrals.
  final Color bgPage;
  final Color surfaceCard;
  final Color surfaceSunken;
  final Color surfaceSunken2;
  final Color ink;
  final Color inkSecondary;
  final Color inkMuted;
  final Color border;
  final Color borderStrong;

  // Brand green.
  final Color spruce;
  final Color spruceMid;
  final Color spruceSoft;
  final Color spruceInk;
  final Color spruceBorder;
  final Color spruceTint;
  final Color spruceTint2;

  // Accent saffron.
  final Color saffron;
  final Color saffronInk;
  final Color saffronTint;

  // Mixed-language badge.
  final Color mixInk;
  final Color mixTint;

  // Misc surfaces.
  final Color streakEmpty;
  final Color toggleOff;

  /// Heatmap ramp least -> most (§2). Length 4.
  final List<Color> streakRamp;

  /// Brand logo stroke color for the current theme.
  final Color logo;

  bool get isDark => brightness == Brightness.dark;

  static const light = SwarTokens(
    brightness: Brightness.light,
    bgPage: SwarColors.lightBgPage,
    surfaceCard: SwarColors.lightSurfaceCard,
    surfaceSunken: SwarColors.lightSurfaceSunken,
    surfaceSunken2: SwarColors.lightSurfaceSunken2,
    ink: SwarColors.lightInk,
    inkSecondary: SwarColors.lightInkSecondary,
    inkMuted: SwarColors.lightInkMuted,
    border: SwarColors.lightBorder,
    borderStrong: SwarColors.lightBorderStrong,
    spruce: SwarColors.spruce,
    spruceMid: SwarColors.spruceMid,
    spruceSoft: SwarColors.spruceSoft,
    spruceInk: SwarColors.spruceInk,
    spruceBorder: SwarColors.spruceBorder,
    spruceTint: SwarColors.lightSpruceTint,
    spruceTint2: SwarColors.lightSpruceTint2,
    saffron: SwarColors.saffron,
    saffronInk: SwarColors.saffronInk,
    saffronTint: SwarColors.lightSaffronTint,
    mixInk: SwarColors.mixInk,
    mixTint: SwarColors.lightMixTint,
    streakEmpty: SwarColors.lightStreakEmpty,
    toggleOff: SwarColors.lightToggleOff,
    streakRamp: [
      SwarColors.streakL1,
      SwarColors.streakL2,
      SwarColors.streakL3,
      SwarColors.streakL4,
    ],
    logo: SwarColors.spruce,
  );

  static const dark = SwarTokens(
    brightness: Brightness.dark,
    bgPage: SwarColors.darkBgPage,
    surfaceCard: SwarColors.darkSurfaceCard,
    surfaceSunken: SwarColors.darkSurfaceSunken,
    surfaceSunken2: SwarColors.darkSurfaceSunken2,
    ink: SwarColors.darkInk,
    inkSecondary: SwarColors.darkInkSecondary,
    inkMuted: SwarColors.darkInkMuted,
    border: SwarColors.darkBorder,
    borderStrong: SwarColors.darkBorderStrong,
    spruce: SwarColors.spruce,
    spruceMid: SwarColors.spruceMid,
    spruceSoft: SwarColors.spruceSoft,
    spruceInk: SwarColors.spruceInk,
    spruceBorder: SwarColors.spruceBorder,
    spruceTint: SwarColors.darkSpruceTint,
    spruceTint2: SwarColors.darkSpruceTint2,
    saffron: SwarColors.saffron,
    saffronInk:
        SwarColors.saffron, // on dark tints, saffron text lightens to saffron
    saffronTint: SwarColors.darkSaffronTint,
    mixInk: Color(0xFFE7B8E7), // light magenta on dark (§12)
    mixTint: SwarColors.darkMixTint,
    streakEmpty: SwarColors.darkStreakEmpty,
    toggleOff: SwarColors.darkToggleOff,
    streakRamp: [
      SwarColors.darkStreakEmpty,
      SwarColors.streakL2,
      SwarColors.streakL3,
      SwarColors.streakL4,
    ],
    logo: SwarColors.spruceSoft,
  );

  /// The active token set for [context]. Falls back to [light] if the extension
  /// is somehow absent so widgets never crash on a bare theme.
  static SwarTokens of(BuildContext context) {
    return Theme.of(context).extension<SwarTokens>() ?? light;
  }

  @override
  SwarTokens copyWith({Brightness? brightness}) => this;

  @override
  SwarTokens lerp(ThemeExtension<SwarTokens>? other, double t) {
    // Discrete light/dark swap; no interpolation needed between the two sets.
    if (other is! SwarTokens) return this;
    return t < 0.5 ? this : other;
  }
}

/// Ergonomic accessor: `context.tokens.spruce`.
extension SwarTokensContext on BuildContext {
  SwarTokens get tokens => SwarTokens.of(this);
}
