// apps/swar_desktop/lib/diagnostics/presentation/core_diagnostics_page.dart

import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_colors.dart';
import 'package:swar_desktop/design_system/swar_spacing.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/diagnostics/presentation/core_diagnostics_state.dart';
import 'package:swar_desktop/diagnostics/presentation/core_diagnostics_view_model.dart';

/// Phase 0 bridge verification screen. Presentation Layer.
class CoreDiagnosticsPage extends StatefulWidget {
  const CoreDiagnosticsPage({required this.gateway, super.key});

  final CoreDiagnosticsGateway gateway;

  @override
  State<CoreDiagnosticsPage> createState() => _CoreDiagnosticsPageState();
}

class _CoreDiagnosticsPageState extends State<CoreDiagnosticsPage> {
  late final CoreDiagnosticsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = CoreDiagnosticsViewModel(gateway: widget.gateway);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Padding(
              padding: const EdgeInsets.all(SwarSpacing.xl),
              child: ListenableBuilder(
                listenable: _viewModel,
                builder: (context, _) => _DiagnosticsContent(
                  state: _viewModel.state,
                  onCheckCore: _viewModel.checkCore,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiagnosticsContent extends StatelessWidget {
  const _DiagnosticsContent({required this.state, required this.onCheckCore});

  final CoreDiagnosticsState state;
  final VoidCallback onCheckCore;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          children: [
            const _Wordmark(),
            const SizedBox(height: SwarSpacing.xxl),
            Text(
              'Your voice stays yours.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: SwarSpacing.sm),
            Text(
              'Swar improves clarity without replacing how you sound. Everything runs on this computer.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: SwarSpacing.xl),
            if (constraints.maxWidth >= 620)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _CoreCard(state: state, onCheckCore: onCheckCore),
                  ),
                  const SizedBox(width: SwarSpacing.md),
                  Expanded(child: _PrivacyCard()),
                ],
              )
            else ...[
              _CoreCard(state: state, onCheckCore: onCheckCore),
              const SizedBox(height: SwarSpacing.md),
              const _PrivacyCard(),
            ],
          ],
        );
      },
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: SwarColors.leaf,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: const Icon(
            Icons.graphic_eq_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: SwarSpacing.sm),
        Text('swar', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        Text(
          'Architecture check',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _CoreCard extends StatelessWidget {
  const _CoreCard({required this.state, required this.onCheckCore});

  final CoreDiagnosticsState state;
  final VoidCallback onCheckCore;

  @override
  Widget build(BuildContext context) {
    final isChecking = state.status == CoreConnectionStatus.checking;
    final isReady = state.status == CoreConnectionStatus.ready;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SwarSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isReady ? Icons.check_circle_rounded : Icons.memory_rounded,
              color: isReady ? SwarColors.leaf : SwarColors.mutedInk,
            ),
            const SizedBox(height: SwarSpacing.md),
            Text('Native core', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: SwarSpacing.xs),
            Text(
              isReady
                  ? 'Connected. Version ${state.version}'
                  : 'Verify Flutter can call Rust and receive events.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (state.errorMessage case final message?) ...[
              const SizedBox(height: SwarSpacing.sm),
              Text(message, style: const TextStyle(color: SwarColors.danger)),
            ],
            if (state.events.isNotEmpty) ...[
              const SizedBox(height: SwarSpacing.md),
              Wrap(
                spacing: SwarSpacing.sm,
                children: state.events
                    .map((event) => Chip(label: Text('$event')))
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: SwarSpacing.lg),
            FilledButton.icon(
              key: const Key('check-core-button'),
              onPressed: isChecking ? null : onCheckCore,
              icon: isChecking
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(isChecking ? 'Checking' : 'Check native core'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SwarSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_outline_rounded, color: SwarColors.leaf),
            const SizedBox(height: SwarSpacing.md),
            Text(
              'Local by design',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: SwarSpacing.xs),
            Text(
              'Audio, writing preferences, and dictation history stay on your computer.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
