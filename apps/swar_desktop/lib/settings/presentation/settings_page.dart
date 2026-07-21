// apps/swar_desktop/lib/settings/presentation/settings_page.dart

import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_components.dart';
import 'package:swar_desktop/design_system/swar_tokens.dart';
import 'package:swar_desktop/design_system/swar_typography.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/diagnostics/presentation/core_diagnostics_card.dart';
import 'package:swar_desktop/dictation/domain/dictation_engine_gateway.dart';
import 'package:swar_desktop/dictation/presentation/dictation_session_view_model.dart';
import 'package:swar_desktop/settings/domain/swar_settings.dart';
import 'package:swar_desktop/settings/presentation/settings_view_model.dart';
import 'package:swar_desktop/settings/presentation/personalization_view_model.dart';

enum SettingsSection { general, system }

/// Settings — a full screen (spec §8). The shared top nav sits above (from the
/// shell); this page renders the serif title, the General/System sub-toggle, and
/// the grouped setting cards. Presentation Layer.
final class SwarSettingsPage extends StatefulWidget {
  const SwarSettingsPage({
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
  State<SwarSettingsPage> createState() => _SwarSettingsPageState();
}

final class _SwarSettingsPageState extends State<SwarSettingsPage> {
  SettingsSection _section = SettingsSection.general;

  void _select(SettingsSection section) => setState(() => _section = section);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.viewModel,
        widget.dictationSessionViewModel,
        widget.personalizationViewModel,
      ]),
      builder: (context, _) {
        return switch (_section) {
          SettingsSection.general => _GeneralSettings(
            key: const Key('general-settings-page'),
            section: _section,
            onSection: _select,
            viewModel: widget.viewModel,
            sessionViewModel: widget.dictationSessionViewModel,
            personalizationViewModel: widget.personalizationViewModel,
          ),
          SettingsSection.system => _SystemSettings(
            key: const Key('system-settings-page'),
            section: _section,
            onSection: _select,
            viewModel: widget.viewModel,
            diagnosticsGateway: widget.diagnosticsGateway,
            personalizationViewModel: widget.personalizationViewModel,
          ),
        };
      },
    );
  }
}

/// Page scaffold: centered 960px column, serif title + sub-toggle, then content.
final class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold({
    required this.title,
    required this.section,
    required this.onSection,
    required this.children,
    required this.scrollKey,
  });

  final String title;
  final SettingsSection section;
  final ValueChanged<SettingsSection> onSection;
  final List<Widget> children;
  final Key scrollKey;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1008),
        child: ListView(
          key: scrollKey,
          padding: const EdgeInsets.fromLTRB(32, 8, 32, 48),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: SwarType.serifTitle.copyWith(color: t.ink),
                  ),
                ),
                _SubToggle(section: section, onSection: onSection),
              ],
            ),
            const SizedBox(height: 26),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// General/System sub-toggle — active segment white with a border (§8.1).
final class _SubToggle extends StatelessWidget {
  const _SubToggle({required this.section, required this.onSection});

  final SettingsSection section;
  final ValueChanged<SettingsSection> onSection;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(SwarRadii.pill),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SubSegment(
            key: const Key('settings-general-nav'),
            label: 'General',
            active: section == SettingsSection.general,
            onTap: () => onSection(SettingsSection.general),
          ),
          _SubSegment(
            key: const Key('settings-system-nav'),
            label: 'System',
            active: section == SettingsSection.system,
            onTap: () => onSection(SettingsSection.system),
          ),
        ],
      ),
    );
  }
}

final class _SubSegment extends StatelessWidget {
  const _SubSegment({
    required this.label,
    required this.active,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: active ? t.surfaceCard : Colors.transparent,
            borderRadius: BorderRadius.circular(SwarRadii.pill),
            border: active ? Border.all(color: t.border, width: 0.5) : null,
          ),
          child: Text(
            label,
            style: SwarType.nav.copyWith(
              color: active ? t.ink : t.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// --- General ---

final class _GeneralSettings extends StatelessWidget {
  const _GeneralSettings({
    required this.section,
    required this.onSection,
    required this.viewModel,
    required this.sessionViewModel,
    required this.personalizationViewModel,
    super.key,
  });

  final SettingsSection section;
  final ValueChanged<SettingsSection> onSection;
  final SettingsViewModel viewModel;
  final DictationSessionViewModel sessionViewModel;
  final PersonalizationViewModel personalizationViewModel;

  @override
  Widget build(BuildContext context) {
    final settings = viewModel.settings;
    final modelInstalled = sessionViewModel.recommendedModelStatus.installed;
    return _SettingsScaffold(
      title: 'General',
      section: section,
      onSection: onSection,
      scrollKey: const Key('general-settings-scroll'),
      children: [
        _GroupCard(
          children: [
            _SettingRow(
              title: 'Shortcut',
              description:
                  'Hold and release to finish. Double-tap to lock recording.',
              trailing: _MenuDropdown<SwarShortcutKey>(
                fieldKey: const Key('shortcut-setting'),
                value: settings.shortcutKey,
                minWidth: 150,
                labelFor: (value) => switch (value) {
                  SwarShortcutKey.option => 'Option ⌥',
                  SwarShortcutKey.control => 'Control ⌃',
                },
                items: SwarShortcutKey.values,
                onChanged: viewModel.setShortcutKey,
              ),
            ),
            _SettingRow(
              title: 'Microphone',
              description:
                  'Swar uses the built-in microphone unless you choose another.',
              trailing: _MicrophoneSelector(
                viewModel: viewModel,
                sessionViewModel: sessionViewModel,
              ),
            ),
            _SettingRow(
              title: 'Writing mode',
              description:
                  'Choose how closely Swar shapes the words you speak.',
              trailing: SwarSegmented<SwarWritingMode>(
                key: const Key('writing-mode-setting'),
                selected: settings.writingMode,
                onChanged: viewModel.setWritingMode,
                segments: const [
                  SwarSegment(value: SwarWritingMode.raw, label: 'Raw'),
                  SwarSegment(value: SwarWritingMode.clean, label: 'Clean'),
                  SwarSegment(value: SwarWritingMode.intent, label: 'Intent'),
                ],
              ),
            ),
            _SettingRow(
              title: 'Offline model',
              descriptionWidget: Text(
                settings.modelPath.isEmpty
                    ? 'Install the private multilingual voice model once.'
                    : _shortenPath(settings.modelPath),
                style: settings.modelPath.isEmpty
                    ? SwarType.description.copyWith(
                        color: context.tokens.inkSecondary,
                      )
                    : const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4,
                      ).copyWith(color: context.tokens.inkSecondary),
              ),
              trailing: SwarPrimaryButton(
                key: const Key('install-offline-model-button'),
                label: modelInstalled ? 'Use installed model' : 'Install model',
                icon: modelInstalled
                    ? Icons.check_circle_outline_rounded
                    : Icons.download_rounded,
                busy: sessionViewModel.isInstallingModel,
                onPressed: () async {
                  final path = await sessionViewModel.installRecommendedModel();
                  if (path != null) viewModel.setModelPath(path);
                },
              ),
            ),
            _SettingRow(
              title: 'Personal vocabulary',
              description:
                  '${personalizationViewModel.entries.length} local pronunciation and spelling preferences.',
              trailing: _VocabularyButton(viewModel: personalizationViewModel),
            ),
            _SettingRow(
              title: 'Optional cleanup provider',
              description:
                  settings.enhancementProvider == SwarEnhancementProvider.local
                  ? 'Local processing only. No text leaves this device.'
                  : 'Opt-in OpenAI-compatible provider. The key is never saved.',
              trailing: _ProviderSettingsButton(viewModel: viewModel),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _GroupCard(
          children: [
            _SettingRow(
              title: 'Test dictation',
              descriptionWidget: _TestStatus(message: sessionViewModel.message),
              trailing: SwarPrimaryButton(
                key: const Key('test-dictation-button'),
                label: sessionViewModel.isRecording
                    ? 'Stop and transcribe'
                    : 'Start test',
                icon: sessionViewModel.isRecording
                    ? Icons.stop_rounded
                    : Icons.mic_none_rounded,
                onPressed: sessionViewModel.isProcessing
                    ? null
                    : sessionViewModel.isRecording
                    ? sessionViewModel.finish
                    : () => sessionViewModel.start(
                        DictationEngineConfig(
                          modelPath: settings.modelPath,
                          microphoneId: settings.microphoneId,
                          language: 'english',
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
              ),
            ),
          ],
        ),
      ],
    );
  }
}

final class _TestStatus extends StatelessWidget {
  const _TestStatus({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pasted = message == null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          pasted ? Icons.check_circle_rounded : Icons.info_outline_rounded,
          size: 14,
          color: pasted ? t.spruce : t.inkSecondary,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            message ?? 'Dictation pasted.',
            style: SwarType.description.copyWith(color: t.inkSecondary),
          ),
        ),
      ],
    );
  }
}

// --- System ---

final class _SystemSettings extends StatelessWidget {
  const _SystemSettings({
    required this.section,
    required this.onSection,
    required this.viewModel,
    required this.diagnosticsGateway,
    required this.personalizationViewModel,
    super.key,
  });

  final SettingsSection section;
  final ValueChanged<SettingsSection> onSection;
  final SettingsViewModel viewModel;
  final CoreDiagnosticsGateway diagnosticsGateway;
  final PersonalizationViewModel personalizationViewModel;

  @override
  Widget build(BuildContext context) {
    final settings = viewModel.settings;
    return _SettingsScaffold(
      title: 'System',
      section: section,
      onSection: onSection,
      scrollKey: const Key('system-settings-scroll'),
      children: [
        // These four already changed how Swar behaves; they simply had no
        // control, so everyone was stuck on whichever default shipped. The
        // exclusion list matters most: without it there is no way to say
        // "never dictate into my password manager".
        const _GroupLabel('Dictating'),
        _GroupCard(
          children: [
            _ToggleRow(
              rowKey: const Key('show-swar-bar-setting'),
              title: 'Show the Swar bar',
              description:
                  'The bar appears above whatever you are working in while you dictate. It never takes focus.',
              value: settings.showSwarBar,
              onChanged: (value) => viewModel.setShowSwarBar(enabled: value),
            ),
            _ToggleRow(
              rowKey: const Key('paste-automatically-setting'),
              title: 'Paste automatically',
              description:
                  'Put the words at your cursor when dictation finishes. Turn this off to have them copied instead.',
              value: settings.pasteAutomatically,
              onChanged: (value) =>
                  viewModel.setPasteAutomatically(enabled: value),
            ),
            _ToggleRow(
              rowKey: const Key('restore-clipboard-setting'),
              title: 'Restore your clipboard',
              description:
                  'Pasting uses the clipboard, so Swar puts back whatever you had copied before.',
              value: settings.restoreClipboard,
              onChanged: (value) =>
                  viewModel.setRestoreClipboard(enabled: value),
            ),
            _SettingRow(
              title: 'Never dictate into',
              description:
                  'One application name per line. Swar will not insert text into these.',
              trailing: _ExcludedApplicationsField(
                values: settings.excludedApplications,
                onChanged: viewModel.setExcludedApplications,
              ),
            ),
          ],
        ),
        const _GroupLabel('App settings'),
        _GroupCard(
          children: [
            _ToggleRow(
              rowKey: const Key('learn-from-edits-setting'),
              title: 'Learn from your edits',
              description:
                  'Keeps a local record of corrections you make, so the export below has something in it. Off by default.',
              value: settings.learnFromEdits,
              onChanged: (value) => viewModel.setLearnFromEdits(enabled: value),
            ),
            _SettingRow(
              title: 'Export learning examples',
              description:
                  personalizationViewModel.message ??
                  'Create a local JSONL file only when you choose to export.',
              trailing: SwarGhostButton(
                key: const Key('export-learning-examples'),
                label: 'Export',
                onPressed: personalizationViewModel.isLoading
                    ? null
                    : personalizationViewModel.export,
              ),
            ),
            _ToggleRow(
              rowKey: const Key('keep-models-warm-setting'),
              title: 'Keep voice model ready',
              description: 'Uses more memory, but starts dictation faster.',
              value: settings.keepModelsWarm,
              onChanged: (value) => viewModel.setKeepModelsWarm(enabled: value),
            ),
            _SettingRow(
              title: 'Keep history for',
              description:
                  'Your dictation history stays on this machine. Older entries are removed automatically.',
              trailing: _MenuDropdown<int>(
                fieldKey: const Key('history-retention-setting'),
                value: settings.historyRetentionDays,
                minWidth: 150,
                labelFor: (value) => value == 365 ? '1 year' : '$value days',
                items: const [30, 90, 180, 365],
                onChanged: viewModel.setHistoryRetentionDays,
              ),
            ),
          ],
        ),
        const _GroupLabel('Offline engine'),
        _GroupCard(
          padding: const EdgeInsets.all(22),
          child: CoreDiagnosticsCard(gateway: diagnosticsGateway),
        ),
      ],
    );
  }
}

String _shortenPath(String path) {
  final parts = path.split('/');
  if (parts.length <= 4) return path;
  return '…/${parts.sublist(parts.length - 4).join('/')}';
}

// --- shared row / group primitives (§8.2) ---

final class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 0, 10),
      child: Text(
        label,
        style: SwarType.description.copyWith(
          color: t.inkSecondary,
          fontSize: 14,
        ),
      ),
    );
  }
}

final class _GroupCard extends StatelessWidget {
  const _GroupCard({this.children, this.child, this.padding});

  final List<Widget>? children;
  final Widget? child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final content =
        child ??
        Column(
          children: [
            for (var i = 0; i < children!.length; i++) ...[
              children![i],
              if (i != children!.length - 1) const SwarInsetDivider(inset: 0),
            ],
          ],
        );
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(SwarRadii.cardLarge),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: content,
    );
  }
}

/// Settings row (§8.2): info block left, control right, 16–18px vertical.
final class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.trailing,
    this.description,
    this.descriptionWidget,
    this.rowKey,
  });

  final String title;
  final String? description;
  final Widget? descriptionWidget;
  final Widget trailing;
  final Key? rowKey;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      key: rowKey,
      padding: const EdgeInsets.symmetric(vertical: 17),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SwarType.rowTitle.copyWith(color: t.ink)),
                if (descriptionWidget != null) ...[
                  const SizedBox(height: 4),
                  descriptionWidget!,
                ] else if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description!,
                    style: SwarType.description.copyWith(color: t.inkSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 24),
          trailing,
        ],
      ),
    );
  }
}

final class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.description,
    this.rowKey,
  });

  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Key? rowKey;

  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      rowKey: rowKey,
      title: title,
      description: description,
      trailing: SwarToggle(value: value, onChanged: onChanged),
    );
  }
}

/// A pill dropdown that opens a native menu anchored to the button (§8.6).
final class _MenuDropdown<T> extends StatelessWidget {
  const _MenuDropdown({
    required this.value,
    required this.items,
    required this.labelFor,
    required this.onChanged,
    required this.minWidth,
    this.fieldKey,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;
  final double minWidth;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: fieldKey,
      child: SwarDropdownButton(
        label: labelFor(value),
        minWidth: minWidth,
        onPressed: () async {
          final box = context.findRenderObject() as RenderBox?;
          final overlay =
              Overlay.of(context).context.findRenderObject() as RenderBox?;
          if (box == null || overlay == null) return;
          final position = RelativeRect.fromRect(
            Rect.fromPoints(
              box.localToGlobal(
                box.size.bottomLeft(Offset.zero),
                ancestor: overlay,
              ),
              box.localToGlobal(
                box.size.bottomRight(Offset.zero),
                ancestor: overlay,
              ),
            ),
            Offset.zero & overlay.size,
          );
          final selected = await showMenu<T>(
            context: context,
            position: position,
            items: [
              for (final item in items)
                PopupMenuItem<T>(value: item, child: Text(labelFor(item))),
            ],
          );
          if (selected != null) onChanged(selected);
        },
      ),
    );
  }
}

// --- secondary surfaces (dialogs) — functional, restyled triggers ---

final class _VocabularyButton extends StatelessWidget {
  const _VocabularyButton({required this.viewModel});

  final PersonalizationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return SwarGhostButton(
      key: const Key('personal-vocabulary-button'),
      label: 'Manage',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => _VocabularyDialog(viewModel: viewModel),
      ),
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

/// Editor for the applications Swar refuses to insert into.
///
/// A dialog rather than an inline field: the list is usually empty, and a
/// multi-line box sitting open in a settings row is a lot of furniture for
/// something most people set once. The button reports the count so the state
/// is legible without opening it.
final class _ExcludedApplicationsField extends StatelessWidget {
  const _ExcludedApplicationsField({
    required this.values,
    required this.onChanged,
  });

  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwarGhostButton(
      key: const Key('excluded-applications-setting'),
      label: values.isEmpty ? 'Add' : '${values.length} excluded',
      onPressed: () => _show(context),
    );
  }

  Future<void> _show(BuildContext context) async {
    final field = TextEditingController(text: values.join('\n'));
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Never dictate into'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'One application name per line, as it appears in the menu bar. '
                'Swar will not insert text into these.',
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('excluded-applications-field'),
                controller: field,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: '1Password\nKeychain Access',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('save-excluded-applications'),
            onPressed: () {
              // Trimming and de-duplication happen in the view model, so a
              // trailing blank line or a repeated entry is not an error here.
              onChanged(field.text.split('\n'));
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    field.dispose();
  }
}

final class _ProviderSettingsButton extends StatelessWidget {
  const _ProviderSettingsButton({required this.viewModel});

  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return SwarGhostButton(
      key: const Key('provider-settings-button'),
      label: 'Configure',
      onPressed: () => _show(context),
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
    return FutureBuilder<List<SwarMicrophone>>(
      future: _microphones,
      builder: (context, snapshot) {
        final microphones = snapshot.data ?? const <SwarMicrophone>[];
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        if (microphones.isEmpty) {
          return SwarGhostButton(
            label: 'Check microphones',
            icon: Icons.refresh_rounded,
            onPressed: _reload,
          );
        }

        final savedId = widget.viewModel.settings.microphoneId;
        final selected = microphones.where((item) => item.id == savedId);
        final active = selected.isNotEmpty
            ? selected.first
            : microphones.firstWhere(
                (item) => item.isBuiltIn,
                orElse: () => microphones.first,
              );
        return _MenuDropdown<String>(
          fieldKey: ValueKey('microphone-${active.id}'),
          value: active.id,
          minWidth: 220,
          items: microphones.map((m) => m.id).toList(growable: false),
          labelFor: (id) {
            final mic = microphones.firstWhere((m) => m.id == id);
            return mic.name;
          },
          onChanged: widget.viewModel.setMicrophoneId,
        );
      },
    );
  }

  void _reload() {
    setState(() {
      _microphones = widget.sessionViewModel.listMicrophones();
    });
  }
}
