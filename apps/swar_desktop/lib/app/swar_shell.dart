// apps/swar_desktop/lib/app/swar_shell.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:swar_desktop/app/swar_routes.dart';
import 'package:swar_desktop/design_system/swar_colors.dart';
import 'package:swar_desktop/design_system/swar_spacing.dart';

const _desktopSidebarBreakpoint = 760.0;

/// Persistent desktop navigation shell. Presentation Layer.
final class SwarShell extends StatelessWidget {
  const SwarShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('swar-shell'),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= _desktopSidebarBreakpoint) {
            return Row(
              children: [
                _DesktopSidebar(
                  selectedIndex: navigationShell.currentIndex,
                  onSelected: (index) => _goBranch(context, index),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: KeyedSubtree(
                    key: const Key('shell-content'),
                    child: navigationShell,
                  ),
                ),
              ],
            );
          }

          return KeyedSubtree(
            key: const Key('shell-content'),
            child: navigationShell,
          );
        },
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= _desktopSidebarBreakpoint) {
            return const SizedBox.shrink();
          }
          return NavigationBar(
            key: const Key('compact-navigation'),
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) => _goBranch(context, index),
            destinations: const [
              NavigationDestination(
                key: Key('compact-dictation-nav'),
                icon: Icon(Icons.mic_none_rounded),
                selectedIcon: Icon(Icons.mic_rounded),
                label: 'Dictation',
              ),
              NavigationDestination(
                key: Key('compact-insights-nav'),
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights_rounded),
                label: 'Insights',
              ),
              NavigationDestination(
                key: Key('compact-settings-nav'),
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          );
        },
      ),
    );
  }

  void _goBranch(BuildContext context, int index) {
    if (index == 2) {
      context.go(SwarRoutes.generalSettings);
      return;
    }
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

final class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: SwarColors.surface,
      child: SizedBox(
        width: 224,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(SwarSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SwarWordmark(),
                const SizedBox(height: SwarSpacing.xl),
                _SidebarDestination(
                  key: const Key('sidebar-dictation-nav'),
                  label: 'Dictation',
                  icon: Icons.mic_none_rounded,
                  selectedIcon: Icons.mic_rounded,
                  selected: selectedIndex == 0,
                  onPressed: () => onSelected(0),
                ),
                const SizedBox(height: SwarSpacing.xs),
                _SidebarDestination(
                  key: const Key('sidebar-insights-nav'),
                  label: 'Insights',
                  icon: Icons.insights_outlined,
                  selectedIcon: Icons.insights_rounded,
                  selected: selectedIndex == 1,
                  onPressed: () => onSelected(1),
                ),
                const Spacer(),
                _SidebarDestination(
                  key: const Key('sidebar-settings-nav'),
                  label: 'Settings',
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings_rounded,
                  selected: selectedIndex == 2,
                  onPressed: () => onSelected(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _SwarWordmark extends StatelessWidget {
  const _SwarWordmark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: 'Swar',
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: SwarColors.leaf,
              borderRadius: BorderRadius.all(Radius.circular(11)),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: SwarSpacing.sm),
          Text('swar', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

final class _SidebarDestination extends StatelessWidget {
  const _SidebarDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(selected ? selectedIcon : icon),
      label: Align(alignment: Alignment.centerLeft, child: Text(label)),
      style: TextButton.styleFrom(
        foregroundColor: selected ? SwarColors.leaf : SwarColors.mutedInk,
        backgroundColor: selected ? SwarColors.leafSoft : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: SwarSpacing.md,
          vertical: 14,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
    );
  }
}
