import 'package:flutter_test/flutter_test.dart';
import 'package:swar_desktop/settings/data/in_memory_personalization_repository.dart';
import 'package:swar_desktop/settings/presentation/personalization_view_model.dart';

void main() {
  test(
    'local vocabulary can be added, replaced, deleted, and exported',
    () async {
      final viewModel = PersonalizationViewModel(
        repository: InMemoryPersonalizationRepository(),
      );
      addTearDown(viewModel.dispose);

      await viewModel.load();
      expect(viewModel.entries, isEmpty);

      await viewModel.add('sewer', 'Swar');
      expect(viewModel.entries.single.written, 'Swar');

      await viewModel.add('SEWER', 'swar');
      expect(viewModel.entries, hasLength(1));
      expect(viewModel.entries.single.written, 'swar');

      await viewModel.export();
      expect(viewModel.message, contains('/tmp/swar-export.jsonl'));

      await viewModel.delete('sewer');
      expect(viewModel.entries, isEmpty);
    },
  );
}
