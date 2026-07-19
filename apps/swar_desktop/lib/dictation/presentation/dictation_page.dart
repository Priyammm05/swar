import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_colors.dart';
import 'package:swar_desktop/dictation/domain/dictation_history_repository.dart';
import 'package:swar_desktop/dictation/domain/dictation_record.dart';
import 'package:swar_desktop/dictation/presentation/dictation_history_view_model.dart';
import 'package:swar_desktop/dictation/presentation/dictation_session_view_model.dart';
import 'package:swar_desktop/settings/presentation/settings_view_model.dart';

/// Dictation overview translated from the approved HTML. Presentation Layer.
final class DictationPage extends StatefulWidget {
  const DictationPage({
    required this.repository,
    required this.sessionViewModel,
    required this.settingsViewModel,
    super.key,
  });

  final DictationHistoryRepository repository;
  final DictationSessionViewModel sessionViewModel;
  final SettingsViewModel settingsViewModel;

  @override
  State<DictationPage> createState() => _DictationPageState();
}

final class _DictationPageState extends State<DictationPage> {
  late final DictationHistoryViewModel _viewModel;
  late int _completionRevision;

  @override
  void initState() {
    super.initState();
    _viewModel = DictationHistoryViewModel(repository: widget.repository)
      ..load();
    _completionRevision = widget.sessionViewModel.completionRevision;
    widget.sessionViewModel.addListener(_handleSessionChanged);
  }

  @override
  void didUpdateWidget(covariant DictationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionViewModel == widget.sessionViewModel) return;
    oldWidget.sessionViewModel.removeListener(_handleSessionChanged);
    _completionRevision = widget.sessionViewModel.completionRevision;
    widget.sessionViewModel.addListener(_handleSessionChanged);
  }

  @override
  void dispose() {
    widget.sessionViewModel.removeListener(_handleSessionChanged);
    _viewModel.dispose();
    super.dispose();
  }

  void _handleSessionChanged() {
    final revision = widget.sessionViewModel.completionRevision;
    if (revision == _completionRevision) return;
    _completionRevision = revision;
    unawaited(_viewModel.refresh());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final dense = !compact && constraints.maxHeight < 860;
          final outerPadding = compact ? 16.0 : (dense ? 20.0 : 32.0);
          final canvasPadding = compact ? 20.0 : (dense ? 24.0 : 40.0);
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: outerPadding,
              vertical: compact ? 20 : (dense ? 16 : 32),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: math.max(0, constraints.maxHeight - 80),
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
                      final wide = innerConstraints.maxWidth >= 980;
                      final summary = _OverviewSummary(
                        totalDictations: _viewModel.totalCount,
                        dense: dense,
                      );
                      final feed = _TranscriptionFeed(
                        viewModel: _viewModel,
                        dense: dense,
                        learningOptedIn:
                            widget.settingsViewModel.settings.learnFromEdits,
                      );
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: summary),
                            SizedBox(width: dense ? 24 : 32),
                            Expanded(flex: 9, child: feed),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [summary, const SizedBox(height: 32), feed],
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

final class _OverviewSummary extends StatelessWidget {
  const _OverviewSummary({required this.totalDictations, required this.dense});

  final int totalDictations;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Welcome back, Priyam',
          style: TextStyle(
            fontSize: 24,
            height: 1.33,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.24,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Here is your dictation overview.',
          style: TextStyle(
            color: SwarColors.mutedInk,
            fontSize: 14,
            height: 1.43,
          ),
        ),
        SizedBox(height: dense ? 20 : 32),
        _SummaryCard(
          label: 'LOCAL DICTATIONS',
          value: '$totalDictations',
          trailing: const Icon(
            Icons.trending_up_rounded,
            color: SwarColors.leaf,
            size: 20,
          ),
        ),
        SizedBox(height: dense ? 14 : 24),
        const _SummaryCard(label: 'STORAGE', value: 'Local', suffix: 'only'),
        SizedBox(height: dense ? 14 : 24),
        const _SummaryCard(
          label: 'ACTIVE STREAK',
          value: '3',
          suffix: 'days',
          showStreak: true,
        ),
      ],
    );
  }
}

final class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    this.suffix,
    this.trailing,
    this.showStreak = false,
  });

  final String label;
  final String value;
  final String? suffix;
  final Widget? trailing;
  final bool showStreak;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: SwarColors.panel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: SwarColors.mutedInk,
              fontSize: 12,
              height: 1.33,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 36,
                      height: 1.12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    suffix!,
                    style: const TextStyle(
                      color: SwarColors.mutedInk,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: trailing!,
                ),
              ],
            ],
          ),
          if (showStreak) ...[
            const SizedBox(height: 16),
            const Row(
              children: [
                _StreakSegment(active: true),
                _StreakSegment(active: true),
                _StreakSegment(active: true),
                _StreakSegment(),
                _StreakSegment(),
                _StreakSegment(),
                _StreakSegment(),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

final class _StreakSegment extends StatelessWidget {
  const _StreakSegment({this.active = false});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 8,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: active ? SwarColors.leaf : SwarColors.surfaceVariant,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

final class _TranscriptionFeed extends StatelessWidget {
  const _TranscriptionFeed({
    required this.viewModel,
    required this.dense,
    required this.learningOptedIn,
  });

  final DictationHistoryViewModel viewModel;
  final bool dense;
  final bool learningOptedIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: dense ? 382 : 464,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SwarColors.panel,
        border: Border.all(color: SwarColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _FeedHeader(viewModel: viewModel, dense: dense),
          Expanded(
            child: _FeedBody(
              viewModel: viewModel,
              dense: dense,
              learningOptedIn: learningOptedIn,
            ),
          ),
          if (viewModel.hasMore)
            _FeedFooter(viewModel: viewModel, dense: dense),
        ],
      ),
    );
  }
}

final class _FeedHeader extends StatelessWidget {
  const _FeedHeader({required this.viewModel, required this.dense});

  final DictationHistoryViewModel viewModel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: dense ? 64 : 80,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SwarColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showLabel = constraints.maxWidth >= 600;
          return Row(
            children: [
              if (showLabel) ...[
                const Text(
                  "TODAY'S ACTIVITY",
                  style: TextStyle(
                    color: SwarColors.mutedInk,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: SwarColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${viewModel.totalCount} ENTRIES',
                    style: TextStyle(
                      color: SwarColors.leaf,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
              ],
              SizedBox(
                width: showLabel
                    ? 256
                    : math.max(150, constraints.maxWidth - 48),
                height: 40,
                child: TextField(
                  key: const Key('dictation-search'),
                  onChanged: viewModel.search,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search transcripts...',
                    hintStyle: const TextStyle(color: Color(0x806B7280)),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: SwarColors.mutedInk,
                    ),
                    filled: true,
                    fillColor: SwarColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: const BorderSide(color: Color(0x33145350)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.filter_list_rounded,
                key: Key('dictation-language-filter'),
                size: 24,
                color: SwarColors.mutedInk,
              ),
            ],
          );
        },
      ),
    );
  }
}

final class _FeedBody extends StatelessWidget {
  const _FeedBody({
    required this.viewModel,
    required this.dense,
    required this.learningOptedIn,
  });

  final DictationHistoryViewModel viewModel;
  final bool dense;
  final bool learningOptedIn;

  @override
  Widget build(BuildContext context) {
    if (viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.errorMessage != null) {
      return _EmptyState(
        icon: Icons.error_outline_rounded,
        title: viewModel.errorMessage!,
      );
    }
    if (viewModel.records.isEmpty) {
      return viewModel.query.searchText.trim().isEmpty
          ? const _EmptyState(
              icon: Icons.mic_none_rounded,
              title: 'Your dictations will appear here',
            )
          : const _EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No matching dictations',
            );
    }
    return ListView.separated(
      key: const Key('dictation-list'),
      itemCount: viewModel.records.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => _TranscriptRow(
        key: Key('dictation-record-$index'),
        record: viewModel.records[index],
        dense: dense,
        onCorrect: (record, value) =>
            viewModel.correct(record, value, learningOptedIn: learningOptedIn),
      ),
    );
  }
}

final class _TranscriptRow extends StatelessWidget {
  const _TranscriptRow({
    required this.record,
    required this.dense,
    required this.onCorrect,
    super.key,
  });

  final DictationRecord record;
  final bool dense;
  final Future<bool> Function(DictationRecord record, String value) onCorrect;

  @override
  Widget build(BuildContext context) {
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(
          TimeOfDay.fromDateTime(record.createdAt),
          alwaysUse24HourFormat: false,
        )
        .toLowerCase();
    return SizedBox(
      height: dense ? 76 : 98,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 24 : 32,
          vertical: dense ? 18 : 28,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(
                time,
                style: const TextStyle(
                  color: Color(0x996B7280),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Text(
                record.finalText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
            IconButton(
              key: Key('edit-dictation-${record.id}'),
              tooltip: 'Correct dictation',
              onPressed: () => _showCorrectionDialog(context),
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCorrectionDialog(BuildContext context) async {
    final controller = TextEditingController(text: record.finalText);
    final corrected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct dictation'),
        content: SizedBox(
          width: 520,
          child: TextField(
            key: const Key('dictation-correction-field'),
            controller: controller,
            autofocus: true,
            maxLines: 6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('save-dictation-correction'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (corrected != null) await onCorrect(record, corrected);
  }
}

final class _FeedFooter extends StatelessWidget {
  const _FeedFooter({required this.viewModel, required this.dense});

  final DictationHistoryViewModel viewModel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: dense ? 58 : 88,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SwarColors.border)),
      ),
      child: OutlinedButton(
        onPressed: viewModel.isLoadingMore ? null : viewModel.loadMore,
        style: OutlinedButton.styleFrom(
          disabledForegroundColor: SwarColors.mutedInk,
          side: const BorderSide(color: SwarColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: viewModel.isLoadingMore
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text(
                'SHOW MORE ACTIVITY',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
      ),
    );
  }
}

final class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: SwarColors.leaf, size: 30),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
