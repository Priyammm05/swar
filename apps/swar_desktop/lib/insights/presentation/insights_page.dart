import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_colors.dart';
import 'package:swar_desktop/insights/domain/insights_repository.dart';
import 'package:swar_desktop/insights/domain/insights_snapshot.dart';
import 'package:swar_desktop/insights/presentation/insights_view_model.dart';

/// Insights dashboard translated from the approved HTML. Presentation Layer.
final class InsightsPage extends StatefulWidget {
  const InsightsPage({required this.repository, super.key});

  final InsightsRepository repository;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

final class _InsightsPageState extends State<InsightsPage> {
  late final InsightsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = InsightsViewModel(repository: widget.repository)..load();
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
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final dense = !compact && constraints.maxHeight < 860;
          final outerHorizontalPadding = compact ? 16.0 : (dense ? 20.0 : 32.0);
          final outerVerticalPadding = compact ? 20.0 : (dense ? 16.0 : 32.0);
          final canvasPadding = compact ? 20.0 : (dense ? 24.0 : 40.0);
          final sectionGap = dense ? 24.0 : 32.0;
          return SingleChildScrollView(
            key: const Key('insights-grid'),
            padding: EdgeInsets.symmetric(
              horizontal: outerHorizontalPadding,
              vertical: outerVerticalPadding,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: math.max(
                      0,
                      constraints.maxHeight - outerVerticalPadding * 2,
                    ),
                  ),
                  padding: EdgeInsets.all(canvasPadding),
                  decoration: BoxDecoration(
                    color: SwarColors.surface,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x08000000),
                        blurRadius: 8,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, innerConstraints) {
                      final wideTop = innerConstraints.maxWidth >= 1040;
                      final wideBottom = innerConstraints.maxWidth >= 900;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _InsightsHeader(dense: dense),
                          SizedBox(height: sectionGap),
                          _TopMetrics(
                            wide: wideTop,
                            dense: dense,
                            snapshot: _viewModel.snapshot,
                          ),
                          SizedBox(height: sectionGap),
                          _BottomMetrics(
                            wide: wideBottom,
                            dense: dense,
                            snapshot: _viewModel.snapshot,
                          ),
                          if (_viewModel.errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _viewModel.errorMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: SwarColors.mutedInk,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

final class _InsightsHeader extends StatelessWidget {
  const _InsightsHeader({required this.dense});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            'Insights',
            style: dense
                ? Theme.of(context).textTheme.headlineMedium
                : Theme.of(context).textTheme.displaySmall,
          ),
        ),
        Container(
          width: dense ? 32 : 40,
          height: dense ? 32 : 40,
          decoration: BoxDecoration(
            color: SwarColors.surface,
            border: Border.all(color: SwarColors.border),
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(color: Color(0x0A000000), blurRadius: 5),
            ],
          ),
          child: Icon(Icons.ios_share_rounded, size: dense ? 17 : 20),
        ),
      ],
    );
  }
}

final class _TopMetrics extends StatelessWidget {
  const _TopMetrics({
    required this.wide,
    required this.dense,
    required this.snapshot,
  });

  final bool wide;
  final bool dense;
  final SwarInsightsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (wide) {
      return SizedBox(
        height: dense ? 184 : 220,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _PaceCard(
                key: const Key('insights-pace-card'),
                dense: dense,
                wordsPerMinute: snapshot.averageWordsPerMinute,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _CorrectionsCard(
                key: const Key('insights-corrections-card'),
                dense: dense,
                totalDictations: snapshot.totalDictations,
                duration: snapshot.totalSpeechDuration,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 2,
              child: _TotalWordsCard(
                key: const Key('insights-total-card'),
                dense: dense,
                totalWords: snapshot.totalWords,
              ),
            ),
          ],
        ),
      );
    }
    final cardHeight = dense ? 184.0 : 220.0;
    return Column(
      children: [
        SizedBox(
          height: cardHeight,
          child: _PaceCard(
            key: const Key('insights-pace-card'),
            dense: dense,
            wordsPerMinute: snapshot.averageWordsPerMinute,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: cardHeight,
          child: _CorrectionsCard(
            key: const Key('insights-corrections-card'),
            dense: dense,
            totalDictations: snapshot.totalDictations,
            duration: snapshot.totalSpeechDuration,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: cardHeight,
          child: _TotalWordsCard(
            key: const Key('insights-total-card'),
            dense: dense,
            totalWords: snapshot.totalWords,
          ),
        ),
      ],
    );
  }
}

final class _BottomMetrics extends StatelessWidget {
  const _BottomMetrics({
    required this.wide,
    required this.dense,
    required this.snapshot,
  });

  final bool wide;
  final bool dense;
  final SwarInsightsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (wide) {
      return SizedBox(
        height: dense ? 344 : 430,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _DesktopUsageCard(
                key: const Key('insights-activity-card'),
                dense: dense,
                totalDictations: snapshot.totalDictations,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _StreakCard(
                key: const Key('insights-streak-card'),
                dense: dense,
                currentStreak: snapshot.currentStreakDays,
                longestStreak: snapshot.longestStreakDays,
              ),
            ),
          ],
        ),
      );
    }
    final cardHeight = dense ? 344.0 : 430.0;
    return Column(
      children: [
        SizedBox(
          height: cardHeight,
          child: _DesktopUsageCard(
            key: const Key('insights-activity-card'),
            dense: dense,
            totalDictations: snapshot.totalDictations,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: cardHeight,
          child: _StreakCard(
            key: const Key('insights-streak-card'),
            dense: dense,
            currentStreak: snapshot.currentStreakDays,
            longestStreak: snapshot.longestStreakDays,
          ),
        ),
      ],
    );
  }
}

final class _PaceCard extends StatelessWidget {
  const _PaceCard({
    required this.dense,
    required this.wordsPerMinute,
    super.key,
  });

  final bool dense;
  final double wordsPerMinute;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.all(dense ? 20 : 24),
      child: Column(
        children: [
          Text(
            wordsPerMinute.round().toString(),
            style: TextStyle(
              fontSize: dense ? 36 : 48,
              height: 1.05,
              fontWeight: FontWeight.w700,
              letterSpacing: dense ? -1 : -1.5,
            ),
          ),
          const SizedBox(height: 4),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CapsLabel('WORDS PER MINUTE'),
              SizedBox(width: 4),
              Icon(Icons.info_rounded, size: 12, color: Color(0xFFD1D5DB)),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: dense ? 144 : 180,
            height: dense ? 72 : 90,
            child: CustomPaint(
              painter: _GaugePainter(strokeWidth: dense ? 16 : 20),
              child: Align(
                alignment: Alignment(0, 0.78),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Top',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                    ),
                    Text(
                      '0.1%',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.strokeWidth});

  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(10, 10, size.width - 20, (size.height - 10) * 2);
    final background = Paint()
      ..color = SwarColors.surfaceVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final fill = Paint()
      ..color = SwarColors.leaf
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(rect, math.pi, math.pi, false, background);
    canvas.drawArc(rect, math.pi, math.pi * 0.82, false, fill);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.strokeWidth != strokeWidth;
  }
}

final class _CorrectionsCard extends StatelessWidget {
  const _CorrectionsCard({
    required this.dense,
    required this.totalDictations,
    required this.duration,
    super.key,
  });

  final bool dense;
  final int totalDictations;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.all(dense ? 20 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$totalDictations',
            style: TextStyle(
              fontSize: dense ? 36 : 48,
              height: 1.05,
              fontWeight: FontWeight.w700,
              letterSpacing: dense ? -1 : -1.5,
            ),
          ),
          const SizedBox(height: 4),
          const _CapsLabel('LOCAL DICTATIONS'),
          const Spacer(),
          const Divider(height: 1),
          SizedBox(height: dense ? 8 : 12),
          _CorrectionRow(value: '$totalDictations', label: 'transcripts saved'),
          SizedBox(height: dense ? 8 : 12),
          _CorrectionRow(
            value: '${duration.inMinutes}',
            label: 'minutes spoken',
          ),
        ],
      ),
    );
  }
}

final class _CorrectionRow extends StatelessWidget {
  const _CorrectionRow({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: SwarColors.mutedInk, fontSize: 12),
          ),
        ),
        const Icon(Icons.info_rounded, size: 12, color: Color(0xFFD1D5DB)),
      ],
    );
  }
}

final class _TotalWordsCard extends StatelessWidget {
  const _TotalWordsCard({
    required this.dense,
    required this.totalWords,
    super.key,
  });

  final bool dense;
  final int totalWords;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.all(dense ? 20 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatCount(totalWords),
            style: TextStyle(
              fontSize: dense ? 36 : 48,
              height: 1.05,
              fontWeight: FontWeight.w700,
              letterSpacing: dense ? -1 : -1.5,
            ),
          ),
          const SizedBox(height: 4),
          const _CapsLabel('TOTAL WORDS DICTATED'),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.desktop_windows_outlined,
                          size: 16,
                          color: Color(0xFF4B5563),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Desktop',
                          style: TextStyle(
                            color: Color(0xFF4B5563),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${_formatCount(totalWords)} words',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: dense ? 128 : 142,
                height: dense ? 32 : 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SwarColors.surface,
                  border: Border.all(color: SwarColors.border),
                  borderRadius: BorderRadius.circular(dense ? 10 : 12),
                ),
                child: const Text(
                  'Download on mobile',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _DesktopUsageCard extends StatelessWidget {
  const _DesktopUsageCard({
    required this.dense,
    required this.totalDictations,
    super.key,
  });

  final bool dense;
  final int totalDictations;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.all(dense ? 24 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            title: 'Desktop usage',
            meta: 'LOCAL RECORDS | $totalDictations',
            dense: dense,
          ),
          SizedBox(height: dense ? 20 : 32),
          _UsageRow(
            icon: Icons.memory_outlined,
            percent: totalDictations == 0 ? 0 : 100,
            label: '$totalDictations DICTATIONS',
            color: SwarColors.leaf,
            dense: dense,
          ),
          _UsageRow(
            icon: Icons.swap_horiz_rounded,
            label: '0 OTHER TASKS',
            color: SwarColors.leafMid,
            dense: dense,
          ),
          _UsageRow(
            icon: Icons.mail_outline_rounded,
            label: '0 EMAILS',
            dense: dense,
          ),
          _UsageRow(
            icon: Icons.chat_outlined,
            label: '0 WORK MESSAGES',
            dense: dense,
          ),
          _UsageRow(
            icon: Icons.chat_bubble_outline_rounded,
            label: '0 PERSONAL MESSAGES',
            dense: dense,
          ),
          _UsageRow(
            icon: Icons.description_outlined,
            label: '0 DOCUMENTS',
            dense: dense,
          ),
        ],
      ),
    );
  }
}

final class _UsageRow extends StatelessWidget {
  const _UsageRow({
    required this.icon,
    required this.label,
    required this.dense,
    this.percent = 0,
    this.color = SwarColors.leafLight,
  });

  final IconData icon;
  final int percent;
  final String label;
  final Color color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 10 : 13),
      child: Row(
        children: [
          SizedBox(
            width: dense ? 20 : 24,
            child: Icon(
              icon,
              size: dense ? 18 : 20,
              color: const Color(0xFF4B5563),
            ),
          ),
          SizedBox(width: dense ? 12 : 16),
          Expanded(
            child: Container(
              height: dense ? 20 : 24,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: SwarColors.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: percent / 100,
                child: ColoredBox(
                  color: color,
                  child: Center(
                    child: percent == 0
                        ? const SizedBox.shrink()
                        : Text(
                            '$percent%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: dense ? 12 : 16),
          SizedBox(
            width: dense ? 110 : 128,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: SwarColors.mutedInk,
                fontSize: dense ? 9 : 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _StreakCard extends StatelessWidget {
  const _StreakCard({
    required this.dense,
    required this.currentStreak,
    required this.longestStreak,
    super.key,
  });

  final bool dense;
  final int currentStreak;
  final int longestStreak;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.all(dense ? 24 : 32),
      child: Column(
        children: [
          _CardHeader(
            title: '$currentStreak day streak',
            meta: 'LONGEST STREAK | $longestStreak DAYS',
            dense: dense,
          ),
          SizedBox(height: dense ? 12 : 16),
          const _MonthHeader(),
          SizedBox(height: dense ? 12 : 16),
          Expanded(child: _HeatMap(currentStreak: currentStreak)),
          SizedBox(height: dense ? 16 : 24),
          const _HeatLegend(),
        ],
      ),
    );
  }
}

final class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.title,
    required this.meta,
    required this.dense,
  });

  final String title;
  final String meta;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: dense ? 20 : 24,
              height: 1.33,
              fontWeight: FontWeight.w700,
              letterSpacing: dense ? -0.2 : -0.24,
            ),
          ),
        ),
        Text(
          meta,
          style: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

final class _MonthHeader extends StatelessWidget {
  const _MonthHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.chevron_left_rounded, size: 16, color: Color(0xFFD1D5DB)),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _CapsLabel('APR'),
              _CapsLabel('MAY'),
              _CapsLabel('JUN'),
              _CapsLabel('JUL'),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFFD1D5DB)),
      ],
    );
  }
}

final class _HeatMap extends StatelessWidget {
  const _HeatMap({required this.currentStreak});

  final int currentStreak;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellSize = math.min(
          28.0,
          math.min(
            (constraints.maxWidth - 54) / 12 - 4,
            constraints.maxHeight / 7 - 4,
          ),
        );
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var row = 0; row < 7; row++)
              Row(
                children: [
                  SizedBox(
                    width: 38,
                    child: Text(
                      const [
                        'SUN',
                        'MON',
                        'TUE',
                        'WED',
                        'THU',
                        'FRI',
                        'SAT',
                      ][row],
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (var column = 0; column < 12; column++)
                    Expanded(
                      child: Center(
                        child: Container(
                          width: cellSize,
                          height: cellSize,
                          decoration: BoxDecoration(
                            color:
                                row * 12 + column >=
                                    84 - currentStreak.clamp(0, 84)
                                ? SwarColors.leaf
                                : SwarColors.leafSoft,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

String _formatCount(int value) {
  final digits = value.toString();
  final result = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) result.write(',');
    result.write(digits[index]);
  }
  return result.toString();
}

final class _HeatLegend extends StatelessWidget {
  const _HeatLegend();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _CapsLabel('LESS'),
        SizedBox(width: 8),
        _LegendSquare(color: SwarColors.leafSoft),
        _LegendSquare(color: SwarColors.leafPale),
        _LegendSquare(color: SwarColors.leafLight),
        _LegendSquare(color: SwarColors.leaf),
        SizedBox(width: 5),
        _CapsLabel('MORE'),
        Spacer(),
        _LegendSquare(
          color: SwarColors.leafSoft,
          borderColor: SwarColors.leaf,
          size: 16,
        ),
        SizedBox(width: 8),
        Text(
          'CURRENT STREAK',
          style: TextStyle(
            color: SwarColors.mutedInk,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

final class _LegendSquare extends StatelessWidget {
  const _LegendSquare({required this.color, this.borderColor, this.size = 12});

  final Color color;
  final Color? borderColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: color,
        border: borderColor == null ? null : Border.all(color: borderColor!),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

final class _Panel extends StatelessWidget {
  const _Panel({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SwarColors.panel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

final class _CapsLabel extends StatelessWidget {
  const _CapsLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF9CA3AF),
        fontSize: 10,
        height: 1.6,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}
