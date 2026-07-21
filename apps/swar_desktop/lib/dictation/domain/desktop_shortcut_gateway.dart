enum DesktopShortcutEventKind { pressed, released, toggle, stop, cancel }

final class DesktopShortcutEvent {
  const DesktopShortcutEvent(this.kind);

  final DesktopShortcutEventKind kind;
}

enum DesktopOverlayState { idle, preparing, recording, finalising }

/// The text surrounding the caret in the focused field.
final class FocusedFieldText {
  const FocusedFieldText({this.before = '', this.after = ''});

  final String before;
  final String after;

  bool get isEmpty => before.isEmpty && after.isEmpty;
}

/// The exceptional situation the overlay must surface (overlay spec section 3,
/// states 6-11). `null` means the ordinary recording and processing flow.
enum DesktopOverlayCondition {
  /// Text landed at the cursor.
  inserted,

  /// Insertion failed, so the words went to the clipboard instead.
  copied,

  /// Microphone or Accessibility permission is missing.
  permission,

  /// No verified offline voice model is installed.
  model,

  /// Dictation was invoked with no text field focused.
  noField,

  /// The focused field is a password, OTP, or payment field.
  secure,
}

/// One immutable snapshot of everything the native overlay renders.
///
/// Passed as a single value rather than a growing parameter list, so adding a
/// field to the overlay does not change the signature of every implementation
/// and test fake. Raw PCM never crosses this boundary — only the smoothed
/// numeric [audioLevel] does.
final class DesktopOverlaySnapshot {
  const DesktopOverlaySnapshot({
    required this.state,
    required this.audioLevel,
    required this.isLatched,
    required this.shortcutKey,
    this.condition,
    this.transcriptFinal = '',
    this.transcriptPartial = '',
    this.language = '',
    this.elapsedMs = 0,
    this.writingMode = SwarOverlayWritingMode.clean,
  });

  final DesktopOverlayState state;

  /// 0-1 smoothed input level driving the waveform.
  final double audioLevel;
  final bool isLatched;

  /// `option` or `control` — picks the glyph shown in the Ready state.
  final String shortcutKey;
  final DesktopOverlayCondition? condition;

  /// Confirmed words, drawn in full white.
  final String transcriptFinal;

  /// The not-yet-final tail, drawn muted.
  final String transcriptPartial;

  /// Chip label such as `EN`, `HI`, or `HI+EN`.
  final String language;

  /// Recording elapsed time, for the timer in the recording row.
  final int elapsedMs;

  /// Picks the Processing label: Transcribing, Cleaning, or Understanding.
  final SwarOverlayWritingMode writingMode;
}

/// Mirrors `SwarWritingMode` without making the dictation layer depend on
/// settings, so the overlay contract stays self-contained.
enum SwarOverlayWritingMode { raw, clean, intent }

abstract interface class DesktopShortcutGateway {
  Stream<DesktopShortcutEvent> get events;

  Future<bool> initialize();

  Future<bool> configureShortcut(String shortcutKey);

  Future<bool> requestInsertionPermission();

  Future<String> foregroundApplication();

  /// Whether the currently focused field is a secure/password field. Used to
  /// suppress history storage for that dictation (privacy P0).
  Future<bool> focusedFieldIsSecure();

  /// The focused field's own text, split at the caret, as reference context for
  /// the on-device cleanup model. Empty for a secure field or when
  /// Accessibility is unavailable.
  ///
  /// This is the user's own document text. It must reach the local model only
  /// and must never be sent to a BYOK provider.
  Future<FocusedFieldText> focusedFieldText();

  Future<void> updateOverlay(DesktopOverlaySnapshot snapshot);

  Future<void> hideOverlay();

  Future<void> dispose();
}

final class NoopDesktopShortcutGateway implements DesktopShortcutGateway {
  const NoopDesktopShortcutGateway();

  @override
  Stream<DesktopShortcutEvent> get events => const Stream.empty();

  @override
  Future<bool> initialize() async => false;

  @override
  Future<bool> configureShortcut(String shortcutKey) async => false;

  @override
  Future<bool> requestInsertionPermission() async => true;

  @override
  Future<String> foregroundApplication() async => '';

  @override
  Future<bool> focusedFieldIsSecure() async => false;

  @override
  Future<FocusedFieldText> focusedFieldText() async => const FocusedFieldText();

  @override
  Future<void> updateOverlay(DesktopOverlaySnapshot snapshot) async {}

  @override
  Future<void> hideOverlay() async {}

  @override
  Future<void> dispose() async {}
}
