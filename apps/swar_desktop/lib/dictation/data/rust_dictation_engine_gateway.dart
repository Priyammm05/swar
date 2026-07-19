import 'package:swar_desktop/dictation/domain/dictation_engine_gateway.dart';
import 'package:swar_desktop/generated_bridge/api/dictation.dart' as native;
import 'package:swar_desktop/generated_bridge/api/models.dart' as models;

final class RustDictationEngineGateway implements DictationEngineGateway {
  @override
  Future<List<SwarMicrophone>> listMicrophones() async {
    final devices = await native.listMicrophones();
    return devices
        .map(
          (device) => SwarMicrophone(
            id: device.id,
            name: device.name,
            isDefault: device.isDefault,
            isBuiltIn: device.isBuiltIn,
          ),
        )
        .toList(growable: false);
  }

  @override
  Stream<DictationEngineEvent> start(DictationEngineConfig config) {
    return native
        .startDictationSession(
          config: native.DictationSessionConfig(
            modelPath: config.modelPath,
            microphoneId: config.microphoneId,
            language: config.language,
            writingMode: config.writingMode,
            sourceApplication: config.sourceApplication,
            pasteAutomatically: config.pasteAutomatically,
            restoreClipboard: config.restoreClipboard,
            maximumSeconds: 300,
            enableLivePreview: config.enableLivePreview,
            enhancementProvider: config.enhancementProvider,
            providerEndpoint: config.providerEndpoint,
            providerModel: config.providerModel,
            providerApiKey: config.providerApiKey,
          ),
        )
        .map(
          (event) => DictationEngineEvent(
            sessionId: event.sessionId,
            kind: DictationEngineEventKind.values.byName(event.kind.name),
            previousState: DictationLifecycleState.values.byName(
              event.previousState.name,
            ),
            currentState: DictationLifecycleState.values.byName(
              event.currentState.name,
            ),
            timestampMilliseconds: event.timestampMs.toInt(),
            reason: event.reason,
            audioLevel: event.audioLevel,
            message: event.message,
            partialText: event.partialText,
          ),
        );
  }

  @override
  Future<DictationEngineCompletion> finish(String sessionId) async {
    final result = await native.finishDictationSession(sessionId: sessionId);
    return DictationEngineCompletion(
      finalText: result.finalText,
      insertionStatus: result.insertionStatus,
    );
  }

  @override
  Future<void> cancel(String sessionId) =>
      native.cancelDictationSession(sessionId: sessionId);

  @override
  Future<bool> prepare(String modelPath) =>
      native.prepareDictationEngine(modelPath: modelPath);

  @override
  Future<void> prepareAudio(String microphoneId) async {
    await native.prepareAudioCapture(microphoneId: microphoneId);
  }

  @override
  Future<void> release() => native.releaseDictationEngine();

  @override
  bool modelIsReady(String modelPath) =>
      native.offlineModelIsReady(modelPath: modelPath);

  @override
  OfflineModelInstallation recommendedModelStatus() {
    final status = models.recommendedModelStatus();
    return _modelInstallation(status);
  }

  @override
  Future<OfflineModelInstallation> installRecommendedModel() async {
    return _modelInstallation(await models.installRecommendedModel());
  }

  OfflineModelInstallation _modelInstallation(
    models.OfflineModelStatus status,
  ) {
    return OfflineModelInstallation(
      path: status.path,
      installed: status.installed,
      sizeBytes: status.sizeBytes.toInt(),
    );
  }
}
