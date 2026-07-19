// apps/swar_desktop/lib/dictation/presentation/dictation_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swar_desktop/design_system/swar_components.dart';
import 'package:swar_desktop/design_system/swar_tokens.dart';
import 'package:swar_desktop/design_system/swar_typography.dart';
import 'package:swar_desktop/dictation/domain/dictation_history_repository.dart';
import 'package:swar_desktop/dictation/domain/dictation_record.dart';
import 'package:swar_desktop/dictation/presentation/dictation_history_view_model.dart';
import 'package:swar_desktop/dictation/presentation/dictation_session_view_model.dart';
import 'package:swar_desktop/settings/presentation/settings_view_model.dart';

/// Activity — the local dictation history (spec §6). Presentation Layer.
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
      builder: (context, _) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1008),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 48),
            children: [
              _Greeting(total: _viewModel.totalCount),
              const SizedBox(height: 18),
              _Toolbar(viewModel: _viewModel),
              const SizedBox(height: 16),
              _Feed(
                viewModel: _viewModel,
                learningOptedIn:
                    widget.settingsViewModel.settings.learnFromEdits,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Greeting extends StatelessWidget {
  const _Greeting({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Welcome back', style: SwarType.greeting.copyWith(color: t.ink)),
        const SizedBox(height: 4),
        Text(
          '$total ${total == 1 ? 'dictation' : 'dictations'}, all on this device.',
          style: SwarType.description.copyWith(color: t.inkMuted),
        ),
      ],
    );
  }
}

final class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.viewModel});

  final DictationHistoryViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Text(
          'TODAY',
          style: SwarType.uppercaseLabel.copyWith(
            color: t.inkSecondary,
            letterSpacing: 0.72,
          ),
        ),
        const SizedBox(width: 10),
        SwarCountPill(
          label:
              '${viewModel.totalCount} '
              '${viewModel.totalCount == 1 ? 'entry' : 'entries'}',
        ),
        const SizedBox(width: 14),
        Expanded(child: _SearchField(viewModel: viewModel)),
        const SizedBox(width: 14),
        SwarIconButton(
          icon: Icons.tune_rounded,
          iconSize: 17,
          size: 38,
          round: true,
          semanticLabel: 'Filter',
          onPressed: () {},
        ),
      ],
    );
  }
}

final class _SearchField extends StatelessWidget {
  const _SearchField({required this.viewModel});

  final DictationHistoryViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      height: 38,
      child: TextField(
        key: const Key('dictation-search'),
        onChanged: viewModel.search,
        style: SwarType.searchInput.copyWith(color: t.ink),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search transcripts',
          hintStyle: SwarType.searchInput.copyWith(color: t.inkMuted),
          prefixIcon: Icon(Icons.search_rounded, size: 16, color: t.inkMuted),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          filled: true,
          fillColor: t.surfaceSunken,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: _border(t.border),
          enabledBorder: _border(t.border),
          focusedBorder: _border(t.spruceBorder),
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(SwarRadii.pill),
    borderSide: BorderSide(color: color, width: 0.5),
  );
}

final class _Feed extends StatelessWidget {
  const _Feed({required this.viewModel, required this.learningOptedIn});

  final DictationHistoryViewModel viewModel;
  final bool learningOptedIn;

  @override
  Widget build(BuildContext context) {
    if (viewModel.isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(child: CircularProgressIndicator()),
      );
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

    final groups = _groupByDay(viewModel.records);
    final sections = <Widget>[];
    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      if (g > 0) {
        sections.add(
          _SectionLabel(label: group.label, count: group.entries.length),
        );
      }
      sections.add(
        _DayCard(
          isFirst: g == 0,
          entries: group.entries,
          learningOptedIn: learningOptedIn,
          // Pagination is global; the control lives inside the first (Today) card.
          showMore: g == 0 && viewModel.hasMore,
          remaining: viewModel.totalCount - viewModel.records.length,
          loadingMore: viewModel.isLoadingMore,
          onLoadMore: viewModel.loadMore,
          onCorrect: (record, value) => viewModel.correct(
            record,
            value,
            learningOptedIn: learningOptedIn,
          ),
        ),
      );
    }

    // The whole feed is one keyed list so widget tests can target it.
    return KeyedSubtree(
      key: const Key('dictation-list'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: sections,
      ),
    );
  }
}

@immutable
final class _DayGroup {
  const _DayGroup({required this.label, required this.entries});
  final String label;
  final List<_IndexedRecord> entries;
}

@immutable
final class _IndexedRecord {
  const _IndexedRecord(this.index, this.record);
  final int index;
  final DictationRecord record;
}

List<_DayGroup> _groupByDay(List<DictationRecord> records) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final groups = <String, List<_IndexedRecord>>{};
  final order = <String>[];
  for (var i = 0; i < records.length; i++) {
    final record = records[i];
    final created = record.createdAt.toLocal();
    final day = DateTime(created.year, created.month, created.day);
    final diff = today.difference(day).inDays;
    final label = switch (diff) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => _formatDay(day),
    };
    (groups[label] ??= (
      order..add(label),
      <_IndexedRecord>[],
    ).$2).add(_IndexedRecord(i, record));
  }
  return [
    for (final label in order) _DayGroup(label: label, entries: groups[label]!),
  ];
}

String _formatDay(DateTime day) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[day.month - 1]} ${day.day}';
}

final class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 2, 12),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: SwarType.uppercaseLabel.copyWith(
              color: t.inkSecondary,
              letterSpacing: 0.72,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$count ${count == 1 ? 'entry' : 'entries'}',
            style: SwarType.caption.copyWith(color: t.inkMuted),
          ),
        ],
      ),
    );
  }
}

final class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.isFirst,
    required this.entries,
    required this.learningOptedIn,
    required this.showMore,
    required this.remaining,
    required this.loadingMore,
    required this.onLoadMore,
    required this.onCorrect,
  });

  final bool isFirst;
  final List<_IndexedRecord> entries;
  final bool learningOptedIn;
  final bool showMore;
  final int remaining;
  final bool loadingMore;
  final VoidCallback onLoadMore;
  final Future<bool> Function(DictationRecord record, String value) onCorrect;

  @override
  Widget build(BuildContext context) {
    return SwarCard(
      radius: SwarRadii.cardLarge,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            _EntryRow(
              key: Key('dictation-record-${entries[i].index}'),
              record: entries[i].record,
              onCorrect: onCorrect,
            ),
            if (i != entries.length - 1) const SwarInsetDivider(),
          ],
          if (showMore)
            _ShowMore(
              remaining: remaining,
              loading: loadingMore,
              onPressed: onLoadMore,
            ),
        ],
      ),
    );
  }
}

final class _ShowMore extends StatelessWidget {
  const _ShowMore({
    required this.remaining,
    required this.loading,
    required this.onPressed,
  });

  final int remaining;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      children: [
        Container(height: 0.5, color: t.border),
        InkWell(
          key: const Key('dictation-show-more'),
          onTap: loading ? null : onPressed,
          child: SizedBox(
            height: 36,
            child: Center(
              child: loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Show $remaining more from today',
                          style: SwarType.nav.copyWith(color: t.inkSecondary),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 15,
                          color: t.inkSecondary,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _EntryRow extends StatefulWidget {
  const _EntryRow({required this.record, required this.onCorrect, super.key});

  final DictationRecord record;
  final Future<bool> Function(DictationRecord record, String value) onCorrect;

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

final class _EntryRowState extends State<_EntryRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final record = widget.record;
    final time = TimeOfDay.fromDateTime(record.createdAt.toLocal());
    final label = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(time, alwaysUse24HourFormat: false).toLowerCase();

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _hover ? t.surfaceSunken : t.surfaceCard,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 62,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  label,
                  style: SwarType.timestamp.copyWith(color: t.inkMuted),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                record.finalText,
                style: SwarType.body.copyWith(color: t.ink),
              ),
            ),
            const SizedBox(width: 12),
            // Badge and actions occupy the same slot; hover crossfades them.
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Stack(
                alignment: Alignment.centerRight,
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: _hover ? 0 : 1,
                    child: _RowBadge(record: record),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: _hover ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !_hover,
                      child: _RowActions(
                        text: record.finalText,
                        onEdit: () => _showCorrectionDialog(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCorrectionDialog(BuildContext context) async {
    final controller = TextEditingController(text: widget.record.finalText);
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
    if (corrected != null) await widget.onCorrect(widget.record, corrected);
  }
}

final class _RowActions extends StatelessWidget {
  const _RowActions({required this.text, required this.onEdit});

  final String text;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwarIconButton(
          icon: Icons.content_copy_rounded,
          semanticLabel: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: text)),
        ),
        const SizedBox(width: 2),
        SwarIconButton(
          icon: Icons.keyboard_return_rounded,
          semanticLabel: 'Reinsert',
          onPressed: () => Clipboard.setData(ClipboardData(text: text)),
        ),
        const SizedBox(width: 2),
        SwarIconButton(
          icon: Icons.more_horiz_rounded,
          semanticLabel: 'More',
          onPressed: onEdit,
        ),
      ],
    );
  }
}

/// The at-rest badge for a row: a "copied" status when insertion fell back to
/// the clipboard, otherwise the detected-language chip (§6.4).
final class _RowBadge extends StatelessWidget {
  const _RowBadge({required this.record});

  final DictationRecord record;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (record.wasCopiedFallback) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: t.saffronTint,
          borderRadius: BorderRadius.circular(SwarRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.assignment_turned_in_outlined,
              size: 12,
              color: t.saffronInk,
            ),
            const SizedBox(width: 4),
            Text('copied', style: SwarType.badge.copyWith(color: t.saffronInk)),
          ],
        ),
      );
    }
    final (label, fg, bg) = switch (record.detectedLanguage) {
      DictationLanguage.hinglish => ('HI+EN', t.mixInk, t.mixTint),
      DictationLanguage.hindi => ('HI', t.mixInk, t.mixTint),
      _ => ('EN', t.spruce, t.spruceTint),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SwarRadii.pill),
      ),
      child: Text(label, style: SwarType.badge.copyWith(color: fg)),
    );
  }
}

final class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 72),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: t.spruce, size: 30),
            const SizedBox(height: 12),
            Text(title, style: SwarType.rowTitle.copyWith(color: t.ink)),
          ],
        ),
      ),
    );
  }
}
