import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:swar_desktop/design_system/swar_colors.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/dictation/domain/dictation_engine_gateway.dart';
import 'package:swar_desktop/dictation/presentation/dictation_session_view_model.dart';
import 'package:swar_desktop/settings/presentation/settings_page.dart';
import 'package:swar_desktop/settings/presentation/settings_view_model.dart';

const _desktopNavigationBreakpoint = 760.0;

/// Shared top application shell from the approved HTML. Presentation Layer.
final class SwarShell extends StatelessWidget {
  const SwarShell({
    required this.navigationShell,
    required this.settingsViewModel,
    required this.diagnosticsGateway,
    required this.dictationSessionViewModel,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final SettingsViewModel settingsViewModel;
  final CoreDiagnosticsGateway diagnosticsGateway;
  final DictationSessionViewModel dictationSessionViewModel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('swar-shell'),
      backgroundColor: SwarColors.canvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= _desktopNavigationBreakpoint;
          return Column(
            children: [
              _TopAppBar(
                showNavigation: desktop,
                selectedIndex: navigationShell.currentIndex,
                onSelected: navigationShell.goBranch,
                onSettings: () => _openSettings(context),
                settingsViewModel: settingsViewModel,
                sessionViewModel: dictationSessionViewModel,
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
                  onSettings: () => _openSettings(context),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openSettings(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (context) => SwarSettingsDialog(
        viewModel: settingsViewModel,
        diagnosticsGateway: diagnosticsGateway,
        dictationSessionViewModel: dictationSessionViewModel,
      ),
    );
  }
}

final class _TopAppBar extends StatelessWidget {
  const _TopAppBar({
    required this.showNavigation,
    required this.selectedIndex,
    required this.onSelected,
    required this.onSettings,
    required this.settingsViewModel,
    required this.sessionViewModel,
  });

  final bool showNavigation;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onSettings;
  final SettingsViewModel settingsViewModel;
  final DictationSessionViewModel sessionViewModel;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('top-navigation'),
      height: 64,
      decoration: const BoxDecoration(
        color: SwarColors.chrome,
        border: Border(bottom: BorderSide(color: SwarColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Row(
            children: [
              const _SwarWordmark(),
              if (showNavigation) ...[
                const SizedBox(width: 32),
                _TopDestination(
                  key: const Key('top-dictation-nav'),
                  label: 'Dictation',
                  icon: Icons.mic_none_rounded,
                  selected: selectedIndex == 1,
                  onPressed: () => onSelected(1),
                ),
                const SizedBox(width: 8),
                _TopDestination(
                  key: const Key('top-insights-nav'),
                  label: 'Insights',
                  icon: Icons.bar_chart_rounded,
                  selected: selectedIndex == 0,
                  onPressed: () => onSelected(0),
                ),
                const SizedBox(width: 8),
                _TopDestination(
                  key: const Key('top-settings-nav'),
                  label: 'Settings',
                  icon: Icons.settings_outlined,
                  selected: false,
                  onPressed: onSettings,
                ),
              ],
              const Spacer(),
              ListenableBuilder(
                listenable: sessionViewModel,
                builder: (context, _) => _DictationControl(
                  sessionViewModel: sessionViewModel,
                  settingsViewModel: settingsViewModel,
                ),
              ),
              const SizedBox(width: 16),
              const _NotificationButton(),
              const SizedBox(width: 24),
              const _ProfileButton(),
            ],
          ),
        ),
      ),
    );
  }
}

final class _DictationControl extends StatelessWidget {
  const _DictationControl({
    required this.sessionViewModel,
    required this.settingsViewModel,
  });

  final DictationSessionViewModel sessionViewModel;
  final SettingsViewModel settingsViewModel;

  @override
  Widget build(BuildContext context) {
    final recording = sessionViewModel.isRecording;
    final busy =
        sessionViewModel.state == DictationSessionState.preparing ||
        sessionViewModel.state == DictationSessionState.finalising;
    return Tooltip(
      message: recording
          ? 'Stop and transcribe (Control + Space)'
          : 'Start dictation (Control + Space)',
      child: FilledButton.icon(
        key: const Key('global-dictation-control'),
        onPressed: busy
            ? null
            : recording
            ? sessionViewModel.finish
            : _start,
        style: FilledButton.styleFrom(
          backgroundColor: recording ? SwarColors.danger : SwarColors.leaf,
          foregroundColor: Colors.white,
          minimumSize: const Size(118, 40),
        ),
        icon: busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                recording ? Icons.stop_rounded : Icons.mic_rounded,
                size: 19,
              ),
        label: Text(
          recording
              ? 'Stop'
              : busy
              ? 'Working'
              : 'Dictate',
        ),
      ),
    );
  }

  Future<void> _start() {
    final settings = settingsViewModel.settings;
    return sessionViewModel.start(
      DictationEngineConfig(
        modelPath: settings.modelPath,
        language: settings.language.name,
        writingMode: settings.writingMode.name,
        pasteAutomatically: settings.pasteAutomatically,
        restoreClipboard: settings.restoreClipboard,
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
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SwarMark(size: 28),
          SizedBox(width: 8),
          Text(
            'Swar',
            style: TextStyle(
              color: SwarColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
}

final class _SwarMark extends StatelessWidget {
  const _SwarMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _SwarMarkPainter());
  }
}

final class _SwarMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SwarColors.ink
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.1;
    const heights = <double>[0.44, 0.78, 0.52, 0.9, 0.6, 0.38];
    for (var index = 0; index < heights.length; index++) {
      final x = size.width * (0.09 + index * 0.16);
      final halfHeight = size.height * heights[index] / 2;
      canvas.drawLine(
        Offset(x, size.height / 2 - halfHeight),
        Offset(x, size.height / 2 + halfHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

final class _TopDestination extends StatelessWidget {
  const _TopDestination({
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
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: selected ? SwarColors.ink : SwarColors.mutedInk,
        backgroundColor: selected
            ? SwarColors.surfaceVariant
            : Colors.transparent,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

final class _NotificationButton extends StatelessWidget {
  const _NotificationButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Center(
            child: Icon(
              Icons.notifications_none_rounded,
              color: SwarColors.mutedInk,
              size: 24,
            ),
          ),
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: SwarColors.danger,
                shape: BoxShape.circle,
              ),
              child: const Text(
                '4',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ProfileButton extends StatelessWidget {
  const _ProfileButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: SwarColors.surfaceVariant,
        border: Border.all(color: SwarColors.border),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.person_outline_rounded,
        size: 20,
        color: SwarColors.mutedInk,
      ),
    );
  }
}

final class _CompactNavigation extends StatelessWidget {
  const _CompactNavigation({
    required this.selectedIndex,
    required this.onSelected,
    required this.onSettings,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('compact-navigation'),
        height: 68,
        decoration: const BoxDecoration(
          color: SwarColors.chrome,
          border: Border(top: BorderSide(color: SwarColors.border)),
        ),
        child: Row(
          children: [
            _CompactDestination(
              key: const Key('compact-dictation-nav'),
              label: 'Dictation',
              icon: Icons.mic_none_rounded,
              selected: selectedIndex == 1,
              onPressed: () => onSelected(1),
            ),
            _CompactDestination(
              key: const Key('compact-insights-nav'),
              label: 'Insights',
              icon: Icons.bar_chart_rounded,
              selected: selectedIndex == 0,
              onPressed: () => onSelected(0),
            ),
            _CompactDestination(
              key: const Key('compact-settings-nav'),
              label: 'Settings',
              icon: Icons.settings_outlined,
              selected: false,
              onPressed: onSettings,
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
    return Expanded(
      child: InkWell(
        onTap: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? SwarColors.ink : SwarColors.mutedInk,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? SwarColors.ink : SwarColors.mutedInk,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
