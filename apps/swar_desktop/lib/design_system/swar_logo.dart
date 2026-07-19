// apps/swar_desktop/lib/design_system/swar_logo.dart

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:swar_desktop/design_system/swar_tokens.dart';
import 'package:swar_desktop/design_system/swar_typography.dart';

/// Brand lockup — the Swar menu-bar mark plus the "Swar" wordmark (spec §5).
///
/// The mark is the app's real `menu_bar_logo.svg`, recolored to the theme's
/// brand color (spruce on light, spruce-soft on dark) so the same asset serves
/// light and dark. Used in the top nav and reusable anywhere the lockup appears.
final class SwarLogo extends StatelessWidget {
  const SwarLogo({super.key, this.showWordmark = true, this.markSize = 26});

  /// When false, only the mark renders (e.g. compact surfaces).
  final bool showWordmark;
  final double markSize;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final mark = SwarLogoMark(size: markSize, color: tokens.logo);
    if (!showWordmark) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 9),
        Text('Swar', style: SwarType.wordmark.copyWith(color: tokens.ink)),
      ],
    );
  }
}

/// The circular waveform mark on its own, tinted to [color].
final class SwarLogoMark extends StatelessWidget {
  const SwarLogoMark({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/logo/menu_bar_logo.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      // The mark is decorative; the wordmark carries the label.
      semanticsLabel: 'Swar',
    );
  }
}
