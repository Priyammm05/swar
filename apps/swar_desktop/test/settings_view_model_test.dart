import 'package:flutter_test/flutter_test.dart';
import 'package:swar_desktop/settings/data/in_memory_settings_repository.dart';
import 'package:swar_desktop/settings/domain/swar_settings.dart';
import 'package:swar_desktop/settings/presentation/settings_view_model.dart';

void main() {
  test(
    'provider secret stays in memory and never enters persisted settings',
    () {
      final repository = InMemorySettingsRepository();
      final viewModel = SettingsViewModel(repository: repository);
      addTearDown(viewModel.dispose);

      viewModel
        ..setEnhancementProvider(SwarEnhancementProvider.byok)
        ..setProviderEndpoint('https://provider.example/v1')
        ..setProviderModel('cleanup-model')
        ..setProviderApiKey('secret-session-key');

      expect(viewModel.providerApiKey, 'secret-session-key');
      expect(
        repository.read().enhancementProvider,
        SwarEnhancementProvider.byok,
      );
      expect(repository.read().providerEndpoint, 'https://provider.example/v1');
      expect(repository.read().providerModel, 'cleanup-model');
      expect(
        repository.read().toString(),
        isNot(contains('secret-session-key')),
      );
    },
  );
}
