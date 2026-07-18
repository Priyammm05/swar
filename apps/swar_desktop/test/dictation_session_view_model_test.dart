import 'package:flutter_test/flutter_test.dart';
import 'package:swar_desktop/dictation/domain/dictation_engine_gateway.dart';
import 'package:swar_desktop/dictation/presentation/dictation_session_view_model.dart';

void main() {
  test('stops before capture when the offline model is missing', () async {
    final gateway = _EngineGateway(modelReady: false);
    final viewModel = DictationSessionViewModel(gateway: gateway);
    addTearDown(viewModel.dispose);

    await viewModel.start(
      const DictationEngineConfig(
        modelPath: '',
        language: 'automatic',
        writingMode: 'clean',
        pasteAutomatically: true,
        restoreClipboard: true,
      ),
    );

    expect(viewModel.state, DictationSessionState.failed);
    expect(viewModel.message, contains('offline Whisper model'));
    expect(gateway.startCalls, 0);
  });

  test('records, finishes, and reports the clipboard fallback', () async {
    final gateway = _EngineGateway(modelReady: true);
    final viewModel = DictationSessionViewModel(gateway: gateway);
    addTearDown(viewModel.dispose);

    await viewModel.start(
      const DictationEngineConfig(
        modelPath: '/test/model.bin',
        language: 'english',
        writingMode: 'clean',
        pasteAutomatically: true,
        restoreClipboard: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.state, DictationSessionState.recording);

    await viewModel.finish();
    expect(viewModel.state, DictationSessionState.idle);
    expect(viewModel.message, 'Dictation copied to the clipboard.');
  });
}

final class _EngineGateway implements DictationEngineGateway {
  _EngineGateway({required this.modelReady});

  final bool modelReady;
  int startCalls = 0;

  @override
  Future<void> cancel(String sessionId) async {}

  @override
  Future<DictationEngineCompletion> finish(String sessionId) async =>
      const DictationEngineCompletion(
        finalText: 'Hello',
        insertionStatus: 'copied',
      );

  @override
  Future<List<SwarMicrophone>> listMicrophones() async => const [];

  @override
  bool modelIsReady(String modelPath) => modelReady;

  @override
  OfflineModelInstallation recommendedModelStatus() => OfflineModelInstallation(
    path: '/test/model.bin',
    installed: modelReady,
    sizeBytes: modelReady ? 142000000 : 0,
  );

  @override
  Future<OfflineModelInstallation> installRecommendedModel() async =>
      recommendedModelStatus();

  @override
  Stream<DictationEngineEvent> start(DictationEngineConfig config) {
    startCalls += 1;
    return Stream<DictationEngineEvent>.fromIterable(const [
      DictationEngineEvent(
        sessionId: 'session-1',
        kind: DictationEngineEventKind.recording,
      ),
    ]);
  }
}
