// apps/swar_desktop/lib/insights/domain/insights_snapshot.dart

/// One application's share of dictations (Domain Model).
final class SwarAppUsage {
  const SwarAppUsage({required this.name, required this.count});

  final String name;
  final int count;
}

/// Locally computed insights (Domain Model). Every value is aggregated by the
/// Rust core from the on-device history — nothing here is fabricated in Dart.
final class SwarInsightsSnapshot {
  const SwarInsightsSnapshot({
    this.totalWords = 0,
    this.totalDictations = 0,
    this.totalSpeechDuration = Duration.zero,
    this.averageWordsPerMinute = 0,
    this.currentStreakDays = 0,
    this.longestStreakDays = 0,
    this.wordsCorrected = 0,
    this.dictionaryHits = 0,
    this.languageEnglish = 0,
    this.languageHindi = 0,
    this.languageHinglish = 0,
    this.appUsage = const [],
    this.distinctAppCount = 0,
    this.dailyActivity = const [],
  });

  final int totalWords;
  final int totalDictations;
  final Duration totalSpeechDuration;
  final double averageWordsPerMinute;
  final int currentStreakDays;
  final int longestStreakDays;

  final int wordsCorrected;
  final int dictionaryHits;
  final int languageEnglish;
  final int languageHindi;
  final int languageHinglish;
  final List<SwarAppUsage> appUsage;
  final int distinctAppCount;

  /// Per-day dictation counts, oldest first, ending today (for the heatmap).
  final List<int> dailyActivity;

  int get languageTotal => languageEnglish + languageHindi + languageHinglish;

  double get englishShare =>
      languageTotal == 0 ? 0 : languageEnglish / languageTotal;
  double get hindiShare =>
      languageTotal == 0 ? 0 : languageHindi / languageTotal;
  double get hinglishShare =>
      languageTotal == 0 ? 0 : languageHinglish / languageTotal;

  /// Time saved vs typing the same words at 40 wpm, minus the time actually
  /// spoken. Clamped at zero. A self-comparison, never a global ranking.
  Duration get timeSaved {
    if (totalWords == 0) return Duration.zero;
    final typingSeconds = totalWords / 40 * 60;
    final savedSeconds = typingSeconds - totalSpeechDuration.inSeconds;
    if (savedSeconds <= 0) return Duration.zero;
    return Duration(seconds: savedSeconds.round());
  }

  int get totalAppEvents => appUsage.fold(0, (sum, usage) => sum + usage.count);
}
