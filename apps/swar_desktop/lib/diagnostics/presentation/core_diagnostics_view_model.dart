// apps/swar_desktop/lib/diagnostics/presentation/core_diagnostics_view_model.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/diagnostics/presentation/core_diagnostics_state.dart';

/// Coordinates the diagnostics proof. Presentation Layer.
final class CoreDiagnosticsViewModel extends ChangeNotifier {
  CoreDiagnosticsViewModel({required CoreDiagnosticsGateway gateway})
    : _gateway = gateway;

  final CoreDiagnosticsGateway _gateway;
  StreamSubscription<int>? _eventSubscription;
  CoreDiagnosticsState _state = const CoreDiagnosticsState();
  var _operationGeneration = 0;
  var _isDisposed = false;

  CoreDiagnosticsState get state => _state;

  Future<void> checkCore() async {
    final operationGeneration = ++_operationGeneration;
    await _eventSubscription?.cancel();
    if (!_isCurrent(operationGeneration)) {
      return;
    }

    _eventSubscription = null;
    _state = const CoreDiagnosticsState(status: CoreConnectionStatus.checking);
    notifyListeners();

    try {
      final version = _gateway.getCoreVersion();
      if (!_isCurrent(operationGeneration)) {
        return;
      }

      _state = _state.copyWith(
        status: CoreConnectionStatus.ready,
        version: version,
        clearError: true,
      );
      notifyListeners();

      _eventSubscription = _gateway.streamDemoEvents().listen(
        (event) {
          if (!_isCurrent(operationGeneration)) {
            return;
          }
          _state = _state.copyWith(events: [..._state.events, event]);
          notifyListeners();
        },
        onError: (Object _) {
          if (!_isCurrent(operationGeneration)) {
            return;
          }
          _state = _state.copyWith(
            status: CoreConnectionStatus.failed,
            errorMessage: 'The native event stream stopped unexpectedly.',
          );
          notifyListeners();
        },
      );
    } on Object {
      if (!_isCurrent(operationGeneration)) {
        return;
      }
      _state = _state.copyWith(
        status: CoreConnectionStatus.failed,
        errorMessage: 'The native core could not be reached.',
      );
      notifyListeners();
    }
  }

  bool _isCurrent(int operationGeneration) {
    return !_isDisposed && operationGeneration == _operationGeneration;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _operationGeneration++;
    final eventSubscription = _eventSubscription;
    _eventSubscription = null;
    unawaited(eventSubscription?.cancel());
    super.dispose();
  }
}
