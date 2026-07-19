// apps/swar_desktop/lib/dictation/data/fake_dictation_history_repository.dart

import 'package:swar_desktop/dictation/domain/dictation_history_repository.dart';
import 'package:swar_desktop/dictation/domain/dictation_record.dart';

/// Fake Repository. Data Layer.
/// Generates rows only when the virtualized list asks for them.
final class FakeDictationHistoryRepository
    implements DictationHistoryRepository {
  FakeDictationHistoryRepository({
    this.totalRecordCount = 10000,
    DateTime? anchorTime,
  }) : _anchorTime = anchorTime ?? DateTime(2026, 7, 19, 1, 11);

  final int totalRecordCount;
  final DateTime _anchorTime;
  static const _texts = <String>[
    'Claude of Linear',
    "whatever, let's do the O again and sync again.",
    'And since right now it does not have any, if I sync, it will basically show zero, right?',
    'Please review the launch notes and tell me what still needs a decision.',
    'Move the customer call to Friday morning and keep thirty minutes free afterwards.',
    'The final version should stay direct, warm, and easy to understand.',
  ];

  static const _sources = <String>[
    'Slack',
    'Chrome',
    'Notion',
    'Mail',
    'VS Code',
    'Word',
  ];

  @override
  Future<bool> correctDictation({
    required String id,
    required String correctedText,
    required bool learningOptedIn,
  }) async => correctedText.trim().isNotEmpty;

  @override
  Future<DictationHistoryPage> loadPage(
    DictationQuery query, {
    required int offset,
    required int limit,
  }) async {
    final matchingIndexes = <int>[];
    final searchText = query.searchText.trim().toLowerCase();
    for (var index = 0; index < totalRecordCount; index++) {
      final language =
          DictationLanguage.values[index % DictationLanguage.values.length];
      if (query.language != null && language != query.language) continue;
      if (searchText.isNotEmpty &&
          !_texts[index % _texts.length].toLowerCase().contains(searchText)) {
        continue;
      }
      matchingIndexes.add(index);
    }
    final records = matchingIndexes
        .skip(offset)
        .take(limit)
        .map((sourceIndex) => _recordFor(sourceIndex, query))
        .toList(growable: false);
    return DictationHistoryPage(
      totalCount: matchingIndexes.length,
      records: records,
    );
  }

  DictationRecord _recordFor(int sourceIndex, DictationQuery query) {
    final text = _texts[sourceIndex % _texts.length];
    return DictationRecord(
      id: 'fake-dictation-$sourceIndex',
      finalText: text,
      createdAt: _anchorTime.subtract(
        Duration(
          minutes:
              (sourceIndex ~/ _texts.length) * 11 +
              const [0, 0, 2, 3, 4, 5][sourceIndex % _texts.length],
        ),
      ),
      sourceApplication: _sources[sourceIndex % _sources.length],
      language:
          query.language ??
          DictationLanguage.values[sourceIndex %
              DictationLanguage.values.length],
      writingMode: DictationWritingMode
          .values[sourceIndex % DictationWritingMode.values.length],
      wordCount: text.split(' ').length,
      duration: Duration(seconds: 4 + (sourceIndex % 24)),
    );
  }
}
