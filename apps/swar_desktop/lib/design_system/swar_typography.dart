// apps/swar_desktop/lib/design_system/swar_typography.dart

import 'package:flutter/widgets.dart';

/// Type scale — Design Token Layer (spec §3).
///
/// Two families only: **Manrope** for UI/body (weights 400 and 500 — never
/// 600/700) and **Newsreader** as the display serif for the three screen titles
/// and the large stat numbers. Styles carry geometry only; callers apply color
/// from [SwarTokens] via `.copyWith(color: ...)`. Numeric styles request
/// tabular figures so timestamps and stats stay column-aligned.
abstract final class SwarType {
  static const _manrope = 'Manrope';
  static const _serif = 'Newsreader';
  static const _tabular = [FontFeature.tabularFigures()];

  // letter-spacing is expressed in logical px (em * fontSize).

  /// Serif screen title — "Insights" / "General" / "System". 30/500, -0.01em.
  static const serifTitle = TextStyle(
    fontFamily: _serif,
    fontSize: 30,
    fontWeight: FontWeight.w500,
    height: 1.1,
    letterSpacing: -0.30,
  );

  /// Activity greeting h1 — "Welcome back, Priyam". 24/500, -0.01em.
  static const greeting = TextStyle(
    fontFamily: _manrope,
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.15,
    letterSpacing: -0.24,
  );

  /// Logo wordmark — "Swar". 19/500, -0.01em.
  static const wordmark = TextStyle(
    fontFamily: _manrope,
    fontSize: 19,
    fontWeight: FontWeight.w500,
    height: 1,
    letterSpacing: -0.19,
  );

  /// Card heading (h2) — "Language split". 17/500.
  static const cardHeading = TextStyle(
    fontFamily: _manrope,
    fontSize: 17,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  /// Stat hero number — 44/500 serif, -0.02em, tabular.
  static const statHero = TextStyle(
    fontFamily: _serif,
    fontSize: 44,
    fontWeight: FontWeight.w500,
    height: 1,
    letterSpacing: -0.88,
    fontFeatures: _tabular,
  );

  /// WPM big number — 52/500 serif, -0.02em, tabular.
  static const wpmHero = TextStyle(
    fontFamily: _serif,
    fontSize: 52,
    fontWeight: FontWeight.w500,
    height: 1,
    letterSpacing: -1.04,
    fontFeatures: _tabular,
  );

  /// Setting row title — 15/500.
  static const rowTitle = TextStyle(
    fontFamily: _manrope,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  /// Body / row transcript text — 14/400, 1.55.
  static const body = TextStyle(
    fontFamily: _manrope,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );

  /// Nav item — 13/500.
  static const nav = TextStyle(
    fontFamily: _manrope,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  /// Setting description — 13/400, 1.4.
  static const description = TextStyle(
    fontFamily: _manrope,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// Search input — 13/400.
  static const searchInput = TextStyle(
    fontFamily: _manrope,
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  /// Caption / label — 12/400, 1.4. Timestamps add [tabular].
  static const caption = TextStyle(
    fontFamily: _manrope,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// Caption medium — 12/500 (count pills, source captions).
  static const captionMedium = TextStyle(
    fontFamily: _manrope,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  /// Timestamp — 12/400, tabular.
  static const timestamp = TextStyle(
    fontFamily: _manrope,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    fontFeatures: _tabular,
  );

  /// Uppercase stat label — 12/400, 0.03em, uppercase (caller uppercases text).
  static const uppercaseLabel = TextStyle(
    fontFamily: _manrope,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.36,
  );

  /// Language / status badge — 11/400.
  static const badge = TextStyle(
    fontFamily: _manrope,
    fontSize: 11,
    fontWeight: FontWeight.w400,
  );

  /// A large serif number that also needs tabular figures at an arbitrary size.
  static TextStyle serifNumber(double size) => TextStyle(
    fontFamily: _serif,
    fontSize: size,
    fontWeight: FontWeight.w500,
    height: 1,
    letterSpacing: size * -0.02,
    fontFeatures: _tabular,
  );
}
