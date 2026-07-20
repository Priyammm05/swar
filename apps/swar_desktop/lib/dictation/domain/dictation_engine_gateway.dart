final class SwarMicrophone {
  const SwarMicrophone({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.isBuiltIn,
  });

  final String id;
  final String name;
  final bool isDefault;
  final bool isBuiltIn;
}

enum DictationEngineEventKind {
  stateChanged,
  preparing,
  recording,
  audioLevel,
  finalising,
  cancelled,
  failed,
  partialTranscript,
}

enum DictationLifecycleState {
  idle,
  preparing,
  recording,
  finalising,
  transcribing,
  cleaning,
  enhancing,
  inserting,
  copiedFallback,
  completed,
  cancelled,
  failed,
}

final class DictationEngineEvent {
  const DictationEngineEvent({
    required this.sessionId,
    required this.kind,
    required this.previousState,
    required this.currentState,
    required this.timestampMilliseconds,
    required this.reason,
    this.audioLevel,
    this.message,
    this.partialText,
  });

  final String sessionId;
  final DictationEngineEventKind kind;
  final DictationLifecycleState previousState;
  final DictationLifecycleState currentState;
  final int timestampMilliseconds;
  final String reason;
  final double? audioLevel;
  final String? message;
  final String? partialText;
}

final class DictationEngineConfig {
  const DictationEngineConfig({
    required this.modelPath,
    required this.microphoneId,
    required this.language,
    required this.writingMode,
    required this.pasteAutomatically,
    required this.restoreClipboard,
    this.keepModelsWarm = true,
    this.enableLivePreview = false,
    this.sourceApplication = '',
    this.enhancementProvider = 'local',
    this.providerEndpoint = '',
    this.providerModel = '',
    this.providerApiKey = '',
    this.isSensitive = false,
  });

  final String modelPath;
  final String microphoneId;
  final String language;
  final String writingMode;
  final bool pasteAutomatically;
  final bool restoreClipboard;
  final bool keepModelsWarm;
  final bool enableLivePreview;
  final String sourceApplication;
  final String enhancementProvider;
  final String providerEndpoint;
  final String providerModel;
  final String providerApiKey;

  /// True when the focused field is a password/secure field. The dictation still
  /// inserts, but nothing is persisted to history (privacy P0).
  final bool isSensitive;
}

final class DictationEngineCompletion {
  const DictationEngineCompletion({
    required this.finalText,
    required this.insertionStatus,
  });

  final String finalText;
  final String insertionStatus;
}

final class OfflineModelInstallation {
  const OfflineModelInstallation({
    required this.path,
    required this.installed,
    required this.sizeBytes,
  });

  final String path;
  final bool installed;
  final int sizeBytes;
}

abstract interface class DictationEngineGateway {
  Future<List<SwarMicrophone>> listMicrophones();

  Stream<DictationEngineEvent> start(DictationEngineConfig config);

  Future<DictationEngineCompletion> finish(String sessionId);

  Future<void> cancel(String sessionId);

  Future<bool> prepare(String modelPath);

  Future<void> prepareAudio(String microphoneId);

  Future<void> release();

  bool modelIsReady(String modelPath);

  OfflineModelInstallation recommendedModelStatus();

  Future<OfflineModelInstallation> installRecommendedModel();
}
