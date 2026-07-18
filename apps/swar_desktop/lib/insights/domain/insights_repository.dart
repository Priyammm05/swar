import 'package:swar_desktop/insights/domain/insights_snapshot.dart';

abstract interface class InsightsRepository {
  Future<SwarInsightsSnapshot> loadSnapshot();
}
