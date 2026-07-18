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
  int recordCount(DictationQuery query);

  DictationRecord recordAt(int index, DictationQuery query);
}
