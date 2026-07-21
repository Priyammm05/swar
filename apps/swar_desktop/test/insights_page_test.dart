import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swar_desktop/design_system/swar_theme.dart';
import 'package:swar_desktop/dictation/domain/dictation_completion_signal.dart';
import 'package:swar_desktop/insights/domain/insights_repository.dart';
import 'package:swar_desktop/insights/domain/insights_snapshot.dart';
import 'package:swar_desktop/insights/presentation/insights_page.dart';

void main() {
  /// The reported failure: Insights never changed while the app was open. The
  /// shell holds all three pages in an indexed stack, so the page loaded once
  /// at launch and its `initState` never ran again, however many dictations
  /// landed afterwards.
  testWidgets('recounts when a dictation finishes', (tester) async {
    final repository = _Repository();
    final completions = _Completions();
    addTearDown(completions.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: SwarTheme.light(),
        home: Scaffold(
          body: InsightsPage(
            repository: repository,
            completionSignal: completions,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.loads, 1);

    // Noise from an ordinary recording: levels and state changes notify too,
    // and must not each trigger a database read.
    completions.notifyWithoutCompleting();
    await tester.pumpAndSettle();
    expect(repository.loads, 1);

    completions.complete();
    await tester.pumpAndSettle();
    expect(repository.loads, 2);
  });
}

final class _Repository implements InsightsRepository {
  int loads = 0;

  @override
  Future<SwarInsightsSnapshot> loadSnapshot() async {
    loads += 1;
    return SwarInsightsSnapshot(totalDictations: loads);
  }
}

final class _Completions extends ChangeNotifier
    implements DictationCompletionSignal {
  int _revision = 0;

  @override
  int get completionRevision => _revision;

  void complete() {
    _revision += 1;
    notifyListeners();
  }

  void notifyWithoutCompleting() => notifyListeners();
}
