import 'package:swar_desktop/generated_bridge/api/history.dart' as native;
import 'package:swar_desktop/insights/domain/insights_repository.dart';
import 'package:swar_desktop/insights/domain/insights_snapshot.dart';

final class RustInsightsRepository implements InsightsRepository {
  @override
  Future<SwarInsightsSnapshot> loadSnapshot() async {
    final value = await native.loadInsightsSnapshot();
    return SwarInsightsSnapshot(
      totalWords: value.totalWords.toInt(),
      totalDictations: value.totalDictations.toInt(),
      totalSpeechDuration: Duration(
        milliseconds: value.totalSpeechDurationMs.toInt(),
      ),
      averageWordsPerMinute: value.averageWordsPerMinute,
      currentStreakDays: value.currentStreakDays,
      longestStreakDays: value.longestStreakDays,
      wordsCorrected: value.wordsCorrected.toInt(),
      dictionaryHits: value.dictionaryHits.toInt(),
      languageEnglish: value.languageEnglish.toInt(),
      languageHindi: value.languageHindi.toInt(),
      languageHinglish: value.languageHinglish.toInt(),
      distinctAppCount: value.distinctAppCount.toInt(),
      appUsage: value.appUsage
          .map(
            (usage) =>
                SwarAppUsage(name: usage.name, count: usage.count.toInt()),
          )
          .toList(growable: false),
      dailyActivity: value.dailyActivity.toList(growable: false),
    );
  }
}
