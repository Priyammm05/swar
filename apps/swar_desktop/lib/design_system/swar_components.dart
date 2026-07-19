// apps/swar_desktop/lib/design_system/swar_components.dart

import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_tokens.dart';
import 'package:swar_desktop/design_system/swar_typography.dart';

/// Shared control primitives — Presentation Layer (spec §8.6).
///
/// Every reusable box (buttons, dropdown trigger, segmented control, toggle,
/// icon button, cards, pills, badges) lives here so all three screens compose
/// the exact same primitives rather than re-styling Material defaults. Each reads
/// its colors from [SwarTokens] so light/dark comes for free.

/// Radii from the spec (§4).
abstract final class SwarRadii {
  static const card = 14.0; // Insights cards
  static const cardLarge = 16.0; // Activity day cards, Settings group cards
  static const control = 12.0; // buttons, dropdowns
  static const pill = 999.0; // pills, nav, badges, toggles
  static const segmentOuter = 10.0;
  static const segmentItem = 8.0; // segment items, icon buttons
}

/// Primary filled button — bg spruce, text spruce-ink (§8.6).
final class SwarPrimaryButton extends StatelessWidget {
  const SwarPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _PressableBox(
      onPressed: busy ? null : onPressed,
      background: t.spruce,
      border: t.spruce,
      radius: SwarRadii.control,
      child: _buttonRow(
        label: label,
        icon: icon,
        busy: busy,
        color: t.spruceInk,
      ),
    );
  }
}

/// Ghost-green button — white bg, spruce text, spruce-border (§8.6).
final class SwarGhostButton extends StatelessWidget {
  const SwarGhostButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _PressableBox(
      onPressed: onPressed,
      background: t.surfaceCard,
      border: t.spruceBorder,
      radius: SwarRadii.control,
      child: _buttonRow(label: label, icon: icon, busy: false, color: t.spruce),
    );
  }
}

/// Dropdown trigger button — space-between label + trailing chevron (§8.6).
/// This is display-only; [onPressed] opens whatever picker the caller wants.
final class SwarDropdownButton extends StatelessWidget {
  const SwarDropdownButton({
    required this.label,
    required this.onPressed,
    this.minWidth,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // The trailing slot in a settings row is horizontally unbounded, so a
    // MainAxisSize.max Row would fail to lay out. IntrinsicWidth gives the Row a
    // tight width (clamped up to minWidth by the ConstrainedBox), letting the
    // label sit left and the chevron pin right.
    final row = Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: SwarType.rowTitle.copyWith(color: t.ink, height: 1.1),
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: t.inkMuted),
      ],
    );
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth ?? 0),
      child: IntrinsicWidth(
        child: _HoverBox(
          onPressed: onPressed,
          idle: t.surfaceCard,
          hover: t.surfaceSunken,
          border: t.borderStrong,
          radius: SwarRadii.control,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: row,
        ),
      ),
    );
  }
}

/// A single choice in a [SwarSegmented].
@immutable
final class SwarSegment<T> {
  const SwarSegment({required this.value, required this.label});
  final T value;
  final String label;
}

/// Segmented control — sunken track, spruce-tint-2 selected segment (§8.6).
final class SwarSegmented<T> extends StatelessWidget {
  const SwarSegmented({
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.showCheckOnSelected = false,
    super.key,
  });

  final List<SwarSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool showCheckOnSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surfaceSunken2,
        borderRadius: BorderRadius.circular(SwarRadii.segmentOuter),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final segment in segments)
            _Segment(
              label: segment.label,
              isSelected: segment.value == selected,
              showCheck: showCheckOnSelected,
              onTap: () => onChanged(segment.value),
            ),
        ],
      ),
    );
  }
}

final class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.isSelected,
    required this.showCheck,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool showCheck;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? t.spruceTint2 : Colors.transparent,
          borderRadius: BorderRadius.circular(SwarRadii.segmentItem),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showCheck && isSelected) ...[
              Icon(Icons.check_rounded, size: 14, color: t.spruce),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: SwarType.nav.copyWith(
                color: isSelected ? t.spruce : t.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Toggle — 44x26 track, animated knob, spruce when on (§8.6).
final class SwarToggle extends StatelessWidget {
  const SwarToggle({required this.value, required this.onChanged, super.key});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      toggled: value,
      container: true,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: 44,
          height: 26,
          decoration: BoxDecoration(
            color: value ? t.spruce : t.toggleOff,
            borderRadius: BorderRadius.circular(SwarRadii.pill),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Square/round icon button — transparent, hover sunken (§8.6).
final class SwarIconButton extends StatelessWidget {
  const SwarIconButton({
    required this.icon,
    required this.onPressed,
    this.semanticLabel,
    this.size = 30,
    this.iconSize = 16,
    this.round = false,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final double size;
  final double iconSize;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _HoverIcon(
      icon: icon,
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      size: size,
      iconSize: iconSize,
      radius: round ? SwarRadii.pill : SwarRadii.segmentItem,
      idleColor: t.inkSecondary,
      hoverColor: t.ink,
      hoverBg: t.surfaceSunken,
    );
  }
}

/// A raised white card (Activity rows / Insights cards). Radius defaults to the
/// standard card radius; pass [sunken] for the Settings group surface.
final class SwarCard extends StatelessWidget {
  const SwarCard({
    required this.child,
    this.radius = SwarRadii.card,
    this.padding,
    this.sunken = false,
    this.filled,
    this.clip = false,
    super.key,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool sunken;

  /// Overrides the background entirely (e.g. the spruce hero card).
  final Color? filled;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bg = filled ?? (sunken ? t.surfaceSunken : t.surfaceCard);
    return Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: filled == null ? Border.all(color: t.border, width: 0.5) : null,
      ),
      child: child,
    );
  }
}

/// Small count pill — e.g. "91 entries" (§6.2). Spruce text on spruce-tint.
final class SwarCountPill extends StatelessWidget {
  const SwarCountPill({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: t.spruceTint,
        borderRadius: BorderRadius.circular(SwarRadii.pill),
      ),
      child: Text(
        label,
        style: SwarType.captionMedium.copyWith(color: t.spruce),
      ),
    );
  }
}

/// A hairline divider inset from a card's horizontal padding (§6.5, §8.2).
final class SwarInsetDivider extends StatelessWidget {
  const SwarInsetDivider({this.inset = 18, super.key});

  final double inset;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: Container(height: 0.5, color: t.border),
    );
  }
}

// --- internal building blocks ---

Widget _buttonRow({
  required String label,
  required IconData? icon,
  required bool busy,
  required Color color,
}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (busy)
        SizedBox.square(
          dimension: 15,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        )
      else if (icon != null)
        Icon(icon, size: 16, color: color),
      if (busy || icon != null) const SizedBox(width: 8),
      Text(label, style: SwarType.rowTitle.copyWith(color: color, height: 1.1)),
    ],
  );
}

/// A tappable box with fixed background used by primary/ghost buttons.
final class _PressableBox extends StatelessWidget {
  const _PressableBox({
    required this.child,
    required this.background,
    required this.border,
    required this.radius,
    required this.onPressed,
  });

  final Widget child;
  final Color background;
  final Color border;
  final double radius;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.6 : 1,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border, width: 0.5),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A tappable box that lightens its background on hover (dropdown).
final class _HoverBox extends StatefulWidget {
  const _HoverBox({
    required this.child,
    required this.idle,
    required this.hover,
    required this.border,
    required this.radius,
    required this.padding,
    required this.onPressed,
  });

  final Widget child;
  final Color idle;
  final Color hover;
  final Color border;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onPressed;

  @override
  State<_HoverBox> createState() => _HoverBoxState();
}

final class _HoverBoxState extends State<_HoverBox> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _hovering ? widget.hover : widget.idle,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: widget.border, width: 0.5),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

final class _HoverIcon extends StatefulWidget {
  const _HoverIcon({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    required this.size,
    required this.iconSize,
    required this.radius,
    required this.idleColor,
    required this.hoverColor,
    required this.hoverBg,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final double size;
  final double iconSize;
  final double radius;
  final Color idleColor;
  final Color hoverColor;
  final Color hoverBg;

  @override
  State<_HoverIcon> createState() => _HoverIconState();
}

final class _HoverIconState extends State<_HoverIcon> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: Semantics(
          button: true,
          label: widget.semanticLabel,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: _hovering ? widget.hoverBg : Colors.transparent,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _hovering ? widget.hoverColor : widget.idleColor,
            ),
          ),
        ),
      ),
    );
  }
}
