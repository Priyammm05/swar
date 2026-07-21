import 'package:flutter_test/flutter_test.dart';
import 'package:swar_desktop/dictation/data/fake_dictation_history_repository.dart';
import 'package:swar_desktop/dictation/presentation/dictation_history_view_model.dart';

void main() {
  test(
    'loads one bounded page and delegates search to the repository',
    () async {
      final viewModel = DictationHistoryViewModel(
        repository: FakeDictationHistoryRepository(totalRecordCount: 10000),
      );
      addTearDown(viewModel.dispose);

      await viewModel.load();
      expect(viewModel.totalCount, 10000);
      expect(viewModel.records.length, DictationHistoryViewModel.pageSize);

      await viewModel.search('launch');
      expect(viewModel.records, isNotEmpty);
      expect(
        viewModel.records.every(
          (record) => record.finalText.toLowerCase().contains('launch'),
        ),
        isTrue,
      );
    },
  );

  test('loads activity in pages of fifty and removes the more state', () async {
    final viewModel = DictationHistoryViewModel(
      repository: FakeDictationHistoryRepository(totalRecordCount: 60),
    );
    addTearDown(viewModel.dispose);

    await viewModel.load();
    expect(viewModel.records, hasLength(50));
    expect(viewModel.hasMore, isTrue);

    await viewModel.loadMore();
    expect(viewModel.records, hasLength(60));
    expect(viewModel.hasMore, isFalse);
  });

  test('shows every available row when history has fewer than fifty', () async {
    final viewModel = DictationHistoryViewModel(
      repository: FakeDictationHistoryRepository(totalRecordCount: 6),
    );
    addTearDown(viewModel.dispose);

    await viewModel.load();

    expect(viewModel.records, hasLength(6));
    expect(viewModel.totalCount, 6);
    expect(viewModel.hasMore, isFalse);
  });

  test('does not offer another page when exactly fifty rows exist', () async {
    final viewModel = DictationHistoryViewModel(
      repository: FakeDictationHistoryRepository(totalRecordCount: 50),
    );
    addTearDown(viewModel.dispose);

    await viewModel.load();

    expect(viewModel.records, hasLength(50));
    expect(viewModel.hasMore, isFalse);
  });

  test('a successful correction refreshes the visible history', () async {
    final viewModel = DictationHistoryViewModel(
      repository: FakeDictationHistoryRepository(totalRecordCount: 1),
    );
    addTearDown(viewModel.dispose);
    await viewModel.load();

    expect(
      await viewModel.correct(
        viewModel.records.single,
        'Corrected locally',
        learningOptedIn: true,
      ),
      isTrue,
    );
    expect(viewModel.records, hasLength(1));
  });

  test('each day tracks its own reveal count, newest starting larger', () {
    final viewModel = DictationHistoryViewModel(
      repository: FakeDictationHistoryRepository(totalRecordCount: 0),
    );
    addTearDown(viewModel.dispose);

    // The day at the top of the feed is the one being read.
    expect(viewModel.revealedCountFor('2026-7-22', isNewest: true), 50);
    expect(viewModel.revealedCountFor('2026-7-21', isNewest: false), 20);

    // Expanding one day must not move any other.
    viewModel.revealMoreInDay('2026-7-21', isNewest: false);
    expect(viewModel.revealedCountFor('2026-7-21', isNewest: false), 70);
    expect(viewModel.revealedCountFor('2026-7-22', isNewest: true), 50);
    expect(viewModel.revealedCountFor('2026-7-20', isNewest: false), 20);

    viewModel.revealMoreInDay('2026-7-21', isNewest: false);
    expect(viewModel.revealedCountFor('2026-7-21', isNewest: false), 120);
  });
}
