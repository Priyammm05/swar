// apps/swar_desktop/lib/settings/presentation/settings_page.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:swar_desktop/app/swar_routes.dart';
import 'package:swar_desktop/design_system/swar_colors.dart';
import 'package:swar_desktop/design_system/swar_spacing.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/diagnostics/presentation/core_diagnostics_card.dart';
import 'package:swar_desktop/settings/domain/swar_settings.dart';
import 'package:swar_desktop/settings/presentation/settings_view_model.dart';

enum SettingsSection { general, system }

/// Settings view. Presentation Layer.
final class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.section,
    required this.viewModel,
    required this.diagnosticsGateway,
    super.key,
  });

  final SettingsSection section;
  final SettingsViewModel viewModel;
  final CoreDiagnosticsGateway diagnosticsGateway;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(SwarSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: SwarSpacing.xs),
            Text(
              'Choose how Swar listens, writes, and behaves on this computer.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: SwarSpacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<SettingsSection>(
                key: const Key('settings-section-control'),
                segments: const [
                  ButtonSegment(
                    value: SettingsSection.general,
                    label: Text('General'),
                    icon: Icon(Icons.tune_rounded),
                  ),
                  ButtonSegment(
                    value: SettingsSection.system,
                    label: Text('System'),
                    icon: Icon(Icons.computer_rounded),
                  ),
                ],
                selected: {section},
                onSelectionChanged: (selection) {
                  final selected = selection.single;
                  context.go(
                    selected == SettingsSection.general
                        ? SwarRoutes.generalSettings
                        : SwarRoutes.systemSettings,
                  );
                },
              ),
            ),
            const SizedBox(height: SwarSpacing.lg),
            Expanded(
              child: ListenableBuilder(
                listenable: viewModel,
                builder: (context, _) {
                  return switch (section) {
                    SettingsSection.general => _GeneralSettings(
                      viewModel: viewModel,
                    ),
                    SettingsSection.system => _SystemSettings(
                      viewModel: viewModel,
                      diagnosticsGateway: diagnosticsGateway,
                    ),
                  };
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _GeneralSettings extends StatelessWidget {
  const _GeneralSettings({required this.viewModel});

  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final settings = viewModel.settings;
    return ListView(
      key: const Key('general-settings-page'),
      children: [
        _SettingsCard(
          title: 'Shortcut',
          description: 'Hold your shortcut anywhere to speak with Swar.',
          child: Row(
            children: [
              const _ShortcutKey(label: 'Control'),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: SwarSpacing.xs),
                child: Text('+'),
              ),
              const _ShortcutKey(label: 'Space'),
              const Spacer(),
              const OutlinedButton(onPressed: null, child: Text('Change')),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Dictation language',
          description:
              'Swar can preserve English, Hindi, and Hinglish as you speak.',
          child: DropdownButtonFormField<SwarLanguagePreference>(
            key: const Key('language-setting'),
            initialValue: settings.language,
            decoration: const InputDecoration(border: OutlineInputBorder()),
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
              if (value != null) {
                viewModel.setLanguage(value);
              }
            },
          ),
        ),
        _SettingsCard(
          title: 'Writing mode',
          description: 'Choose how much Swar should shape the words you speak.',
          child: SegmentedButton<SwarWritingMode>(
            key: const Key('writing-mode-setting'),
            segments: const [
              ButtonSegment(value: SwarWritingMode.raw, label: Text('Raw')),
              ButtonSegment(value: SwarWritingMode.clean, label: Text('Clean')),
              ButtonSegment(
                value: SwarWritingMode.intent,
                label: Text('Intent'),
              ),
            ],
            selected: {settings.writingMode},
            onSelectionChanged: (selection) {
              viewModel.setWritingMode(selection.single);
            },
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
    return ListView(
      key: const Key('system-settings-page'),
      children: [
        _SettingsCard(
          title: 'App behaviour',
          description: 'Keep Swar close without letting it get in your way.',
          child: Column(
            children: [
              SwitchListTile(
                key: const Key('launch-at-login-setting'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Launch Swar when I sign in'),
                value: settings.launchAtLogin,
                onChanged: (value) {
                  viewModel.setLaunchAtLogin(enabled: value);
                },
              ),
              SwitchListTile(
                key: const Key('show-in-dock-setting'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Show Swar in the Dock or taskbar'),
                value: settings.showInDock,
                onChanged: (value) {
                  viewModel.setShowInDock(enabled: value);
                },
              ),
              SwitchListTile(
                key: const Key('keep-models-warm-setting'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep the voice model ready'),
                subtitle: const Text(
                  'Uses more memory but starts dictation faster.',
                ),
                value: settings.keepModelsWarm,
                onChanged: (value) {
                  viewModel.setKeepModelsWarm(enabled: value);
                },
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'System check',
          description:
              'Confirm that Swar can reach its private offline engine.',
          child: CoreDiagnosticsCard(gateway: diagnosticsGateway),
        ),
      ],
    );
  }
}

final class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SwarSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(SwarSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: SwarSpacing.xs),
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: SwarSpacing.md),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

final class _ShortcutKey extends StatelessWidget {
  const _ShortcutKey({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: SwarColors.canvas,
        border: Border.all(color: SwarColors.border),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(label),
    );
  }
}
