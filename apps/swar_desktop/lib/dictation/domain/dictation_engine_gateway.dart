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
  preparing,
  recording,
  audioLevel,
  finalising,
  cancelled,
  failed,
}

final class DictationEngineEvent {
  const DictationEngineEvent({
    required this.sessionId,
    required this.kind,
    this.audioLevel,
    this.message,
  });

  final String sessionId;
  final DictationEngineEventKind kind;
  final double? audioLevel;
  final String? message;
}

final class DictationEngineConfig {
  const DictationEngineConfig({
    required this.modelPath,
    required this.microphoneId,
    required this.language,
    required this.writingMode,
    required this.pasteAutomatically,
    required this.restoreClipboard,
  });

  final String modelPath;
  final String microphoneId;
  final String language;
  final String writingMode;
  final bool pasteAutomatically;
  final bool restoreClipboard;
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

  bool modelIsReady(String modelPath);

  OfflineModelInstallation recommendedModelStatus();

  Future<OfflineModelInstallation> installRecommendedModel();
}
