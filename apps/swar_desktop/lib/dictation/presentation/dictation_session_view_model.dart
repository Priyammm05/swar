import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:swar_desktop/dictation/domain/dictation_engine_gateway.dart';

enum DictationSessionState { idle, preparing, recording, finalising, failed }

final class DictationSessionViewModel extends ChangeNotifier {
  DictationSessionViewModel({required DictationEngineGateway gateway})
    : _gateway = gateway;

  final DictationEngineGateway _gateway;
  StreamSubscription<DictationEngineEvent>? _subscription;
  DictationSessionState _state = DictationSessionState.idle;
  String? _sessionId;
  String? _message;
  double _audioLevel = 0;
  bool _isInstallingModel = false;

  DictationSessionState get state => _state;
  String? get message => _message;
  double get audioLevel => _audioLevel;
  bool get isRecording => _state == DictationSessionState.recording;
  bool get isInstallingModel => _isInstallingModel;

  OfflineModelInstallation get recommendedModelStatus =>
      _gateway.recommendedModelStatus();

  Future<List<SwarMicrophone>> listMicrophones() => _gateway.listMicrophones();

  Future<void> start(DictationEngineConfig config) async {
    if (!_gateway.modelIsReady(config.modelPath)) {
      _fail('Choose an offline Whisper model before testing dictation.');
      return;
    }
    await _subscription?.cancel();
    _state = DictationSessionState.preparing;
    _message = 'Preparing the microphone…';
    notifyListeners();
    _subscription = _gateway.start(config).listen((event) {
      _sessionId = event.sessionId;
      _audioLevel = event.audioLevel ?? _audioLevel;
      switch (event.kind) {
        case DictationEngineEventKind.preparing:
          _state = DictationSessionState.preparing;
        case DictationEngineEventKind.recording:
        case DictationEngineEventKind.audioLevel:
          _state = DictationSessionState.recording;
          _message = 'Listening locally…';
        case DictationEngineEventKind.finalising:
          _state = DictationSessionState.finalising;
          _message = 'Transcribing locally…';
        case DictationEngineEventKind.cancelled:
          _reset();
        case DictationEngineEventKind.failed:
          _fail(event.message ?? 'Dictation stopped unexpectedly.');
      }
      notifyListeners();
    }, onError: (Object error) => _fail(_friendlyError(error)));
  }

  Future<void> finish() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    _state = DictationSessionState.finalising;
    _message = 'Transcribing locally…';
    notifyListeners();
    try {
      final completion = await _gateway.finish(sessionId);
      _state = DictationSessionState.idle;
      _message = completion.insertionStatus == 'pasted'
          ? 'Dictation pasted.'
          : 'Dictation copied to the clipboard.';
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

  void _reset() {
    _state = DictationSessionState.idle;
    _sessionId = null;
    _audioLevel = 0;
  }

  void _fail(String message) {
    _state = DictationSessionState.failed;
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
    return 'Swar could not complete this dictation.';
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
