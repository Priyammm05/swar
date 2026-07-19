// apps/swar_desktop/lib/dictation/domain/dictation_record.dart

enum DictationLanguage { automatic, english, hindi, hinglish }

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
    this.insertionStatus = '',
  });

  final String id;
  final String finalText;
  final DateTime createdAt;
  final String sourceApplication;

  /// The dictation *mode* at capture time (often "automatic").
  final DictationLanguage language;
  final DictationWritingMode writingMode;
  final int wordCount;
  final Duration duration;

  /// How the text reached the target field: inserted, or copied to the
  /// clipboard as a fallback when insertion failed.
  final String insertionStatus;

  /// True when insertion fell back to the clipboard.
  bool get wasCopiedFallback {
    final status = insertionStatus.toLowerCase();
    return status.contains('copi') ||
        status.contains('clipboard') ||
        status.contains('fallback');
  }

  /// Language inferred from the transcript's script (Devanagari vs Latin), so a
  /// badge reflects what was actually spoken rather than the capture mode. Mixed
  /// scripts read as Hinglish; romanized Hindi with no Devanagari reads English.
  DictationLanguage get detectedLanguage {
    var devanagari = 0;
    var latin = 0;
    for (final rune in finalText.runes) {
      if (rune >= 0x0900 && rune <= 0x097F) {
        devanagari++;
      } else if ((rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A)) {
        latin++;
      }
    }
    if (devanagari == 0) return DictationLanguage.english;
    if (latin == 0) return DictationLanguage.hindi;
    return DictationLanguage.hinglish;
  }
}
