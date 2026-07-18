// apps/swar_desktop/lib/dictation/domain/dictation_history_repository.dart

import 'package:swar_desktop/dictation/domain/dictation_record.dart';

/// The filters sent to the history data source.
final class DictationQuery {
  const DictationQuery({this.searchText = '', this.language});

  final String searchText;
  final DictationLanguage? language;

  DictationQuery copyWith({
    String? searchText,
    DictationLanguage? language,
    bool clearLanguage = false,
  }) {
    return DictationQuery(
      searchText: searchText ?? this.searchText,
      language: clearLanguage ? null : language ?? this.language,
    );
  }
}

/// Repository Contract. Domain Layer.
/// Phase 2 will implement this contract through paginated Rust and SQLite APIs.
abstract interface class DictationHistoryRepository {
  Future<DictationHistoryPage> loadPage(
    DictationQuery query, {
    required int offset,
    required int limit,
  });
}

final class DictationHistoryPage {
  const DictationHistoryPage({required this.totalCount, required this.records});

  final int totalCount;
  final List<DictationRecord> records;
}
