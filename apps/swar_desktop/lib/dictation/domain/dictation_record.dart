// apps/swar_desktop/lib/dictation/domain/dictation_record.dart

enum DictationLanguage { english, hindi, hinglish }

enum DictationWritingMode { raw, clean, intent }

/// Domain Model.
/// A lightweight projection of one locally stored dictation.
final class DictationRecord {
  const DictationRecord({
    required this.id,
    required this.finalText,
    required this.createdAt,
    required this.sourceApplication,
    required this.language,
    required this.writingMode,
    required this.wordCount,
    required this.duration,
  });

  final String id;
  final String finalText;
  final DateTime createdAt;
  final String sourceApplication;
  final DictationLanguage language;
  final DictationWritingMode writingMode;
  final int wordCount;
  final Duration duration;
}
