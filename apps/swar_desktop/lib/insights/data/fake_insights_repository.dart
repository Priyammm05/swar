import 'package:swar_desktop/insights/domain/insights_repository.dart';
import 'package:swar_desktop/insights/domain/insights_snapshot.dart';

final class FakeInsightsRepository implements InsightsRepository {
  const FakeInsightsRepository({
    this.snapshot = const SwarInsightsSnapshot(
      totalWords: 6555,
      totalDictations: 8,
      totalSpeechDuration: Duration(minutes: 44),
      averageWordsPerMinute: 150,
      currentStreakDays: 3,
      longestStreakDays: 3,
    ),
  });

  final SwarInsightsSnapshot snapshot;

  @override
  Future<SwarInsightsSnapshot> loadSnapshot() async => snapshot;
}
