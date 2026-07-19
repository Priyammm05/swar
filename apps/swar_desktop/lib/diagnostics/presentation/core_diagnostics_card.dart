// apps/swar_desktop/lib/diagnostics/presentation/core_diagnostics_card.dart

import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_colors.dart';
import 'package:swar_desktop/design_system/swar_spacing.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/diagnostics/presentation/core_diagnostics_state.dart';
import 'package:swar_desktop/diagnostics/presentation/core_diagnostics_view_model.dart';

/// Reusable system-check card. Presentation Layer.
final class CoreDiagnosticsCard extends StatefulWidget {
  const CoreDiagnosticsCard({required this.gateway, super.key});

  final CoreDiagnosticsGateway gateway;

  @override
  State<CoreDiagnosticsCard> createState() => _CoreDiagnosticsCardState();
}

final class _CoreDiagnosticsCardState extends State<CoreDiagnosticsCard> {
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
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final state = _viewModel.state;
        final isChecking = state.status == CoreConnectionStatus.checking;
        final isReady = state.status == CoreConnectionStatus.ready;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isReady ? Icons.check_circle_rounded : Icons.memory_rounded,
              color: isReady ? SwarColors.spruce : SwarColors.lightInkMuted,
            ),
            const SizedBox(height: SwarSpacing.md),
            Text(
              isReady ? 'Offline engine ready' : 'Offline engine',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: SwarSpacing.xs),
            Text(
              key: const Key('core-status'),
              isReady
                  ? 'Connected. Version ${state.version}'
                  : 'Make sure Swar can reach the engine running on this computer.',
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
                    .map(
                      (event) => Chip(
                        key: Key('core-event-$event'),
                        label: Text('$event'),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: SwarSpacing.lg),
            FilledButton.icon(
              key: const Key('check-core-button'),
              onPressed: isChecking ? null : _viewModel.checkCore,
              icon: isChecking
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(isChecking ? 'Checking' : 'Run system check'),
            ),
          ],
        );
      },
    );
  }
}
