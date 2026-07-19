// apps/swar_desktop/lib/app/swar_shell.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:swar_desktop/design_system/swar_components.dart';
import 'package:swar_desktop/design_system/swar_logo.dart';
import 'package:swar_desktop/design_system/swar_tokens.dart';
import 'package:swar_desktop/design_system/swar_typography.dart';

const _desktopNavigationBreakpoint = 760.0;

/// Branch indices in [createSwarRouter]. The nav pill renders them in the spec
/// order (Activity, Insights, Settings) regardless of branch declaration order.
const _insightsBranch = 0;
const _activityBranch = 1;
const _settingsBranch = 2;

/// Shared application shell (spec §5) — the logo on the left and a centered
/// navigation pill, identical on every screen. Presentation Layer.
final class SwarShell extends StatelessWidget {
  const SwarShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      key: const Key('swar-shell'),
      backgroundColor: t.bgPage,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= _desktopNavigationBreakpoint;
          return Column(
            children: [
              if (desktop)
                _TopNav(
                  selectedIndex: navigationShell.currentIndex,
                  onSelected: navigationShell.goBranch,
                ),
              Expanded(
                child: KeyedSubtree(
                  key: const Key('shell-content'),
                  child: navigationShell,
                ),
              ),
              if (!desktop)
                _CompactNavigation(
                  selectedIndex: navigationShell.currentIndex,
                  onSelected: navigationShell.goBranch,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The desktop top bar: `grid-template-columns: 1fr auto 1fr` — logo left, pill
/// centered, right column empty so the pill stays centered (§5).
final class _TopNav extends StatelessWidget {
  const _TopNav({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('top-navigation'),
      padding: const EdgeInsets.fromLTRB(32, 26, 32, 4),
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Row(
          children: [
            const Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SwarLogo(showWordmark: false, markSize: 52),
              ),
            ),
            _NavPill(selectedIndex: selectedIndex, onSelected: onSelected),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    );
  }
}

final class _NavPill extends StatelessWidget {
  const _NavPill({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: t.surfaceCard,
        borderRadius: BorderRadius.circular(SwarRadii.pill),
        border: Border.all(color: t.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF14201B).withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NavItem(
            key: const Key('top-dictation-nav'),
            label: 'Activity',
            icon: Icons.grid_view_rounded,
            selected: selectedIndex == _activityBranch,
            onPressed: () => onSelected(_activityBranch),
          ),
          const SizedBox(width: 4),
          _NavItem(
            key: const Key('top-insights-nav'),
            label: 'Insights',
            icon: Icons.bar_chart_rounded,
            selected: selectedIndex == _insightsBranch,
            onPressed: () => onSelected(_insightsBranch),
          ),
          const SizedBox(width: 4),
          _NavItem(
            key: const Key('top-settings-nav'),
            label: 'Settings',
            icon: Icons.settings_outlined,
            selected: selectedIndex == _settingsBranch,
            onPressed: () => onSelected(_settingsBranch),
          ),
        ],
      ),
    );
  }
}

final class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = selected ? t.spruceInk : t.inkSecondary;
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? t.spruce : Colors.transparent,
            borderRadius: BorderRadius.circular(SwarRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 7),
              Text(label, style: SwarType.nav.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact bottom navigation for narrow windows.
final class _CompactNavigation extends StatelessWidget {
  const _CompactNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('compact-navigation'),
        height: 68,
        decoration: BoxDecoration(
          color: t.surfaceSunken,
          border: Border(top: BorderSide(color: t.border, width: 0.5)),
        ),
        child: Row(
          children: [
            _CompactDestination(
              key: const Key('compact-dictation-nav'),
              label: 'Activity',
              icon: Icons.grid_view_rounded,
              selected: selectedIndex == _activityBranch,
              onPressed: () => onSelected(_activityBranch),
            ),
            _CompactDestination(
              key: const Key('compact-insights-nav'),
              label: 'Insights',
              icon: Icons.bar_chart_rounded,
              selected: selectedIndex == _insightsBranch,
              onPressed: () => onSelected(_insightsBranch),
            ),
            _CompactDestination(
              key: const Key('compact-settings-nav'),
              label: 'Settings',
              icon: Icons.settings_outlined,
              selected: selectedIndex == _settingsBranch,
              onPressed: () => onSelected(_settingsBranch),
            ),
          ],
        ),
      ),
    );
  }
}

final class _CompactDestination extends StatelessWidget {
  const _CompactDestination({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = selected ? t.spruce : t.inkMuted;
    return Expanded(
      child: InkWell(
        onTap: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(label, style: SwarType.badge.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
