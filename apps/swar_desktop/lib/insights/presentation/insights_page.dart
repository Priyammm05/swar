// apps/swar_desktop/lib/insights/presentation/insights_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_components.dart';
import 'package:swar_desktop/design_system/swar_tokens.dart';
import 'package:swar_desktop/design_system/swar_typography.dart';
import 'package:swar_desktop/dictation/domain/dictation_completion_signal.dart';
import 'package:swar_desktop/insights/domain/insights_repository.dart';
import 'package:swar_desktop/insights/domain/insights_snapshot.dart';
import 'package:swar_desktop/insights/presentation/insights_view_model.dart';

/// Insights — locally computed usage, one calm view (spec §7). Presentation Layer.
final class InsightsPage extends StatefulWidget {
  const InsightsPage({
    required this.repository,
    required this.completionSignal,
    super.key,
  });

  final InsightsRepository repository;

  /// Tells the page a dictation has landed. The shell keeps all three pages
  /// alive in an indexed stack, so without this Insights would show whatever
  /// the database held at launch for the rest of the session.
  final DictationCompletionSignal completionSignal;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

final class _InsightsPageState extends State<InsightsPage> {
  late final InsightsViewModel _viewModel;
  late int _completionRevision;

  @override
  void initState() {
    super.initState();
    _viewModel = InsightsViewModel(repository: widget.repository)..load();
    _completionRevision = widget.completionSignal.completionRevision;
    widget.completionSignal.addListener(_handleDictationCompleted);
  }

  @override
  void didUpdateWidget(covariant InsightsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.completionSignal == widget.completionSignal) return;
    oldWidget.completionSignal.removeListener(_handleDictationCompleted);
    _completionRevision = widget.completionSignal.completionRevision;
    widget.completionSignal.addListener(_handleDictationCompleted);
  }

  @override
  void dispose() {
    widget.completionSignal.removeListener(_handleDictationCompleted);
    _viewModel.dispose();
    super.dispose();
  }

  void _handleDictationCompleted() {
    // The session notifies on every audio level and state change. Only a bump
    // in the revision means new data exists to count.
    final revision = widget.completionSignal.completionRevision;
    if (revision == _completionRevision) return;
    _completionRevision = revision;
    unawaited(_viewModel.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final snapshot = _viewModel.snapshot;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1008),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(32, 8, 32, 48),
              children: [
                Row(
                  children: [
                    Text(
                      'Insights',
                      style: SwarType.serifTitle.copyWith(color: t.ink),
                    ),
                    const SizedBox(width: 12),
                    const _OnDevicePill(),
                  ],
                ),
                const SizedBox(height: 18),
                _Grid(snapshot: snapshot),
              ],
            ),
          ),
        );
      },
    );
  }
}

final class _OnDevicePill extends StatelessWidget {
  const _OnDevicePill();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: t.spruceTint,
        borderRadius: BorderRadius.circular(SwarRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 13, color: t.spruce),
          const SizedBox(width: 5),
          Text(
            'on-device',
            style: SwarType.captionMedium.copyWith(color: t.spruce),
          ),
        ],
      ),
    );
  }
}

final class _Grid extends StatelessWidget {
  const _Grid({required this.snapshot});

  final SwarInsightsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const Key('insights-grid'),
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final topCards = [
          _WordsCorrectedCard(snapshot: snapshot),
          _TimeSavedCard(snapshot: snapshot),
          _TotalSpokenCard(
            key: const Key('insights-total-card'),
            snapshot: snapshot,
          ),
        ];
        final pace = _PaceCard(
          key: const Key('insights-pace-card'),
          snapshot: snapshot,
        );
        final streak = _StreakCard(
          key: const Key('insights-streak-card'),
          snapshot: snapshot,
        );
        final language = _LanguageSplitCard(snapshot: snapshot);
        final apps = _WhereYouDictateCard(snapshot: snapshot);

        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in topCards) ...[
                card,
                const SizedBox(height: 14),
              ],
              language,
              const SizedBox(height: 14),
              pace,
              const SizedBox(height: 14),
              apps,
              const SizedBox(height: 14),
              streak,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Row(
              children: [
                Expanded(child: topCards[0]),
                const SizedBox(width: 14),
                Expanded(child: topCards[1]),
                const SizedBox(width: 14),
                Expanded(child: topCards[2]),
              ],
            ),
            const SizedBox(height: 14),
            _Row(
              children: [
                Expanded(flex: 14, child: language),
                const SizedBox(width: 14),
                Expanded(flex: 10, child: pace),
              ],
            ),
            const SizedBox(height: 14),
            _Row(
              children: [
                Expanded(child: apps),
                const SizedBox(width: 14),
                Expanded(child: streak),
              ],
            ),
          ],
        );
      },
    );
  }
}

final class _Row extends StatelessWidget {
  const _Row({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Top-aligned rather than IntrinsicHeight-stretched: the cards contain
    // flex-based bars that have no intrinsic height, and the page scrolls, so
    // an unbounded stretch would fail to lay out.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

// --- top cards ---

final class _StatCard extends StatelessWidget {
  const _StatCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SwarCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: child,
    );
  }
}

final class _UppercaseLabel extends StatelessWidget {
  const _UppercaseLabel(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      text.toUpperCase(),
      style: SwarType.uppercaseLabel.copyWith(color: color ?? t.inkMuted),
    );
  }
}

final class _WordsCorrectedCard extends StatelessWidget {
  const _WordsCorrectedCard({required this.snapshot});

  final SwarInsightsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _StatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _UppercaseLabel('Words corrected'),
          const SizedBox(height: 10),
          Text(
            '${snapshot.wordsCorrected}',
            style: SwarType.statHero.copyWith(color: t.ink),
          ),
          const SizedBox(height: 14),
          _FooterLine(
            chipIcon: Icons.menu_book_rounded,
            chipFg: t.spruce,
            chipBg: t.spruceTint,
            text: '${snapshot.dictionaryHits} from your dictionary',
          ),
        ],
      ),
    );
  }
}

final class _TimeSavedCard extends StatelessWidget {
  const _TimeSavedCard({required this.snapshot});

  final SwarInsightsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hours = snapshot.timeSaved.inMinutes / 60;
    return SwarCard(
      filled: t.spruce,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UppercaseLabel('Time saved', color: t.spruceSoft),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                hours.toStringAsFixed(1),
                style: SwarType.statHero.copyWith(color: t.saffron),
              ),
              const SizedBox(width: 4),
              Text(
                'hrs',
                style: SwarType.rowTitle.copyWith(
                  color: t.saffron,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'vs typing at 40 wpm · '),
                TextSpan(
                  text: 'estimate',
                  style: TextStyle(color: t.spruceInk),
                ),
              ],
              style: SwarType.description.copyWith(color: t.spruceSoft),
            ),
          ),
        ],
      ),
    );
  }
}

final class _TotalSpokenCard extends StatelessWidget {
  const _TotalSpokenCard({required this.snapshot, super.key});

  final SwarInsightsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final minutes = snapshot.totalSpeechDuration.inMinutes;
    final wpm = snapshot.averageWordsPerMinute.round();
    return _StatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _UppercaseLabel('Total time spoken'),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$minutes', style: SwarType.statHero.copyWith(color: t.ink)),
              const SizedBox(width: 4),
              Text(
                'min',
                style: SwarType.rowTitle.copyWith(
                  color: t.inkSecondary,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _FooterLine(
            chipIcon: Icons.bolt_rounded,
            chipFg: t.saffronInk,
            chipBg: t.saffronTint,
            text: '${snapshot.totalWords} words · $wpm wpm',
          ),
        ],
      ),
    );
  }
}

final class _FooterLine extends StatelessWidget {
  const _FooterLine({
    required this.chipIcon,
    required this.chipFg,
    required this.chipBg,
    required this.text,
  });

  final IconData chipIcon;
  final Color chipFg;
  final Color chipBg;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: chipBg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(chipIcon, size: 13, color: chipFg),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: SwarType.description.copyWith(color: t.inkSecondary),
          ),
        ),
      ],
    );
  }
}

// --- language split ---

final class _LanguageSplitCard extends StatelessWidget {
  const _LanguageSplitCard({required this.snapshot});

  final SwarInsightsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bars = [
      ('English', snapshot.englishShare, t.spruce),
      ('Hindi', snapshot.hindiShare, t.spruceMid),
      ('Hinglish', snapshot.hinglishShare, t.saffron),
    ];
    final maxShare = bars.map((b) => b.$2).fold(0.0, (a, b) => a > b ? a : b);
    return SwarCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeading(
            title: 'Language split',
            caption: 'what you actually speak',
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final bar in bars)
                  Expanded(
                    child: _LanguageBar(
                      label: bar.$1,
                      share: bar.$2,
                      maxShare: maxShare,
                      color: bar.$3,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(height: 0.5, color: t.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.translate_rounded, size: 14, color: t.inkSecondary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Mixed speech is kept as spoken — never translated.',
                  style: SwarType.caption.copyWith(color: t.inkSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _LanguageBar extends StatelessWidget {
  const _LanguageBar({
    required this.label,
    required this.share,
    required this.maxShare,
    required this.color,
  });

  final String label;
  final double share;
  final double maxShare;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fraction = maxShare == 0 ? 0.0 : share / maxShare;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: share == 0 ? 0.02 : fraction.clamp(0.04, 1.0),
              child: Container(
                width: 54,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                    bottom: Radius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: SwarType.nav.copyWith(color: t.ink)),
        const SizedBox(height: 2),
        Text(
          '${(share * 100).round()}%',
          style: SwarType.caption.copyWith(color: t.inkMuted),
        ),
      ],
    );
  }
}

// --- speaking pace ---

final class _PaceCard extends StatelessWidget {
  const _PaceCard({required this.snapshot, super.key});

  final SwarInsightsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SwarCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeading(title: 'Speaking pace'),
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                Text(
                  '${snapshot.averageWordsPerMinute.round()}',
                  style: SwarType.wpmHero.copyWith(color: t.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  'WORDS / MIN',
                  style: SwarType.uppercaseLabel.copyWith(color: t.inkMuted),
                ),
                const SizedBox(height: 14),
                const _PaceWaveform(),
                const SizedBox(height: 12),
                Text(
                  'faster than most typing',
                  style: SwarType.description.copyWith(color: t.inkSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _PaceWaveform extends StatelessWidget {
  const _PaceWaveform();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const heights = [10.0, 16.0, 22.0, 26.0, 18.0, 12.0];
    final colors = [
      t.spruceSoft,
      t.spruceSoft,
      t.spruce,
      t.spruce,
      t.spruce,
      t.spruceSoft,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < heights.length; i++) ...[
          Container(
            width: 4,
            height: heights[i],
            decoration: BoxDecoration(
              color: colors[i],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (i != heights.length - 1) const SizedBox(width: 3),
        ],
      ],
    );
  }
}

// --- where you dictate ---

final class _WhereYouDictateCard extends StatelessWidget {
  const _WhereYouDictateCard({required this.snapshot});

  final SwarInsightsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final total = snapshot.totalAppEvents;
    final apps = snapshot.appUsage.take(3).toList();
    final palette = [t.spruce, t.spruceMid, t.spruceSoft];
    final barText = [t.spruceInk, t.spruceInk, t.spruce];
    return SwarCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeading(
            title: 'Where you dictate',
            caption: '${snapshot.distinctAppCount} apps',
          ),
          const SizedBox(height: 16),
          if (apps.isEmpty)
            Text(
              'No dictations yet.',
              style: SwarType.description.copyWith(color: t.inkMuted),
            )
          else
            for (var i = 0; i < apps.length; i++) ...[
              _AppUsageRow(
                usage: apps[i],
                share: total == 0 ? 0 : apps[i].count / total,
                barColor: palette[i % palette.length],
                textOnBar: barText[i % barText.length],
              ),
              if (i != apps.length - 1) const SizedBox(height: 12),
            ],
          const SizedBox(height: 16),
          Container(height: 0.5, color: t.border),
          const SizedBox(height: 12),
          Text(
            'Counts come from the app in focus, not its contents.',
            style: SwarType.caption.copyWith(color: t.inkMuted),
          ),
        ],
      ),
    );
  }
}

final class _AppUsageRow extends StatelessWidget {
  const _AppUsageRow({
    required this.usage,
    required this.share,
    required this.barColor,
    required this.textOnBar,
  });

  final SwarAppUsage usage;
  final double share;
  final Color barColor;
  final Color textOnBar;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Icon(_iconFor(usage.name), size: 17, color: t.inkSecondary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth * share).clamp(
                32.0,
                constraints.maxWidth,
              );
              return Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: width,
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '${(share * 100).round()}%',
                    style: SwarType.captionMedium.copyWith(color: textOnBar),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 74,
          child: Text(
            usage.name,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: SwarType.caption.copyWith(color: t.inkSecondary),
          ),
        ),
      ],
    );
  }

  IconData _iconFor(String app) {
    final name = app.toLowerCase();
    if (name.contains('code') ||
        name.contains('studio') ||
        name.contains('term') ||
        name.contains('xcode')) {
      return Icons.code_rounded;
    }
    if (name.contains('mail') || name.contains('outlook')) {
      return Icons.mail_outline_rounded;
    }
    if (name.contains('slack') ||
        name.contains('chat') ||
        name.contains('message') ||
        name.contains('discord') ||
        name.contains('teams')) {
      return Icons.chat_bubble_outline_rounded;
    }
    return Icons.window_rounded;
  }
}

// --- streak heatmap ---

final class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.snapshot, super.key});

  final SwarInsightsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SwarCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeading(
            title: '${snapshot.currentStreakDays}-day streak',
            caption: 'longest · ${snapshot.longestStreakDays} days',
          ),
          const SizedBox(height: 6),
          Text(
            'Days you dictated at least once.',
            style: SwarType.caption.copyWith(color: t.inkSecondary),
          ),
          const SizedBox(height: 14),
          _Heatmap(activity: snapshot.dailyActivity),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Less', style: SwarType.caption.copyWith(color: t.inkMuted)),
              const SizedBox(width: 6),
              for (final color in t.streakRamp) ...[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              const SizedBox(width: 2),
              Text('More', style: SwarType.caption.copyWith(color: t.inkMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

final class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.activity});

  final List<int> activity;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Render 20 columns of 7 days; take the most recent window.
    const columns = 20;
    const rows = 7;
    const cells = columns * rows;
    final tail = activity.length >= cells
        ? activity.sublist(activity.length - cells)
        : <int>[...List<int>.filled(cells - activity.length, 0), ...activity];
    final maxCount = tail.fold(0, (a, b) => a > b ? a : b);

    Color colorFor(int count) {
      if (count <= 0) return t.streakEmpty;
      if (maxCount <= 1) return t.streakRamp[3];
      final ratio = count / maxCount;
      if (ratio > 0.66) return t.streakRamp[3];
      if (ratio > 0.33) return t.streakRamp[2];
      return t.streakRamp[1];
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 4.0;
        final cell = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < cells; i++)
              Container(
                width: cell,
                height: cell,
                decoration: BoxDecoration(
                  color: colorFor(tail[i]),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        );
      },
    );
  }
}

final class _CardHeading extends StatelessWidget {
  const _CardHeading({required this.title, this.caption});

  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: SwarType.cardHeading.copyWith(color: t.ink),
          ),
        ),
        if (caption != null)
          Text(caption!, style: SwarType.caption.copyWith(color: t.inkMuted)),
      ],
    );
  }
}
