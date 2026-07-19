// apps/swar_desktop/lib/design_system/swar_colors.dart

import 'package:flutter/painting.dart';

/// Design Token Source — raw palette values from the Swar UI design spec (§2, §12).
///
/// These are the single source of truth for every hex value in the app. Brand
/// tokens (`spruce`, `saffron`, badge tints) are shared across light and dark;
/// neutrals are remapped per §12. Semantic, theme-resolved tokens live in
/// [SwarTokens] — widgets should read those via `SwarTokens.of(context)` rather
/// than reaching for a raw value here.
abstract final class SwarColors {
  // Brand / green ramp (shared light + dark).
  static const spruce = Color(0xFF2F5547); // primary brand
  static const spruceMid = Color(0xFF5E8474); // secondary bars (Hindi)
  static const spruceSoft = Color(0xFFA9C7BB); // tertiary bars, muted-on-dark
  static const spruceInk = Color(0xFFEAF3EE); // text/icons on spruce fills
  static const spruceBorder = Color(0xFFB9CFC6); // ghost-green button border

  // Accent / saffron ramp (shared).
  static const saffron = Color(0xFFF4B24A); // hero number, Hinglish bar
  static const saffronInk = Color(0xFF8A5A12); // text on saffron-tint

  // Mixed-language badge (shared).
  static const mixInk = Color(0xFF6A2B6A); // HI+EN badge text

  // Streak heatmap ramp (least -> most), shared brand steps.
  static const streakL1 = Color(0xFFEDEAE2); // = light streak-empty
  static const streakL2 = Color(0xFFC8D9D1);
  static const streakL3 = Color(0xFF5E8474);
  static const streakL4 = Color(0xFF2F5547);

  // --- Light neutrals (§2) ---
  static const lightSpruceTint = Color(0xFFE4EEE9); // pill / chip bg
  static const lightSpruceTint2 = Color(0xFFDCEAE3); // selected segment bg
  static const lightSaffronTint = Color(
    0xFFFBEFD9,
  ); // EN warm / copied badge bg
  static const lightMixTint = Color(0xFFF3E4F3); // HI+EN badge bg

  static const lightBgPage = Color(0xFFFFFFFF);
  static const lightSurfaceCard = Color(0xFFFFFFFF);
  static const lightSurfaceSunken = Color(0xFFF6F4EF);
  static const lightSurfaceSunken2 = Color(0xFFEFEDE6);
  static const lightInk = Color(0xFF14201B);
  static const lightInkSecondary = Color(0xFF5F6B65);
  static const lightInkMuted = Color(0xFF8C9691);
  static const lightBorder = Color(0x1A14201B); // rgba(20,32,27,0.10)
  static const lightBorderStrong = Color(0x2914201B); // rgba(20,32,27,0.16)
  static const lightStreakEmpty = Color(0xFFEDEAE2);
  static const lightToggleOff = Color(0xFFC7C5BC);

  // --- Dark neutrals (§12) ---
  static const darkSpruceTint = Color(0xFF213A30);
  static const darkSpruceTint2 = Color(0xFF22261F);
  static const darkSaffronTint = Color(0xFF3A2E12);
  static const darkMixTint = Color(0xFF38223A);

  static const darkBgPage = Color(0xFF141715);
  static const darkSurfaceCard = Color(0xFF1E221F);
  static const darkSurfaceSunken = Color(0xFF191C1A);
  static const darkSurfaceSunken2 = Color(0xFF22261F);
  static const darkInk = Color(0xFFF2F4F1);
  static const darkInkSecondary = Color(0xFFAEB8B2);
  static const darkInkMuted = Color(0xFF7E8983);
  static const darkBorder = Color(0x1AFFFFFF); // rgba(255,255,255,0.10)
  static const darkBorderStrong = Color(0x29FFFFFF); // rgba(255,255,255,0.16)
  static const darkStreakEmpty = Color(0xFF26302B);
  static const darkToggleOff = Color(0xFF3A3F3B);

  // Shared status.
  static const danger = Color(0xFFC24A4A);
}
