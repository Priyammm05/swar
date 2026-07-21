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
        microphoneId: '',
        language: 'automatic',
        writingMode: 'clean',
        pasteAutomatically: true,
        restoreClipboard: true,
      ),
    );

    expect(viewModel.state, DictationLifecycleState.failed);
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
        microphoneId: 'built-in',
        language: 'english',
        writingMode: 'clean',
        pasteAutomatically: true,
        restoreClipboard: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.state, DictationLifecycleState.recording);

    await viewModel.finish();
    expect(viewModel.state, DictationLifecycleState.idle);
    expect(viewModel.message, 'Dictation copied to the clipboard.');
  });

  test(
    'keeps tentative preview separate while following exact core states',
    () async {
      final gateway = _EngineGateway(
        modelReady: true,
        events: const [
          DictationEngineEvent(
            sessionId: 'session-1',
            kind: DictationEngineEventKind.partialTranscript,
            previousState: DictationLifecycleState.recording,
            currentState: DictationLifecycleState.recording,
            timestampMilliseconds: 2,
            reason: 'tentative local preview',
            partialText: 'Tentative words',
          ),
          DictationEngineEvent(
            sessionId: 'session-1',
            kind: DictationEngineEventKind.finalising,
            previousState: DictationLifecycleState.finalising,
            currentState: DictationLifecycleState.cleaning,
            timestampMilliseconds: 3,
            reason: 'final transcript ready',
          ),
        ],
      );
      final viewModel = DictationSessionViewModel(gateway: gateway);
      addTearDown(viewModel.dispose);

      await viewModel.start(
        const DictationEngineConfig(
          modelPath: '/test/model.bin',
          microphoneId: 'built-in',
          language: 'english',
          writingMode: 'clean',
          pasteAutomatically: true,
          restoreClipboard: true,
          enableLivePreview: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.partialText, 'Tentative words');
      expect(viewModel.state, DictationLifecycleState.cleaning);
      expect(viewModel.message, 'Cleaning the transcript…');
      expect(viewModel.completionRevision, 0);
    },
  );

  test('a late preview cannot drag the overlay back to recording', () async {
    // The reported failure: on release the overlay showed "understanding", then
    // jumped back to the waveform, then to "understanding" again before the text
    // appeared. A preview decode still in flight when the speaker stops lands
    // after the session has moved on, and every preview is stamped `recording`,
    // so applying its state rewound the lifecycle.
    final gateway = _EngineGateway(
      modelReady: true,
      events: const [
        DictationEngineEvent(
          sessionId: 'session-1',
          kind: DictationEngineEventKind.finalising,
          previousState: DictationLifecycleState.recording,
          currentState: DictationLifecycleState.transcribing,
          timestampMilliseconds: 1,
          reason: 'capture finished',
        ),
        DictationEngineEvent(
          sessionId: 'session-1',
          kind: DictationEngineEventKind.partialTranscript,
          previousState: DictationLifecycleState.recording,
          currentState: DictationLifecycleState.recording,
          timestampMilliseconds: 2,
          reason: 'tentative local preview',
          partialText: 'late preview',
        ),
      ],
    );
    final viewModel = DictationSessionViewModel(gateway: gateway);
    addTearDown(viewModel.dispose);

    await viewModel.start(
      const DictationEngineConfig(
        modelPath: '/test/model.bin',
        microphoneId: 'built-in',
        language: 'english',
        writingMode: 'clean',
        pasteAutomatically: true,
        restoreClipboard: true,
        enableLivePreview: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // The preview's text is still shown; only its stale state is ignored.
    expect(viewModel.partialText, 'late preview');
    expect(viewModel.state, DictationLifecycleState.transcribing);
    expect(viewModel.message, isNot('Listening…'));
  });

  test(
    'surfaces an empty local transcript as a transcription failure',
    () async {
      final gateway = _EngineGateway(
        modelReady: true,
        finishError: 'dictation_stage:transcription_empty',
      );
      final viewModel = DictationSessionViewModel(gateway: gateway);
      addTearDown(viewModel.dispose);

      await viewModel.start(
        const DictationEngineConfig(
          modelPath: '/test/model.bin',
          microphoneId: 'built-in',
          language: 'automatic',
          writingMode: 'clean',
          pasteAutomatically: true,
          restoreClipboard: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await viewModel.finish();

      expect(viewModel.state, DictationLifecycleState.failed);
      expect(viewModel.message, 'The local model did not return spoken text.');
      expect(viewModel.completionRevision, 0);
    },
  );
}

final class _EngineGateway implements DictationEngineGateway {
  _EngineGateway({required this.modelReady, this.events, this.finishError});

  final bool modelReady;
  final List<DictationEngineEvent>? events;
  final Object? finishError;
  int startCalls = 0;

  @override
  Future<void> cancel(String sessionId) async {}

  @override
  Future<bool> prepare(String modelPath) async => modelReady;

  @override
  Future<void> prepareAudio(String microphoneId) async {}

  @override
  Future<void> release() async {}

  @override
  Future<DictationEngineCompletion> finish(String sessionId) async {
    final error = finishError;
    if (error != null) throw error;
    return const DictationEngineCompletion(
      finalText: 'Hello',
      insertionStatus: 'copied',
    );
  }

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
    return Stream<DictationEngineEvent>.fromIterable(
      events ??
          const [
            DictationEngineEvent(
              sessionId: 'session-1',
              kind: DictationEngineEventKind.recording,
              previousState: DictationLifecycleState.preparing,
              currentState: DictationLifecycleState.recording,
              timestampMilliseconds: 1,
              reason: 'microphone ready',
            ),
          ],
    );
  }

  @override
  int modelDownloadPercent() => -1;
}
