import 'package:swar_desktop/settings/domain/personalization_repository.dart';

final class InMemoryPersonalizationRepository
    implements PersonalizationRepository {
  final List<SwarVocabularyEntry> _entries = [];

  @override
  Future<void> addVocabulary(String spoken, String written) async {
    _entries.removeWhere(
      (entry) => entry.spoken.toLowerCase() == spoken.toLowerCase(),
    );
    _entries.add(
      SwarVocabularyEntry(spoken: spoken, written: written, useCount: 1),
    );
  }

  @override
  Future<void> deleteVocabulary(String spoken) async {
    _entries.removeWhere(
      (entry) => entry.spoken.toLowerCase() == spoken.toLowerCase(),
    );
  }

  @override
  Future<String> exportLearningExamples() async => '/tmp/swar-export.jsonl';

  @override
  Future<List<SwarVocabularyEntry>> listVocabulary() async =>
      List.unmodifiable(_entries);

  @override
  Future<bool> recordEdit({
    required String original,
    required String corrected,
    required bool learningOptedIn,
  }) async => learningOptedIn && original.trim() != corrected.trim();
}
