// apps/swar_desktop/lib/dictation/presentation/dictation_page.dart

import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_colors.dart';
import 'package:swar_desktop/design_system/swar_spacing.dart';
import 'package:swar_desktop/dictation/domain/dictation_history_repository.dart';
import 'package:swar_desktop/dictation/domain/dictation_record.dart';

/// Dictation history view. Presentation Layer.
final class DictationPage extends StatefulWidget {
  const DictationPage({required this.repository, super.key});

  final DictationHistoryRepository repository;

  @override
  State<DictationPage> createState() => _DictationPageState();
}

final class _DictationPageState extends State<DictationPage> {
  DictationQuery _query = const DictationQuery();

  @override
  Widget build(BuildContext context) {
    final recordCount = widget.repository.recordCount(_query);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SwarSpacing.xl,
          SwarSpacing.xl,
          SwarSpacing.xl,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DictationHeader(
              query: _query,
              onQueryChanged: (query) => setState(() => _query = query),
            ),
            const SizedBox(height: SwarSpacing.lg),
            Expanded(
              child: recordCount == 0
                  ? _query.searchText.trim().isEmpty && _query.language == null
                        ? const _EmptyDictationState()
                        : const _NoMatchingDictationsState()
                  : _DictationList(
                      repository: widget.repository,
                      query: _query,
                      recordCount: recordCount,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _DictationHeader extends StatelessWidget {
  const _DictationHeader({required this.query, required this.onQueryChanged});

  final DictationQuery query;
  final ValueChanged<DictationQuery> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dictation',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: SwarSpacing.xs),
            Text(
              'Everything you finish with Swar, kept privately on this computer.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        );
        final controls = _HistoryControls(
          query: query,
          onQueryChanged: onQueryChanged,
        );

        if (constraints.maxWidth >= 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: title),
              const SizedBox(width: SwarSpacing.lg),
              controls,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: SwarSpacing.md),
            controls,
          ],
        );
      },
    );
  }
}

final class _HistoryControls extends StatelessWidget {
  const _HistoryControls({required this.query, required this.onQueryChanged});

  final DictationQuery query;
  final ValueChanged<DictationQuery> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: SwarSpacing.sm,
      runSpacing: SwarSpacing.sm,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
            key: const Key('dictation-search'),
            onChanged: (value) {
              onQueryChanged(query.copyWith(searchText: value));
            },
            decoration: const InputDecoration(
              hintText: 'Search dictations',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        PopupMenuButton<_LanguageFilter>(
          key: const Key('dictation-language-filter'),
          initialValue: _LanguageFilter.fromLanguage(query.language),
          onSelected: (filter) {
            onQueryChanged(
              filter.language == null
                  ? query.copyWith(clearLanguage: true)
                  : query.copyWith(language: filter.language),
            );
          },
          itemBuilder: (context) => _LanguageFilter.values
              .map(
                (filter) =>
                    PopupMenuItem(value: filter, child: Text(filter.label)),
              )
              .toList(),
          child: Chip(
            avatar: const Icon(Icons.tune_rounded, size: 17),
            label: Text(
              query.language == null
                  ? 'All languages'
                  : _LanguageFilter.fromLanguage(query.language).label,
            ),
          ),
        ),
        const Chip(
          avatar: Icon(Icons.lock_outline_rounded, size: 17),
          label: Text('Local only'),
        ),
      ],
    );
  }
}

final class _DictationList extends StatelessWidget {
  const _DictationList({
    required this.repository,
    required this.query,
    required this.recordCount,
  });

  final DictationHistoryRepository repository;
  final DictationQuery query;
  final int recordCount;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('dictation-list'),
      itemCount: recordCount,
      cacheExtent: 720,
      itemBuilder: (context, index) {
        return _DictationCard(
          key: Key('dictation-record-$index'),
          record: repository.recordAt(index, query),
        );
      },
    );
  }
}

enum _LanguageFilter {
  all(null, 'All languages'),
  english(DictationLanguage.english, 'English'),
  hindi(DictationLanguage.hindi, 'Hindi'),
  hinglish(DictationLanguage.hinglish, 'Hinglish');

  const _LanguageFilter(this.language, this.label);

  final DictationLanguage? language;
  final String label;

  static _LanguageFilter fromLanguage(DictationLanguage? language) {
    return values.firstWhere((filter) => filter.language == language);
  }
}

final class _DictationCard extends StatelessWidget {
  const _DictationCard({required this.record, super.key});

  final DictationRecord record;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SwarSpacing.sm),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(SwarSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: SwarColors.leafSoft,
                foregroundColor: SwarColors.leaf,
                child: Icon(Icons.text_snippet_outlined, size: 18),
              ),
              const SizedBox(width: SwarSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.finalText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: SwarSpacing.sm),
                    Wrap(
                      spacing: SwarSpacing.md,
                      runSpacing: SwarSpacing.xs,
                      children: [
                        _Metadata(label: record.sourceApplication),
                        _Metadata(label: _languageLabel(record.language)),
                        _Metadata(label: _modeLabel(record.writingMode)),
                        _Metadata(label: '${record.wordCount} words'),
                        _Metadata(label: '${record.duration.inSeconds}s'),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy dictation',
                onPressed: null,
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _languageLabel(DictationLanguage language) => switch (language) {
    DictationLanguage.english => 'English',
    DictationLanguage.hindi => 'Hindi',
    DictationLanguage.hinglish => 'Hinglish',
  };

  String _modeLabel(DictationWritingMode mode) => switch (mode) {
    DictationWritingMode.raw => 'Raw',
    DictationWritingMode.clean => 'Clean',
    DictationWritingMode.intent => 'Intent',
  };
}

final class _Metadata extends StatelessWidget {
  const _Metadata({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.bodyMedium);
  }
}

final class _EmptyDictationState extends StatelessWidget {
  const _EmptyDictationState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(SwarSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.mic_none_rounded,
                  size: 36,
                  color: SwarColors.leaf,
                ),
                const SizedBox(height: SwarSpacing.md),
                Text(
                  'Your dictations will appear here',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: SwarSpacing.sm),
                Text(
                  'Speak anywhere with Swar. Your finished words will be saved privately on this computer.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _NoMatchingDictationsState extends StatelessWidget {
  const _NoMatchingDictationsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 34,
              color: SwarColors.leaf,
            ),
            const SizedBox(height: SwarSpacing.md),
            Text(
              'No matching dictations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: SwarSpacing.sm),
            Text(
              'Try another word or choose a different language.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
