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
}
