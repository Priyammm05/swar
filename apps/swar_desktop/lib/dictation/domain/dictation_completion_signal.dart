// apps/swar_desktop/lib/dictation/domain/dictation_completion_signal.dart

import 'package:flutter/foundation.dart';

/// "A dictation just finished." Domain Layer.
///
/// Pages that show derived data — history, Insights — need to know when a new
/// dictation has landed in the local database. They depend on this one-getter
/// interface rather than on the dictation session view model, so a feature can
/// react to a finished dictation without reaching into another feature's
/// presentation layer.
abstract interface class DictationCompletionSignal implements Listenable {
  /// Increments once for every dictation that completes. Comparing it against
  /// the last seen value distinguishes a real completion from the many other
  /// notifications a session emits while recording.
  int get completionRevision;
}
