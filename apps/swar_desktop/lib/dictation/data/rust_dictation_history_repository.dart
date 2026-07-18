import 'package:swar_desktop/dictation/domain/dictation_history_repository.dart';
import 'package:swar_desktop/dictation/domain/dictation_record.dart';
import 'package:swar_desktop/generated_bridge/api/history.dart' as native;

final class RustDictationHistoryRepository
    implements DictationHistoryRepository {
  @override
  Future<DictationHistoryPage> loadPage(
    DictationQuery query, {
    required int offset,
    required int limit,
  }) async {
    final page = await native.loadHistoryPage(
      searchText: query.searchText,
      offset: offset,
      limit: limit,
    );
    final records = page.records
        .where((record) {
          final language = _language(record.language);
          return query.language == null || query.language == language;
        })
        .map(
          (record) => DictationRecord(
            id: record.id,
            finalText: record.finalText,
            createdAt: DateTime.fromMillisecondsSinceEpoch(record.createdAtMs),
            sourceApplication: record.sourceApplication,
            language: _language(record.language),
            writingMode: _writingMode(record.writingMode),
            wordCount: record.wordCount,
            duration: Duration(milliseconds: record.audioDurationMs.toInt()),
          ),
        )
        .toList(growable: false);
    return DictationHistoryPage(totalCount: page.totalCount, records: records);
  }

  DictationLanguage _language(String value) => switch (value.toLowerCase()) {
    'hindi' => DictationLanguage.hindi,
    'hinglish' => DictationLanguage.hinglish,
    _ => DictationLanguage.english,
  };

  DictationWritingMode _writingMode(String value) =>
      switch (value.toLowerCase()) {
        'raw' => DictationWritingMode.raw,
        'intent' => DictationWritingMode.intent,
        _ => DictationWritingMode.clean,
      };
}
