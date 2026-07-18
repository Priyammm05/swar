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
  }) : _anchorTime = anchorTime ?? DateTime.now();

  final int totalRecordCount;
  final DateTime _anchorTime;
  String? _cachedSearchText;
  DictationLanguage? _cachedLanguage;
  List<int>? _cachedSourceIndexes;

  static const _texts = <String>[
    'Please review the launch notes and tell me what still needs a decision.',
    'Kal design review ke baad updated flow team ke saath share kar dena.',
    'Move the customer call to Friday morning and keep thirty minutes free afterwards.',
    'The final version should stay direct, warm, and easy to understand.',
    'Niyo wale integration ke numbers check karke summary bhej dena.',
    'Add the accessibility findings to the release checklist before we ship.',
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
  int recordCount(DictationQuery query) {
    if (query.searchText.trim().isNotEmpty) {
      return _matchingSourceIndexes(query).length;
    }
    if (query.language != null) {
      final firstIndex = query.language!.index;
      if (totalRecordCount <= firstIndex) {
        return 0;
      }
      return ((totalRecordCount - 1 - firstIndex) ~/
              DictationLanguage.values.length) +
          1;
    }
    return totalRecordCount;
  }

  @override
  DictationRecord recordAt(int index, DictationQuery query) {
    final visibleCount = recordCount(query);
    if (index < 0 || index >= visibleCount) {
      throw RangeError.index(index, this, 'index', null, visibleCount);
    }

    final sourceIndex = query.searchText.trim().isNotEmpty
        ? _matchingSourceIndexes(query)[index]
        : query.language == null
        ? index
        : index * DictationLanguage.values.length + query.language!.index;
    final text = _texts[sourceIndex % _texts.length];
    return DictationRecord(
      id: 'fake-dictation-$sourceIndex',
      finalText: text,
      createdAt: _anchorTime.subtract(Duration(minutes: sourceIndex * 11)),
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

  List<int> _matchingSourceIndexes(DictationQuery query) {
    final searchText = query.searchText.trim().toLowerCase();
    if (_cachedSearchText == searchText &&
        _cachedLanguage == query.language &&
        _cachedSourceIndexes != null) {
      return _cachedSourceIndexes!;
    }

    final matches = <int>[];
    for (var index = 0; index < totalRecordCount; index++) {
      final language =
          DictationLanguage.values[index % DictationLanguage.values.length];
      if (query.language != null && language != query.language) {
        continue;
      }
      if (_texts[index % _texts.length].toLowerCase().contains(searchText)) {
        matches.add(index);
      }
    }

    _cachedSearchText = searchText;
    _cachedLanguage = query.language;
    _cachedSourceIndexes = matches;
    return matches;
  }
}
