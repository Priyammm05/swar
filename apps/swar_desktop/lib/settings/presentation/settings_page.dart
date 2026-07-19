import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_colors.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/diagnostics/presentation/core_diagnostics_card.dart';
import 'package:swar_desktop/dictation/domain/dictation_engine_gateway.dart';
import 'package:swar_desktop/dictation/presentation/dictation_session_view_model.dart';
import 'package:swar_desktop/settings/domain/swar_settings.dart';
import 'package:swar_desktop/settings/presentation/settings_view_model.dart';
import 'package:swar_desktop/settings/presentation/personalization_view_model.dart';

enum SettingsSection { general, system }

/// Settings stay close to the current task instead of becoming a destination.
final class SwarSettingsDialog extends StatefulWidget {
  const SwarSettingsDialog({
    required this.viewModel,
    required this.diagnosticsGateway,
    required this.dictationSessionViewModel,
    required this.personalizationViewModel,
    super.key,
  });

  final SettingsViewModel viewModel;
  final CoreDiagnosticsGateway diagnosticsGateway;
  final DictationSessionViewModel dictationSessionViewModel;
  final PersonalizationViewModel personalizationViewModel;

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
              personalizationViewModel: widget.personalizationViewModel,
            ),
            SettingsSection.system => _SystemSettings(
              viewModel: widget.viewModel,
              diagnosticsGateway: widget.diagnosticsGateway,
              personalizationViewModel: widget.personalizationViewModel,
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
    required this.personalizationViewModel,
  });

  final SettingsViewModel viewModel;
  final DictationSessionViewModel sessionViewModel;
  final PersonalizationViewModel personalizationViewModel;

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
              subtitle:
                  'Hold and release to finish. Double-tap to lock recording.',
              trailing: SizedBox(
                width: 180,
                child: DropdownButtonFormField<SwarShortcutKey>(
                  key: const Key('shortcut-setting'),
                  isExpanded: true,
                  initialValue: settings.shortcutKey,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: SwarShortcutKey.option,
                      child: Text('Option ⌥'),
                    ),
                    DropdownMenuItem(
                      value: SwarShortcutKey.control,
                      child: Text('Control ⌃'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) viewModel.setShortcutKey(value);
                  },
                ),
              ),
            ),
            _SettingRow(
              title: 'Microphone',
              subtitle:
                  'Swar uses the built-in microphone unless you choose another.',
              trailing: _MicrophoneSelector(
                viewModel: viewModel,
                sessionViewModel: sessionViewModel,
              ),
            ),
            _SettingRow(
              title: 'Dictation language',
              subtitle:
                  'Auto detect handles English, Hindi, and Hinglish locally.',
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
                      child: Text('Auto detect (recommended)'),
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
            _SettingRow(
              title: 'Personal vocabulary',
              subtitle:
                  '${personalizationViewModel.entries.length} local pronunciation and spelling preferences.',
              trailing: _VocabularyButton(viewModel: personalizationViewModel),
            ),
            _SettingRow(
              title: 'Optional cleanup provider',
              subtitle:
                  settings.enhancementProvider == SwarEnhancementProvider.local
                  ? 'Local processing only. No text leaves this device.'
                  : 'Opt-in OpenAI-compatible provider. The key is never saved.',
              trailing: _ProviderSettingsButton(viewModel: viewModel),
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
                  onPressed: sessionViewModel.isProcessing
                      ? null
                      : sessionViewModel.isRecording
                      ? sessionViewModel.finish
                      : () => sessionViewModel.start(
                          DictationEngineConfig(
                            modelPath: settings.modelPath,
                            microphoneId: settings.microphoneId,
                            language: settings.language.name,
                            writingMode: settings.writingMode.name,
                            pasteAutomatically: settings.pasteAutomatically,
                            restoreClipboard: settings.restoreClipboard,
                            keepModelsWarm: settings.keepModelsWarm,
                            enhancementProvider:
                                settings.enhancementProvider.name,
                            providerEndpoint: settings.providerEndpoint,
                            providerModel: settings.providerModel,
                            providerApiKey: viewModel.providerApiKey,
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
    required this.personalizationViewModel,
  });

  final SettingsViewModel viewModel;
  final CoreDiagnosticsGateway diagnosticsGateway;
  final PersonalizationViewModel personalizationViewModel;

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
            _SettingRow(
              title: 'Export learning examples',
              subtitle:
                  personalizationViewModel.message ??
                  'Create a local JSONL file only when you choose to export.',
              trailing: OutlinedButton(
                key: const Key('export-learning-examples'),
                onPressed: personalizationViewModel.isLoading
                    ? null
                    : personalizationViewModel.export,
                child: const Text('Export'),
              ),
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
            _ToggleSettingRow(
              key: const Key('learn-from-edits-setting'),
              title: 'Learn from my edits',
              subtitle:
                  'Learn vocabulary and writing preferences locally on this device.',
              value: settings.learnFromEdits,
              onChanged: (value) {
                viewModel.setLearnFromEdits(enabled: value);
              },
            ),
            _SettingRow(
              title: 'Keep history for',
              subtitle:
                  'Your dictation history stays on this machine. Older entries are removed automatically.',
              trailing: SizedBox(
                width: 180,
                child: DropdownButtonFormField<int>(
                  key: const Key('history-retention-setting'),
                  isExpanded: true,
                  initialValue: settings.historyRetentionDays,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('30 days')),
                    DropdownMenuItem(value: 90, child: Text('90 days')),
                    DropdownMenuItem(value: 180, child: Text('180 days')),
                    DropdownMenuItem(value: 365, child: Text('1 year')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      viewModel.setHistoryRetentionDays(value);
                    }
                  },
                ),
              ),
            ),
            _SettingRow(
              title: 'Private applications',
              subtitle: settings.excludedApplications.isEmpty
                  ? 'No foreground application names are excluded.'
                  : '${settings.excludedApplications.length} applications excluded from context.',
              trailing: _ExcludedApplicationsButton(viewModel: viewModel),
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

final class _ExcludedApplicationsButton extends StatelessWidget {
  const _ExcludedApplicationsButton({required this.viewModel});

  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: const Key('excluded-applications-button'),
      onPressed: () async {
        final controller = TextEditingController(
          text: viewModel.settings.excludedApplications.join(', '),
        );
        final result = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Private applications'),
            content: SizedBox(
              width: 440,
              child: TextField(
                key: const Key('excluded-applications-field'),
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Application names, separated by commas',
                  hintText: '1Password, Banking, Password Manager',
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('save-excluded-applications'),
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        controller.dispose();
        if (result != null) {
          viewModel.setExcludedApplications(result.split(','));
        }
      },
      child: const Text('Edit'),
    );
  }
}

final class _VocabularyButton extends StatelessWidget {
  const _VocabularyButton({required this.viewModel});

  final PersonalizationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: const Key('personal-vocabulary-button'),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => _VocabularyDialog(viewModel: viewModel),
      ),
      child: const Text('Manage'),
    );
  }
}

final class _VocabularyDialog extends StatefulWidget {
  const _VocabularyDialog({required this.viewModel});

  final PersonalizationViewModel viewModel;

  @override
  State<_VocabularyDialog> createState() => _VocabularyDialogState();
}

final class _VocabularyDialogState extends State<_VocabularyDialog> {
  final _spoken = TextEditingController();
  final _written = TextEditingController();

  @override
  void dispose() {
    _spoken.dispose();
    _written.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('personal-vocabulary-dialog'),
      title: const Text('Personal vocabulary'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: ListenableBuilder(
          listenable: widget.viewModel,
          builder: (context, _) => Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('vocabulary-spoken-field'),
                      controller: _spoken,
                      decoration: const InputDecoration(
                        labelText: 'Swar hears',
                        hintText: 'sewer',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('vocabulary-written-field'),
                      controller: _written,
                      decoration: const InputDecoration(
                        labelText: 'Swar writes',
                        hintText: 'Swar',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    key: const Key('add-vocabulary-entry'),
                    onPressed: () async {
                      if (_spoken.text.trim().isEmpty ||
                          _written.text.trim().isEmpty) {
                        return;
                      }
                      await widget.viewModel.add(_spoken.text, _written.text);
                      _spoken.clear();
                      _written.clear();
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: widget.viewModel.entries.isEmpty
                    ? const Center(
                        child: Text('No personal vocabulary added yet.'),
                      )
                    : ListView.builder(
                        itemCount: widget.viewModel.entries.length,
                        itemBuilder: (context, index) {
                          final entry = widget.viewModel.entries[index];
                          return ListTile(
                            key: Key('vocabulary-entry-$index'),
                            title: Text('${entry.spoken} → ${entry.written}'),
                            subtitle: Text('Used ${entry.useCount} times'),
                            trailing: IconButton(
                              tooltip: 'Delete',
                              onPressed: () =>
                                  widget.viewModel.delete(entry.spoken),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
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

final class _ProviderSettingsButton extends StatelessWidget {
  const _ProviderSettingsButton({required this.viewModel});

  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: const Key('provider-settings-button'),
      onPressed: () => _show(context),
      child: const Text('Configure'),
    );
  }

  Future<void> _show(BuildContext context) async {
    final endpoint = TextEditingController(
      text: viewModel.settings.providerEndpoint,
    );
    final model = TextEditingController(text: viewModel.settings.providerModel);
    final apiKey = TextEditingController(text: viewModel.providerApiKey);
    var provider = viewModel.settings.enhancementProvider;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Cleanup provider'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<SwarEnhancementProvider>(
                  key: const Key('enhancement-provider-setting'),
                  initialValue: provider,
                  decoration: const InputDecoration(labelText: 'Provider'),
                  items: const [
                    DropdownMenuItem(
                      value: SwarEnhancementProvider.local,
                      child: Text('Local only'),
                    ),
                    DropdownMenuItem(
                      value: SwarEnhancementProvider.byok,
                      child: Text('OpenAI-compatible, bring your own key'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => provider = value);
                  },
                ),
                if (provider == SwarEnhancementProvider.byok) ...[
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('provider-endpoint-setting'),
                    controller: endpoint,
                    decoration: const InputDecoration(
                      labelText: 'HTTPS endpoint',
                      hintText: 'https://api.example.com/v1',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('provider-model-setting'),
                    controller: model,
                    decoration: const InputDecoration(labelText: 'Model'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('provider-key-setting'),
                    controller: apiKey,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'API key, kept only until Swar closes',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('save-provider-settings'),
              onPressed: () {
                viewModel
                  ..setEnhancementProvider(provider)
                  ..setProviderEndpoint(endpoint.text)
                  ..setProviderModel(model.text)
                  ..setProviderApiKey(apiKey.text);
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    endpoint.dispose();
    model.dispose();
    apiKey.dispose();
  }
}

final class _MicrophoneSelector extends StatefulWidget {
  const _MicrophoneSelector({
    required this.viewModel,
    required this.sessionViewModel,
  });

  final SettingsViewModel viewModel;
  final DictationSessionViewModel sessionViewModel;

  @override
  State<_MicrophoneSelector> createState() => _MicrophoneSelectorState();
}

final class _MicrophoneSelectorState extends State<_MicrophoneSelector> {
  late Future<List<SwarMicrophone>> _microphones;

  @override
  void initState() {
    super.initState();
    _microphones = widget.sessionViewModel.listMicrophones();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: FutureBuilder<List<SwarMicrophone>>(
        future: _microphones,
        builder: (context, snapshot) {
          final microphones = snapshot.data ?? const <SwarMicrophone>[];
          if (snapshot.connectionState != ConnectionState.done) {
            return const Align(
              alignment: Alignment.center,
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (microphones.isEmpty) {
            return OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Check microphones'),
            );
          }

          final savedId = widget.viewModel.settings.microphoneId;
          final selected = microphones.where((item) => item.id == savedId);
          final selectedId = selected.isNotEmpty
              ? selected.first.id
              : microphones
                    .firstWhere(
                      (item) => item.isBuiltIn,
                      orElse: () => microphones.first,
                    )
                    .id;
          return DropdownButtonFormField<String>(
            key: ValueKey('microphone-$selectedId'),
            initialValue: selectedId,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            items: microphones
                .map(
                  (microphone) => DropdownMenuItem(
                    value: microphone.id,
                    child: Text(
                      microphone.isBuiltIn
                          ? '${microphone.name} · Built-in'
                          : microphone.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) widget.viewModel.setMicrophoneId(value);
            },
          );
        },
      ),
    );
  }

  void _reload() {
    setState(() {
      _microphones = widget.sessionViewModel.listMicrophones();
    });
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
