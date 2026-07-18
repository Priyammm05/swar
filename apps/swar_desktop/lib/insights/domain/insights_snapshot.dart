final class SwarInsightsSnapshot {
  const SwarInsightsSnapshot({
    this.totalWords = 0,
    this.totalDictations = 0,
    this.totalSpeechDuration = Duration.zero,
    this.averageWordsPerMinute = 0,
    this.currentStreakDays = 0,
    this.longestStreakDays = 0,
  });

  final int totalWords;
  final int totalDictations;
  final Duration totalSpeechDuration;
  final double averageWordsPerMinute;
  final int currentStreakDays;
  final int longestStreakDays;
}
