// apps/swar_desktop/lib/insights/presentation/insights_page.dart

import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_colors.dart';
import 'package:swar_desktop/design_system/swar_spacing.dart';

/// Local insights view with Phase 1 sample values. Presentation Layer.
final class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(SwarSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Insights',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(width: SwarSpacing.sm),
                const Chip(label: Text('Preview data')),
              ],
            ),
            const SizedBox(height: SwarSpacing.xs),
            Text(
              'A private view of how speaking fits into your day.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: SwarSpacing.lg),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const cards = <Widget>[
                    _InsightCard(
                      label: 'Speaking pace',
                      value: '142 WPM',
                      note: 'Your recent average',
                      icon: Icons.speed_rounded,
                    ),
                    _InsightCard(
                      label: 'Words dictated',
                      value: '12,480',
                      note: 'Stored only on this computer',
                      icon: Icons.notes_rounded,
                    ),
                    _InsightCard(
                      label: 'Dictations',
                      value: '286',
                      note: 'Across your local history',
                      icon: Icons.mic_rounded,
                    ),
                    _InsightCard(
                      label: 'Estimated time saved',
                      value: '3h 18m',
                      note: 'Compared with typing at 40 WPM',
                      icon: Icons.schedule_rounded,
                    ),
                  ];
                  return GridView.builder(
                    key: const Key('insights-grid'),
                    itemCount: cards.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: constraints.maxWidth >= 920 ? 4 : 2,
                      crossAxisSpacing: SwarSpacing.md,
                      mainAxisSpacing: SwarSpacing.md,
                      mainAxisExtent: 232,
                    ),
                    itemBuilder: (context, index) => cards[index],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
  });

  final String label;
  final String value;
  final String note;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SwarSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: SwarColors.leaf),
            const Spacer(),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: SwarSpacing.xs),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontSize: 26),
            ),
            const SizedBox(height: SwarSpacing.xs),
            Text(note, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
