/// Domain model for one local pronunciation or spelling preference.
final class SwarVocabularyEntry {
  const SwarVocabularyEntry({
    required this.spoken,
    required this.written,
    required this.useCount,
  });

  final String spoken;
  final String written;
  final int useCount;
}

abstract interface class PersonalizationRepository {
  Future<List<SwarVocabularyEntry>> listVocabulary();

  Future<void> addVocabulary(String spoken, String written);

  Future<void> deleteVocabulary(String spoken);

  Future<bool> recordEdit({
    required String original,
    required String corrected,
    required bool learningOptedIn,
  });

  Future<String> exportLearningExamples();
}
