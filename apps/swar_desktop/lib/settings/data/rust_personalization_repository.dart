import 'package:swar_desktop/generated_bridge/api/personalization.dart'
    as native;
import 'package:swar_desktop/settings/domain/personalization_repository.dart';

/// Repository implementation backed by Swar's local Rust/SQLite core.
final class RustPersonalizationRepository implements PersonalizationRepository {
  @override
  Future<void> addVocabulary(String spoken, String written) async {
    native.addVocabulary(spoken: spoken, written: written);
  }

  @override
  Future<void> deleteVocabulary(String spoken) async {
    native.deleteVocabulary(spoken: spoken);
  }

  @override
  Future<String> exportLearningExamples() => native.exportLearningExamples();

  @override
  Future<List<SwarVocabularyEntry>> listVocabulary() async {
    return native
        .listVocabulary()
        .map(
          (entry) => SwarVocabularyEntry(
            spoken: entry.spoken,
            written: entry.written,
            useCount: entry.useCount,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<bool> recordEdit({
    required String original,
    required String corrected,
    required bool learningOptedIn,
  }) async {
    return native.recordUserEdit(
      original: original,
      corrected: corrected,
      learningOptedIn: learningOptedIn,
    );
  }
}
