// apps/swar_desktop/lib/diagnostics/presentation/core_diagnostics_page.dart

import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_colors.dart';
import 'package:swar_desktop/design_system/swar_spacing.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/diagnostics/presentation/core_diagnostics_card.dart';

/// Phase 0 bridge verification screen. Presentation Layer.
class CoreDiagnosticsPage extends StatelessWidget {
  const CoreDiagnosticsPage({required this.gateway, super.key});

  final CoreDiagnosticsGateway gateway;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('diagnostics-page'),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Padding(
              padding: const EdgeInsets.all(SwarSpacing.xl),
              child: _DiagnosticsContent(gateway: gateway),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiagnosticsContent extends StatelessWidget {
  const _DiagnosticsContent({required this.gateway});

  final CoreDiagnosticsGateway gateway;

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
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(SwarSpacing.lg),
                        child: CoreDiagnosticsCard(gateway: gateway),
                      ),
                    ),
                  ),
                  const SizedBox(width: SwarSpacing.md),
                  Expanded(child: _PrivacyCard()),
                ],
              )
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(SwarSpacing.lg),
                  child: CoreDiagnosticsCard(gateway: gateway),
                ),
              ),
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
          'Phase 0 health check',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
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
              key: const Key('privacy-copy'),
              'Audio, writing preferences, and dictation history stay on your computer.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
