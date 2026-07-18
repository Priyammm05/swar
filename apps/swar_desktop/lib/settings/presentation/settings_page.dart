import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_colors.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/diagnostics/presentation/core_diagnostics_card.dart';
import 'package:swar_desktop/dictation/domain/dictation_engine_gateway.dart';
import 'package:swar_desktop/dictation/presentation/dictation_session_view_model.dart';
import 'package:swar_desktop/settings/domain/swar_settings.dart';
import 'package:swar_desktop/settings/presentation/settings_view_model.dart';

enum SettingsSection { general, system }

/// Settings stay close to the current task instead of becoming a destination.
final class SwarSettingsDialog extends StatefulWidget {
  const SwarSettingsDialog({
    required this.viewModel,
    required this.diagnosticsGateway,
    required this.dictationSessionViewModel,
    super.key,
  });

  final SettingsViewModel viewModel;
  final CoreDiagnosticsGateway diagnosticsGateway;
  final DictationSessionViewModel dictationSessionViewModel;

  @override
  State<SwarSettingsDialog> createState() => _SwarSettingsDialogState();
}

final class _SwarSettingsDialogState extends State<SwarSettingsDialog> {
  SettingsSection _section = SettingsSection.general;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width < 820;
    return Dialog(
      key: const Key('settings-dialog'),
      insetPadding: EdgeInsets.all(compact ? 12 : 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1240,
          maxHeight: screen.height * 0.9,
          minHeight: compact ? 520 : 650,
        ),
        child: compact ? _buildCompact(context) : _buildDesktop(context),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 248,
          child: _SettingsNavigation(section: _section, onSelected: _select),
        ),
        Expanded(
          child: _SettingsContent(section: _section, widget: widget),
        ),
      ],
    );
  }

  Widget _buildCompact(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: const BoxDecoration(
            color: SwarColors.chrome,
            border: Border(bottom: BorderSide(color: SwarColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<SettingsSection>(
                  key: const Key('settings-section-control'),
                  segments: const [
                    ButtonSegment(
                      value: SettingsSection.general,
                      icon: Icon(Icons.tune_rounded),
                      label: Text('General'),
                    ),
                    ButtonSegment(
                      value: SettingsSection.system,
                      icon: Icon(Icons.computer_rounded),
                      label: Text('System', key: Key('settings-system-nav')),
                    ),
                  ],
                  selected: {_section},
                  onSelectionChanged: (value) => _select(value.single),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('settings-close-button'),
                tooltip: 'Close settings',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: _SettingsContent(section: _section, widget: widget),
        ),
      ],
    );
  }

  void _select(SettingsSection section) {
    setState(() => _section = section);
  }
}

final class _SettingsNavigation extends StatelessWidget {
  const _SettingsNavigation({required this.section, required this.onSelected});

  final SettingsSection section;
  final ValueChanged<SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: SwarColors.chrome,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'SETTINGS',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: SwarColors.mutedInk,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 26),
            _SettingsNavButton(
              key: const Key('settings-general-nav'),
              icon: Icons.tune_rounded,
              label: 'General',
              selected: section == SettingsSection.general,
              onPressed: () => onSelected(SettingsSection.general),
            ),
            const SizedBox(height: 8),
            _SettingsNavButton(
              key: const Key('settings-system-nav'),
              icon: Icons.computer_rounded,
              label: 'System',
              selected: section == SettingsSection.system,
              onPressed: () => onSelected(SettingsSection.system),
            ),
            const Spacer(),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Swar preview',
                    style: TextStyle(color: SwarColors.mutedInk),
                  ),
                ),
                IconButton(
                  key: const Key('settings-close-button'),
                  tooltip: 'Close settings',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _SettingsNavButton extends StatelessWidget {
  const _SettingsNavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: SwarColors.ink,
        backgroundColor: selected ? SwarColors.canvas : Colors.transparent,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 23),
      label: Text(
        label,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    );
  }
}

final class _SettingsContent extends StatelessWidget {
  const _SettingsContent({required this.section, required this.widget});

  final SettingsSection section;
  final SwarSettingsDialog widget;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: SwarColors.surface,
      child: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) {
          return switch (section) {
            SettingsSection.general => _GeneralSettings(
              viewModel: widget.viewModel,
              sessionViewModel: widget.dictationSessionViewModel,
            ),
            SettingsSection.system => _SystemSettings(
              viewModel: widget.viewModel,
              diagnosticsGateway: widget.diagnosticsGateway,
            ),
          };
        },
      ),
    );
  }
}

final class _GeneralSettings extends StatelessWidget {
  const _GeneralSettings({
    required this.viewModel,
    required this.sessionViewModel,
  });

  final SettingsViewModel viewModel;
  final DictationSessionViewModel sessionViewModel;

  @override
  Widget build(BuildContext context) {
    final settings = viewModel.settings;
    return _SettingsScrollView(
      key: const Key('general-settings-page'),
      title: 'General',
      children: [
        _SettingsGroup(
          children: [
            _SettingRow(
              title: 'Shortcut',
              subtitle: 'Hold Control + Space and speak.',
              trailing: OutlinedButton(
                onPressed: null,
                child: const Text('Change'),
              ),
            ),
            _SettingRow(
              title: 'Microphone',
              subtitle: 'System default microphone (recommended)',
              trailing: OutlinedButton(
                key: const Key('refresh-microphones-button'),
                onPressed: sessionViewModel.listMicrophones,
                child: const Text('Check'),
              ),
            ),
            _SettingRow(
              title: 'Dictation language',
              subtitle: 'Preserve English, Hindi, or Hinglish as you speak.',
              trailing: SizedBox(
                width: 190,
                child: DropdownButtonFormField<SwarLanguagePreference>(
                  key: const Key('language-setting'),
                  isExpanded: true,
                  initialValue: settings.language,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: SwarLanguagePreference.automatic,
                      child: Text('Auto detect'),
                    ),
                    DropdownMenuItem(
                      value: SwarLanguagePreference.english,
                      child: Text('English'),
                    ),
                    DropdownMenuItem(
                      value: SwarLanguagePreference.hindi,
                      child: Text('Hindi'),
                    ),
                    DropdownMenuItem(
                      value: SwarLanguagePreference.hinglish,
                      child: Text('Hinglish'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) viewModel.setLanguage(value);
                  },
                ),
              ),
            ),
            _SettingRow(
              title: 'Writing mode',
              subtitle: 'Choose how closely Swar shapes the words you speak.',
              trailing: SegmentedButton<SwarWritingMode>(
                key: const Key('writing-mode-setting'),
                segments: const [
                  ButtonSegment(value: SwarWritingMode.raw, label: Text('Raw')),
                  ButtonSegment(
                    value: SwarWritingMode.clean,
                    label: Text('Clean'),
                  ),
                  ButtonSegment(
                    value: SwarWritingMode.intent,
                    label: Text('Intent'),
                  ),
                ],
                selected: {settings.writingMode},
                onSelectionChanged: (value) {
                  viewModel.setWritingMode(value.single);
                },
              ),
            ),
            _SettingRow(
              title: 'Offline model',
              subtitle: settings.modelPath.isEmpty
                  ? 'Install the private multilingual voice model once.'
                  : settings.modelPath,
              trailing: FilledButton.icon(
                key: const Key('install-offline-model-button'),
                onPressed: sessionViewModel.isInstallingModel
                    ? null
                    : () async {
                        final path = await sessionViewModel
                            .installRecommendedModel();
                        if (path != null) viewModel.setModelPath(path);
                      },
                icon: sessionViewModel.isInstallingModel
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        sessionViewModel.recommendedModelStatus.installed
                            ? Icons.check_circle_outline_rounded
                            : Icons.download_rounded,
                      ),
                label: Text(
                  sessionViewModel.recommendedModelStatus.installed
                      ? 'Use installed model'
                      : 'Install model',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ListenableBuilder(
          listenable: sessionViewModel,
          builder: (context, _) => _SettingsGroup(
            children: [
              _SettingRow(
                title: 'Test dictation',
                subtitle:
                    sessionViewModel.message ?? 'Audio stays on this device.',
                trailing: FilledButton.icon(
                  key: const Key('test-dictation-button'),
                  onPressed:
                      sessionViewModel.state == DictationSessionState.finalising
                      ? null
                      : sessionViewModel.isRecording
                      ? sessionViewModel.finish
                      : () => sessionViewModel.start(
                          DictationEngineConfig(
                            modelPath: settings.modelPath,
                            language: settings.language.name,
                            writingMode: settings.writingMode.name,
                            pasteAutomatically: settings.pasteAutomatically,
                            restoreClipboard: settings.restoreClipboard,
                          ),
                        ),
                  icon: Icon(
                    sessionViewModel.isRecording
                        ? Icons.stop_rounded
                        : Icons.mic_none_rounded,
                  ),
                  label: Text(
                    sessionViewModel.isRecording
                        ? 'Stop and transcribe'
                        : 'Start test',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final class _SystemSettings extends StatelessWidget {
  const _SystemSettings({
    required this.viewModel,
    required this.diagnosticsGateway,
  });

  final SettingsViewModel viewModel;
  final CoreDiagnosticsGateway diagnosticsGateway;

  @override
  Widget build(BuildContext context) {
    final settings = viewModel.settings;
    return _SettingsScrollView(
      key: const Key('system-settings-page'),
      title: 'System',
      children: [
        Text('App settings', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        _SettingsGroup(
          children: [
            _ToggleSettingRow(
              key: const Key('launch-at-login-setting'),
              title: 'Launch app at login',
              value: settings.launchAtLogin,
              onChanged: (value) {
                viewModel.setLaunchAtLogin(enabled: value);
              },
            ),
            _ToggleSettingRow(
              key: const Key('show-swar-bar-setting'),
              title: 'Show Swar Bar at all times',
              value: settings.showSwarBar,
              onChanged: (value) {
                viewModel.setShowSwarBar(enabled: value);
              },
            ),
            _ToggleSettingRow(
              key: const Key('show-in-dock-setting'),
              title: 'Show app in Dock or taskbar',
              value: settings.showInDock,
              onChanged: (value) {
                viewModel.setShowInDock(enabled: value);
              },
            ),
            _ToggleSettingRow(
              key: const Key('keep-models-warm-setting'),
              title: 'Keep voice model ready',
              subtitle: 'Uses more memory, but starts dictation faster.',
              value: settings.keepModelsWarm,
              onChanged: (value) {
                viewModel.setKeepModelsWarm(enabled: value);
              },
            ),
          ],
        ),
        const SizedBox(height: 30),
        Text('Sound', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        _SettingsGroup(
          children: [
            _ToggleSettingRow(
              key: const Key('dictation-sounds-setting'),
              title: 'Dictation and notification sounds',
              value: settings.dictationSounds,
              onChanged: (value) {
                viewModel.setDictationSounds(enabled: value);
              },
            ),
            _ToggleSettingRow(
              key: const Key('mute-music-setting'),
              title: 'Mute music while dictating',
              value: settings.muteMusic,
              onChanged: (value) {
                viewModel.setMuteMusic(enabled: value);
              },
            ),
          ],
        ),
        const SizedBox(height: 30),
        Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        _SettingsGroup(
          children: [
            _ToggleSettingRow(
              title: 'Suggestions',
              subtitle: 'Tips for improving how you use Swar.',
              value: settings.suggestions,
              onChanged: (value) {
                viewModel.setSuggestions(enabled: value);
              },
            ),
            _ToggleSettingRow(
              title: 'Announcements',
              subtitle: 'New features or capabilities.',
              value: settings.announcements,
              onChanged: (value) {
                viewModel.setAnnouncements(enabled: value);
              },
            ),
            _ToggleSettingRow(
              title: 'Milestones',
              subtitle: 'Word-count milestones and streaks.',
              value: settings.milestones,
              onChanged: (value) {
                viewModel.setMilestones(enabled: value);
              },
            ),
          ],
        ),
        const SizedBox(height: 30),
        Text('Offline engine', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        _SettingsGroup(
          children: [
            Padding(
              padding: const EdgeInsets.all(22),
              child: CoreDiagnosticsCard(gateway: diagnosticsGateway),
            ),
          ],
        ),
      ],
    );
  }
}

final class _SettingsScrollView extends StatelessWidget {
  const _SettingsScrollView({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 620 ? 22.0 : 58.0;
        return ListView(
          key: Key('${title.toLowerCase()}-settings-scroll'),
          padding: EdgeInsets.fromLTRB(horizontal, 34, horizontal, 46),
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 34),
            ...children,
          ],
        );
      },
    );
  }
}

final class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SwarColors.panel,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const Divider(height: 1, indent: 22, endIndent: 22),
          ],
        ],
      ),
    );
  }
}

final class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          ],
        );
        return Padding(
          padding: const EdgeInsets.all(22),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [text, const SizedBox(height: 16), trailing],
                )
              : Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 24),
                    trailing,
                  ],
                ),
        );
      },
    );
  }
}

final class _ToggleSettingRow extends StatelessWidget {
  const _ToggleSettingRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged: onChanged,
    );
  }
}
