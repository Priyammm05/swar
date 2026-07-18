// apps/swar_desktop/lib/diagnostics/presentation/core_diagnostics_state.dart

enum CoreConnectionStatus { idle, checking, ready, failed }

/// Immutable diagnostics state. Presentation Layer.
final class CoreDiagnosticsState {
  const CoreDiagnosticsState({
    this.status = CoreConnectionStatus.idle,
    this.version,
    this.events = const <int>[],
    this.errorMessage,
  });

  final CoreConnectionStatus status;
  final String? version;
  final List<int> events;
  final String? errorMessage;

  CoreDiagnosticsState copyWith({
    CoreConnectionStatus? status,
    String? version,
    List<int>? events,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CoreDiagnosticsState(
      status: status ?? this.status,
      version: version ?? this.version,
      events: events ?? this.events,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
