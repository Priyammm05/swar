import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:swar_desktop/dictation/domain/dictation_engine_gateway.dart';

final class DictationSessionViewModel extends ChangeNotifier {
  DictationSessionViewModel({required DictationEngineGateway gateway})
    : _gateway = gateway;

  final DictationEngineGateway _gateway;
  StreamSubscription<DictationEngineEvent>? _subscription;
  DictationLifecycleState _state = DictationLifecycleState.idle;
  String? _sessionId;
  String? _message;
  double _audioLevel = 0;
  bool _isInstallingModel = false;
  bool _isInstallingLanguagePack = false;
  int _completionRevision = 0;
  bool _keepModelsWarm = true;
  String? _partialText;

  DictationLifecycleState get state => _state;
  String? get message => _message;
  double get audioLevel => _audioLevel;
  bool get isRecording => _state == DictationLifecycleState.recording;
  bool get isProcessing => switch (_state) {
    DictationLifecycleState.preparing ||
    DictationLifecycleState.finalising ||
    DictationLifecycleState.transcribing ||
    DictationLifecycleState.cleaning ||
    DictationLifecycleState.enhancing ||
    DictationLifecycleState.inserting => true,
    _ => false,
  };
  bool get isInstallingModel => _isInstallingModel;
  bool get isInstallingLanguagePack => _isInstallingLanguagePack;
  int get completionRevision => _completionRevision;
  String? get partialText => _partialText;

  OfflineModelInstallation get recommendedModelStatus =>
      _gateway.recommendedModelStatus();

  OfflineModelInstallation get indicPackStatus => _gateway.indicPackStatus();

  Future<List<SwarMicrophone>> listMicrophones() => _gateway.listMicrophones();

  Future<bool> prepare(String modelPath) async {
    if (!_gateway.modelIsReady(modelPath)) return false;
    return _gateway.prepare(modelPath);
  }

  Future<void> start(DictationEngineConfig config) async {
    if (!_gateway.modelIsReady(config.modelPath)) {
      _fail('Choose an offline Whisper model before testing dictation.');
      return;
    }
    await _gateway.prepare(config.modelPath);
    await _subscription?.cancel();
    _keepModelsWarm = config.keepModelsWarm;
    _state = DictationLifecycleState.preparing;
    _message = 'Preparing the microphone…';
    notifyListeners();
    _subscription = _gateway.start(config).listen((event) {
      _sessionId = event.sessionId;
      _audioLevel = event.audioLevel ?? _audioLevel;
      if (event.partialText != null) _partialText = event.partialText;
      _state = event.currentState;
      _message = _messageForState(event.currentState, event.message);
      notifyListeners();
    }, onError: (Object error) => _fail(_friendlyError(error)));
  }

  Future<void> finish() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    _state = DictationLifecycleState.finalising;
    _message = 'Transcribing locally…';
    notifyListeners();
    try {
      final completion = await _gateway.finish(sessionId);
      _state = DictationLifecycleState.idle;
      _sessionId = null;
      _audioLevel = 0;
      _partialText = null;
      _completionRevision += 1;
      _message = completion.insertionStatus == 'inserted'
          ? 'Dictation pasted.'
          : 'Dictation copied to the clipboard.';
      if (!_keepModelsWarm) await _gateway.release();
    } catch (error) {
      _fail(_friendlyError(error));
    }
    notifyListeners();
  }

  Future<void> cancel() async {
    final sessionId = _sessionId;
    if (sessionId != null) await _gateway.cancel(sessionId);
    _reset();
    notifyListeners();
  }

  Future<String?> installRecommendedModel() async {
    if (_isInstallingModel) return null;
    _isInstallingModel = true;
    _message = 'Downloading the multilingual model…';
    notifyListeners();
    try {
      final installation = await _gateway.installRecommendedModel();
      _message = installation.installed
          ? 'Offline model ready.'
          : 'The offline model could not be installed.';
      return installation.installed ? installation.path : null;
    } catch (error) {
      _message = 'Model download failed. Check your connection and try again.';
      return null;
    } finally {
      _isInstallingModel = false;
      notifyListeners();
    }
  }

  /// Downloads the optional Indian-languages pack (~670 MB). Returns true when it
  /// is installed and ready. Until then Hindi/Hinglish/Indian speech uses the
  /// whisper fallback; English keeps using the fast Parakeet engine.
  Future<bool> installIndicModels() async {
    if (_isInstallingLanguagePack) return false;
    _isInstallingLanguagePack = true;
    _message = 'Downloading the Indian languages pack…';
    notifyListeners();
    try {
      final installation = await _gateway.installIndicModels();
      _message = installation.installed
          ? 'Indian languages ready.'
          : 'The Indian languages pack could not be installed.';
      return installation.installed;
    } catch (error) {
      _message =
          'Indian languages download failed. Check your connection and try again.';
      return false;
    } finally {
      _isInstallingLanguagePack = false;
      notifyListeners();
    }
  }

  void _reset() {
    _state = DictationLifecycleState.idle;
    _sessionId = null;
    _audioLevel = 0;
    _partialText = null;
  }

  void _fail(String message) {
    _state = DictationLifecycleState.failed;
    _message = message;
    notifyListeners();
  }

  String _friendlyError(Object error) {
    final value = error.toString();
    if (value.contains('model_not_installed')) {
      return 'Choose an offline Whisper model before testing dictation.';
    }
    if (value.toLowerCase().contains('permission')) {
      return 'Microphone access is required for dictation.';
    }
    if (value.contains('dictation_stage:capture_empty')) {
      return 'Swar did not receive microphone audio.';
    }
    if (value.contains('dictation_stage:capture')) {
      return 'Swar could not finish the microphone recording.';
    }
    if (value.contains('dictation_stage:speech_detection')) {
      return 'Swar could not detect speech in this recording.';
    }
    if (value.contains('dictation_stage:transcription_empty')) {
      return 'The local model did not return spoken text.';
    }
    if (value.contains('dictation_stage:transcription')) {
      return 'The local transcription model stopped unexpectedly.';
    }
    if (value.contains('dictation_stage:cleanup_empty')) {
      return 'Swar could not prepare the recognised text.';
    }
    if (value.contains('dictation_stage:insertion')) {
      return 'Swar recognised the speech but could not copy it.';
    }
    if (value.contains('dictation_stage:history')) {
      return 'Swar pasted the text but could not update local history.';
    }
    return 'Swar could not complete this dictation.';
  }

  String _messageForState(
    DictationLifecycleState state,
    String? failureMessage,
  ) => switch (state) {
    DictationLifecycleState.idle => 'Ready.',
    DictationLifecycleState.preparing => 'Preparing the microphone…',
    DictationLifecycleState.recording => 'Listening locally…',
    DictationLifecycleState.finalising => 'Finishing audio…',
    DictationLifecycleState.transcribing => 'Transcribing locally…',
    DictationLifecycleState.cleaning => 'Cleaning the transcript…',
    DictationLifecycleState.enhancing => 'Refining locally…',
    DictationLifecycleState.inserting => 'Pasting…',
    DictationLifecycleState.copiedFallback => 'Copied to the clipboard.',
    DictationLifecycleState.completed => 'Dictation complete.',
    DictationLifecycleState.cancelled => 'Dictation cancelled.',
    DictationLifecycleState.failed =>
      failureMessage ?? 'Dictation stopped unexpectedly.',
  };

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
