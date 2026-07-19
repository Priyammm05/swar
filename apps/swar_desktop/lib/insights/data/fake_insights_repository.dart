import 'package:swar_desktop/insights/domain/insights_repository.dart';
import 'package:swar_desktop/insights/domain/insights_snapshot.dart';

final class FakeInsightsRepository implements InsightsRepository {
  FakeInsightsRepository({SwarInsightsSnapshot? snapshot})
    : snapshot = snapshot ?? _sample();

  final SwarInsightsSnapshot snapshot;

  @override
  Future<SwarInsightsSnapshot> loadSnapshot() async => snapshot;

  static SwarInsightsSnapshot _sample() {
    return SwarInsightsSnapshot(
      totalWords: 6555,
      totalDictations: 91,
      totalSpeechDuration: const Duration(minutes: 43),
      averageWordsPerMinute: 150,
      currentStreakDays: 3,
      longestStreakDays: 3,
      wordsCorrected: 724,
      dictionaryHits: 312,
      languageEnglish: 54,
      languageHindi: 29,
      languageHinglish: 17,
      distinctAppCount: 8,
      appUsage: const [
        SwarAppUsage(name: 'Code', count: 78),
        SwarAppUsage(name: 'Slack', count: 15),
        SwarAppUsage(name: 'Mail', count: 7),
      ],
      dailyActivity: List<int>.generate(
        140,
        (i) => i >= 137 ? 3 : (i % 7 == 0 ? 1 : (i % 13 == 0 ? 2 : 0)),
      ),
    );
  }
}
