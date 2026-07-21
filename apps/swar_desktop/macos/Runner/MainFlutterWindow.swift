import Cocoa
import ApplicationServices
import FlutterMacOS
import QuartzCore

class MainFlutterWindow: NSWindow {
  private var desktopChannel: FlutterMethodChannel?
  private var shortcutController: OptionKeyMonitor?
  private var overlayController: DictationOverlayController?

  override func awakeFromNib() {
    // Closing the red traffic-light button hides the application window. Keep
    // the native window alive so clicking Swar in the Dock can show it again.
    isReleasedWhenClosed = false
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "dev.swar/desktop",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    let shortcuts = OptionKeyMonitor(
      onPressed: { channel.invokeMethod("dictationKeyPressed", arguments: nil) },
      onReleased: { channel.invokeMethod("dictationKeyReleased", arguments: nil) }
    )
    let accessibility = AccessibilityAccessController()
    let overlay = DictationOverlayController(channel: channel)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "registerGlobalShortcut":
        result(shortcuts.register())
      case "unregisterGlobalShortcut":
        shortcuts.unregister()
        result(nil)
      case "configureGlobalShortcut":
        let arguments = call.arguments as? [String: Any]
        result(shortcuts.configure(arguments?["shortcutKey"] as? String ?? "option"))
      case "requestInsertionPermission":
        result(accessibility.requestIfNeeded())
      case "foregroundApplication":
        let application = NSWorkspace.shared.frontmostApplication
        result(application?.localizedName ?? "")
      case "focusedFieldIsSecure":
        // nil = Accessibility unavailable/unreadable (caller records coverage),
        // true = password/secure field, false = ordinary field.
        result(FocusedFieldInspector.isSecure().map { NSNumber(value: $0) })
      case "focusedFieldText":
        // Reference context for the on-device cleanup model. nil for a secure
        // field or when Accessibility is unavailable.
        if let text = FocusedFieldInspector.focusedText() {
          result(["before": text.before, "after": text.after])
        } else {
          result(nil)
        }
      case "updateDictationOverlay":
        if let arguments = call.arguments as? [String: Any] {
          overlay.update(
            DictationOverlaySnapshot(
              state: arguments["state"] as? String ?? "recording",
              audioLevel: arguments["audioLevel"] as? Double ?? 0,
              isLatched: arguments["isLatched"] as? Bool ?? false,
              shortcutKey: arguments["shortcutKey"] as? String ?? "option",
              // Absent means the ordinary recording/processing flow.
              condition: arguments["condition"] as? String,
              transcriptFinal: arguments["transcriptFinal"] as? String ?? "",
              transcriptPartial: arguments["transcriptPartial"] as? String ?? "",
              language: arguments["language"] as? String ?? "",
              elapsedMs: arguments["elapsedMs"] as? Int ?? 0,
              writingMode: arguments["writingMode"] as? String ?? "clean"
            )
          )
        }
        result(nil)
      case "hideDictationOverlay":
        overlay.hide()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    desktopChannel = channel
    shortcutController = shortcuts
    overlayController = overlay

    super.awakeFromNib()
  }
}

/// Read-only inspection of the currently focused UI element to decide whether it
/// is a secure (password) field. This never writes or inserts — it only reads the
/// element's role — so it does not reintroduce AX text insertion. A password
/// dictated into such a field must never be written to history (privacy P0).
private enum FocusedFieldInspector {
  /// Returns true for a secure field, false for an ordinary field, and nil when
  /// Accessibility is not granted or the focused element cannot be read (so the
  /// caller can default to non-sensitive but record that coverage was missing).
  static func isSecure() -> Bool? {
    guard AXIsProcessTrusted() else { return nil }
    let systemWide = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
      let focusedElement = focused
    else { return nil }
    let element = focusedElement as! AXUIElement
    // Native AppKit secure fields report role "AXSecureTextField"; some apps
    // (and browsers) expose it as the subrole instead.
    if stringAttribute(element, kAXRoleAttribute as CFString) == "AXSecureTextField" {
      return true
    }
    if stringAttribute(element, kAXSubroleAttribute as CFString) == "AXSecureTextField" {
      return true
    }
    return false
  }

  private static func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
    return value as? String
  }

  /// The focused field's own text, split at the caret, as reference context for
  /// the on-device cleanup model.
  ///
  /// Returns nil for a secure field, so a password is never read, and nil when
  /// Accessibility is unavailable. Read-only: this asks for the value and the
  /// selection range and writes nothing back.
  ///
  /// The caller must keep this on-device. It is the contents of the user's own
  /// document and must never be sent to a BYOK provider.
  static func focusedText() -> (before: String, after: String)? {
    guard AXIsProcessTrusted() else { return nil }
    // A secure field is never read, not even to be discarded later.
    if isSecure() == true { return nil }
    let systemWide = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
      let focusedElement = focused
    else { return nil }
    let element = focusedElement as! AXUIElement

    var valueRef: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
      let value = valueRef as? String,
      !value.isEmpty
    else { return nil }

    // Without a readable caret, treat the whole field as preceding text: the
    // model still gets the register, and nothing is invented about position.
    var caret = value.count
    var rangeRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(
      element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
      let rangeValue = rangeRef
    {
      var range = CFRange()
      if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.location >= 0 {
        caret = min(value.count, range.location)
      }
    }
    let split = value.index(value.startIndex, offsetBy: caret)
    return (before: String(value[..<split]), after: String(value[split...]))
  }

  /// The focused element's rect in Cocoa screen coordinates, so the overlay can
  /// avoid parking on top of the caret (overlay spec §7). Read-only, like
  /// `isSecure`: this never writes or inserts. Returns nil when Accessibility is
  /// not granted or the element has no readable geometry.
  static func focusedFrame() -> NSRect? {
    guard AXIsProcessTrusted() else { return nil }
    let systemWide = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
      let focusedElement = focused
    else { return nil }
    let element = focusedElement as! AXUIElement

    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element, kAXPositionAttribute as CFString, &positionValue) == .success,
      AXUIElementCopyAttributeValue(
        element, kAXSizeAttribute as CFString, &sizeValue) == .success
    else { return nil }

    var origin = CGPoint.zero
    var size = CGSize.zero
    guard
      let position = positionValue,
      let extent = sizeValue,
      AXValueGetValue(position as! AXValue, .cgPoint, &origin),
      AXValueGetValue(extent as! AXValue, .cgSize, &size),
      size.width > 0, size.height > 0
    else { return nil }

    // Accessibility reports a top-left origin with y growing downward; Cocoa
    // screen coordinates grow upward from the primary display's bottom.
    guard let primary = NSScreen.screens.first else { return nil }
    return NSRect(
      x: origin.x,
      y: primary.frame.maxY - origin.y - size.height,
      width: size.width,
      height: size.height
    )
  }
}

private final class AccessibilityAccessController {
  private var promptedThisLaunch = false

  var isTrusted: Bool { AXIsProcessTrusted() }

  func requestIfNeeded() -> Bool {
    if isTrusted { return true }
    guard !promptedThisLaunch else { return false }

    promptedThisLaunch = true
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    return isTrusted
  }
}

private final class OptionKeyMonitor {
  private let onPressed: () -> Void
  private let onReleased: () -> Void
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private var isPressed = false
  private var shortcutKey = "option"

  init(onPressed: @escaping () -> Void, onReleased: @escaping () -> Void) {
    self.onPressed = onPressed
    self.onReleased = onReleased
  }

  func register() -> Bool {
    if globalMonitor != nil || localMonitor != nil { return true }
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
      [weak self] event in self?.handle(event)
    }
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
      [weak self] event in
      self?.handle(event)
      return event
    }
    return globalMonitor != nil && localMonitor != nil
  }

  func unregister() {
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    globalMonitor = nil
    localMonitor = nil
    isPressed = false
  }

  func configure(_ shortcutKey: String) -> Bool {
    let normalized = shortcutKey == "control" ? "control" : "option"
    guard normalized != self.shortcutKey else { return register() }
    unregister()
    self.shortcutKey = normalized
    return register()
  }

  private func handle(_ event: NSEvent) {
    let pressed = shortcutKey == "control"
      ? event.modifierFlags.contains(.control)
      : event.modifierFlags.contains(.option)
    guard pressed != isPressed else { return }
    isPressed = pressed
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      pressed ? self.onPressed() : self.onReleased()
    }
  }

  deinit {
    unregister()
  }
}

/// Spec states 6-11: the outcomes and blockers that replace the recording row.
/// Each is the same capsule showing one glyph and one short sentence, so they
/// share a single renderer and differ only in glyph, tint, and label.
private enum OverlayCondition {
  case inserted
  case copied
  case permission
  case model
  case noField
  case secure

  init?(_ raw: String?) {
    switch raw {
    case "inserted": self = .inserted
    case "copied": self = .copied
    case "permission": self = .permission
    case "model": self = .model
    case "noField": self = .noField
    case "secure": self = .secure
    default: return nil
    }
  }

  /// Whether this condition takes over the capsule. `secure` is a persistent
  /// badge shown alongside recording rather than a terminal outcome, so it is
  /// drawn as a chip in the recording row instead.
  var replacesContent: Bool {
    if case .secure = self { return false }
    return true
  }

  var label: String {
    switch self {
    case .inserted: return "Inserted"
    case .copied: return "Couldn't insert — copied"
    case .permission: return "Allow microphone"
    case .model: return "Download voice model"
    case .noField: return "Click a text field first"
    case .secure: return "Private field — history off"
    }
  }

  var glyph: OverlayGlyph {
    switch self {
    case .inserted: return .check
    case .copied, .permission, .noField: return .warning
    case .model: return .download
    case .secure: return .lock
    }
  }

  var tint: NSColor {
    switch self {
    case .inserted: return OverlayPalette.spruce
    case .copied, .permission, .noField: return OverlayPalette.amber
    case .model: return OverlayPalette.saffron
    case .secure: return OverlayPalette.onPillMut
    }
  }
}

private enum OverlayGlyph {
  case check
  case warning
  case download
  case lock
}

/// One immutable frame of overlay state pushed from Dart (overlay spec section 6).
/// Raw PCM never crosses this boundary — only the smoothed numeric `audioLevel`.
struct DictationOverlaySnapshot {
  let state: String
  let audioLevel: Double
  let isLatched: Bool
  let shortcutKey: String
  /// `inserted` / `copied` / `permission` / `model` / `noField` / `secure`, or
  /// nil for the ordinary recording and processing flow (spec states 6-11).
  let condition: String?
  /// Confirmed words, drawn in full white.
  let transcriptFinal: String
  /// The not-yet-final tail, drawn muted.
  let transcriptPartial: String
  /// Chip label such as `EN`, `HI`, or `HI+EN`.
  let language: String
  let elapsedMs: Int
  /// `raw` / `clean` / `intent` — picks the Processing label.
  let writingMode: String
}

private final class DictationOverlayController {
  private let panel: DictationOverlayPanel
  private let content: DictationOverlayView
  private let commandOverlay: CommandScreenOverlayController
  private var globalMouseMonitor: Any?
  private var localMouseMonitor: Any?
  private var hoverPollTimer: Timer?
  // Drag and snap state (spec §7).
  private var dragStartOrigin: NSPoint?
  private var dragStartMouse: NSPoint?
  private var snapTarget: NSPoint?
  private var snapTimer: Timer?
  /// Where the bar rests, remembered per display.
  private var anchors: [CGDirectDisplayID: OverlayAnchor] = [:]

  init(channel: FlutterMethodChannel) {
    let commandOverlay = CommandScreenOverlayController()
    self.commandOverlay = commandOverlay
    content = DictationOverlayView(
      onDictate: { channel.invokeMethod("shortcutPressed", arguments: nil) },
      onLongPressStart: {
        commandOverlay.show()
        channel.invokeMethod("shortcutPressed", arguments: nil)
      },
      onLongPressEnd: {
        commandOverlay.hide()
        channel.invokeMethod("overlayStopPressed", arguments: nil)
      },
      onStop: { channel.invokeMethod("overlayStopPressed", arguments: nil) },
      onCancel: { channel.invokeMethod("overlayCancelPressed", arguments: nil) }
    )
    panel = DictationOverlayPanel(contentView: content)
    startMouseTracking()
    content.onDragBegan = { [weak self] in self?.beginDrag() }
    content.onDragChanged = { [weak self] in self?.continueDrag() }
    content.onDragEnded = { [weak self] in self?.endDrag() }
  }

  deinit {
    if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
    if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
    hoverPollTimer?.invalidate()
    snapTimer?.invalidate()
  }

  // Hover has to work while the user is in another app, so it cannot rely on the
  // panel's own tracking areas (those only fire when Swar is active). A global +
  // local mouse-moved monitor — the same mechanism as the shortcut key — reports
  // the cursor everywhere and drives the resting dock's expand-on-hover.
  private func startMouseTracking() {
    globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) {
      [weak self] _ in self?.handleMouseMoved()
    }
    localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) {
      [weak self] event in
      self?.handleMouseMoved()
      return event
    }
  }

  private func handleMouseMoved() {
    // While dragging, the capsule travels with the cursor. Re-evaluating hover
    // would let a moment of jitter collapse it to the resting dock and turn the
    // panel click-through, dropping the drag halfway.
    guard dragStartOrigin == nil else { return }
    guard panel.isVisible, content.stateIsIdle else {
      content.setHovering(false)
      stopHoverPolling()
      return
    }
    let mouse = NSEvent.mouseLocation
    // Hit-test the exact pill (in screen coords), which grows as it expands, so
    // hover triggers only over the dock itself — not a wide surrounding zone.
    let rectInView = content.hoverRectInView
    let zone = rectInView.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
    let hovering = zone.contains(mouse)
    content.setHovering(hovering)
    // Only the hovered pill accepts clicks (click to dictate); otherwise the dock
    // stays click-through so a stray click never starts dictation.
    panel.ignoresMouseEvents = !hovering
    if hovering { startHoverPolling() } else { stopHoverPolling() }
  }

  // Exiting hover cannot be driven by mouse-moved events. As soon as the pill
  // accepts clicks (ignoresMouseEvents = false) macOS routes moves over it to
  // Swar rather than to the global monitor, and the non-activating panel never
  // becomes key, so the local monitor stays silent too while another app is
  // active. No further events arrive and hover latches on forever.
  // NSEvent.mouseLocation is a query rather than an event, so polling it always
  // sees the true cursor position and lets hover release.
  private func startHoverPolling() {
    guard hoverPollTimer == nil else { return }
    let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      self?.handleMouseMoved()
    }
    hoverPollTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func stopHoverPolling() {
    hoverPollTimer?.invalidate()
    hoverPollTimer = nil
  }

  func update(_ snapshot: DictationOverlaySnapshot) {
    let idle = snapshot.state == "idle"
    if idle { commandOverlay.hide() }
    // At rest the capsule is a passive status indicator: ignore mouse so
    // hovering near it never expands to "Dictate" and a stray click can't start
    // dictation. It only accepts clicks while active (cancel/stop). Dictation is
    // started with the global shortcut key.
    panel.ignoresMouseEvents = idle
    content.update(snapshot)
    position()
    panel.orderFrontRegardless()
  }

  func hide() {
    commandOverlay.hide()
    panel.orderOut(nil)
  }

  /// Places the panel from the remembered anchor for the screen it belongs to.
  /// Skipped while a drag or a snap animation owns the origin.
  private func position() {
    guard dragStartOrigin == nil, snapTarget == nil else { return }
    guard let screen = anchorScreen() else { return }
    panel.setFrameOrigin(origin(for: anchor(for: screen), on: screen))
  }

  // MARK: Drag and snap (spec §7)

  private func beginDrag() {
    dragStartOrigin = panel.frame.origin
    dragStartMouse = NSEvent.mouseLocation
    // A new drag cancels any snap still easing into place.
    snapTarget = nil
  }

  private func continueDrag() {
    guard let startOrigin = dragStartOrigin, let startMouse = dragStartMouse else { return }
    let mouse = NSEvent.mouseLocation
    panel.setFrameOrigin(NSPoint(
      x: startOrigin.x + (mouse.x - startMouse.x),
      y: startOrigin.y + (mouse.y - startMouse.y)
    ))
  }

  private func endDrag() {
    dragStartOrigin = nil
    dragStartMouse = nil
    guard let screen = screenForCapsule() ?? anchorScreen() else { return }
    let visible = screen.visibleFrame
    let capsule = capsuleScreenRect()

    // Nearest horizontal edge wins: the bar belongs at the top or the bottom of
    // the screen, never floating in the middle.
    let distanceToBottom = capsule.midY - visible.minY
    let distanceToTop = visible.maxY - capsule.midY
    var resolved = OverlayAnchor(
      edge: distanceToTop < distanceToBottom ? .top : .bottom,
      centerXFraction: visible.width > 0
        ? min(1, max(0, (capsule.midX - visible.minX) / visible.width))
        : 0.5
    )
    // Spec §7: never cover the caret. If the snapped bar would sit over the
    // focused field, send it to the opposite edge instead.
    if let field = FocusedFieldInspector.focusedFrame(),
       snappedCapsuleRect(for: resolved, on: screen).intersects(field) {
      resolved.edge = resolved.edge == .bottom ? .top : .bottom
    }

    anchors[displayID(of: screen)] = resolved
    snapTarget = origin(for: resolved, on: screen)
    startSnapAnimation()
  }

  /// Eases the panel to its snapped origin. Moving the window for ~200 ms on
  /// release is cheap; continuously resizing it every frame is what janks, which
  /// is why the capsule morphs inside a fixed envelope instead.
  private func startSnapAnimation() {
    guard snapTimer == nil else { return }
    let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      guard let self, let target = self.snapTarget else { self?.stopSnapAnimation(); return }
      let current = self.panel.frame.origin
      let next = NSPoint(
        x: current.x + (target.x - current.x) * 0.22,
        y: current.y + (target.y - current.y) * 0.22
      )
      if abs(target.x - next.x) < 0.5, abs(target.y - next.y) < 0.5 {
        self.panel.setFrameOrigin(target)
        self.snapTarget = nil
        self.stopSnapAnimation()
        return
      }
      self.panel.setFrameOrigin(next)
    }
    snapTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func stopSnapAnimation() {
    snapTimer?.invalidate()
    snapTimer = nil
  }

  private func anchor(for screen: NSScreen) -> OverlayAnchor {
    anchors[displayID(of: screen)] ?? OverlayAnchor(edge: .bottom, centerXFraction: 0.5)
  }

  /// The panel origin that puts the capsule at `anchor` on `screen`. The capsule
  /// is centred horizontally in the envelope and sits `bottomMargin` above its
  /// bottom, so the envelope is offset to compensate.
  private func origin(for anchor: OverlayAnchor, on screen: NSScreen) -> NSPoint {
    let visible = screen.visibleFrame
    let frame = panel.frame
    let margin: CGFloat = 10
    let centerX = visible.minX + visible.width * anchor.centerXFraction
    // Keep the whole envelope on screen so a wide capsule cannot run off an edge.
    let clampedX = min(
      max(centerX - frame.width / 2, visible.minX - frame.width / 2 + 60),
      visible.maxX + frame.width / 2 - 60 - frame.width
    )
    switch anchor.edge {
    case .bottom:
      return NSPoint(x: clampedX, y: visible.minY + margin)
    case .top:
      // Anchor the capsule's top edge, which sits bottomMargin + its height up.
      return NSPoint(x: clampedX, y: visible.maxY - margin - frame.height)
    }
  }

  /// Where the capsule itself would land for a candidate anchor, used for the
  /// caret-overlap check.
  private func snappedCapsuleRect(for anchor: OverlayAnchor, on screen: NSScreen) -> NSRect {
    let panelOrigin = origin(for: anchor, on: screen)
    let local = content.hoverRectInView
    return NSRect(
      x: panelOrigin.x + local.minX,
      y: panelOrigin.y + local.minY,
      width: local.width,
      height: local.height
    )
  }

  private func capsuleScreenRect() -> NSRect {
    let local = content.hoverRectInView
    return NSRect(
      x: panel.frame.minX + local.minX,
      y: panel.frame.minY + local.minY,
      width: local.width,
      height: local.height
    )
  }

  /// The screen the capsule currently sits on, for multi-display placement.
  private func screenForCapsule() -> NSScreen? {
    let capsule = capsuleScreenRect()
    return NSScreen.screens.first { $0.frame.intersects(capsule) }
  }

  private func anchorScreen() -> NSScreen? {
    screenForCapsule() ?? NSScreen.main ?? NSScreen.screens.first
  }

  private func displayID(of screen: NSScreen) -> CGDirectDisplayID {
    (screen.deviceDescription[
      NSDeviceDescriptionKey("NSScreenNumber")
    ] as? NSNumber)?.uint32Value ?? 0
  }
}

/// Which screen edge the bar rests against, and where along it (spec §7).
private struct OverlayAnchor {
  enum Edge {
    case bottom
    case top
  }

  var edge: Edge
  /// 0-1 across the screen's visible width, so the bar returns to the same spot
  /// after a resolution change.
  var centerXFraction: CGFloat
}

private final class CommandScreenOverlayController {
  private let panel: CommandScreenOverlayPanel
  private let content: CommandScreenOverlayView

  init() {
    content = CommandScreenOverlayView()
    panel = CommandScreenOverlayPanel(contentView: content)
  }

  func show() {
    let mouse = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
      ?? NSScreen.main
      ?? NSScreen.screens.first else { return }
    panel.setFrame(screen.frame, display: true)
    content.setFrameSize(screen.frame.size)
    content.startAnimating()
    panel.orderFrontRegardless()
  }

  func hide() {
    content.stopAnimating()
    panel.orderOut(nil)
  }
}

private final class CommandScreenOverlayPanel: NSPanel {
  init(contentView: NSView) {
    super.init(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    self.contentView = contentView
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    ignoresMouseEvents = true
    level = .screenSaver
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

private final class CommandScreenOverlayView: NSView {
  private var phase = 0.0
  private var timer: Timer?

  func startAnimating() {
    guard timer == nil else { return }
    let timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.phase += 0.20
      self.needsDisplay = true
    }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func stopAnimating() {
    timer?.invalidate()
    timer = nil
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    NSColor(calibratedWhite: 0.02, alpha: 0.74).setFill()
    NSBezierPath(rect: bounds).fill()

    let center = NSPoint(x: bounds.midX, y: bounds.height * 0.28)
    let circle = NSRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28)
    NSColor(calibratedWhite: 0.015, alpha: 0.98).setFill()
    NSBezierPath(ovalIn: circle).fill()
    NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
    let border = NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
    border.lineWidth = 1
    border.stroke()

    NSColor.white.setFill()
    for index in 0..<5 {
      let pulse = (sin(phase + Double(index) * 0.9) + 1) / 2
      let height = 5 + CGFloat(pulse) * 9
      let rect = NSRect(
        x: center.x - 9 + CGFloat(index) * 4,
        y: center.y - height / 2,
        width: 2,
        height: height
      )
      NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
    }
  }

  deinit {
    timer?.invalidate()
  }
}

private final class DictationOverlayPanel: NSPanel {
  init(contentView: NSView) {
    super.init(
      // A fixed transparent envelope. The capsule morphs *inside* it every frame,
      // so the window itself never resizes mid-animation (resizing an NSPanel at
      // 60 fps thrashes the window server and janks the morph). Sized for the
      // largest state (the two-line live transcript) plus shadow margin.
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 190),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    self.contentView = contentView
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    acceptsMouseMovedEvents = true
    level = .statusBar
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Overlay design tokens (spec §3). The bar is dark in both app themes.
private enum OverlayPalette {
  static let pillBg = NSColor(srgbRed: 0x1C / 255.0, green: 0x1F / 255.0, blue: 0x1E / 255.0, alpha: 1)
  static let pillBgAlt = NSColor(srgbRed: 0x26 / 255.0, green: 0x30 / 255.0, blue: 0x2B / 255.0, alpha: 1)
  static let onPill = NSColor.white
  static let onPillMut = NSColor(srgbRed: 0x9A / 255.0, green: 0xA6 / 255.0, blue: 0xA0 / 255.0, alpha: 1)
  static let onPillSoft = NSColor(srgbRed: 0xC9 / 255.0, green: 0xD2 / 255.0, blue: 0xCE / 255.0, alpha: 1)
  static let spruce = NSColor(srgbRed: 0x2F / 255.0, green: 0x55 / 255.0, blue: 0x47 / 255.0, alpha: 1)
  static let saffron = NSColor(srgbRed: 0xF4 / 255.0, green: 0xB2 / 255.0, blue: 0x4A / 255.0, alpha: 1)
  /// Warning tint for the copied-fallback, permission, and no-field states.
  static let amber = NSColor(srgbRed: 0xE8 / 255.0, green: 0x8B / 255.0, blue: 0x2E / 255.0, alpha: 1)
}

/// A lightweight critically-ish damped spring, integrated with semi-implicit
/// Euler each frame. Drives the capsule's width/height/radius so the bar morphs
/// organically between states instead of snapping or opacity-swapping (spec §5.1).
private struct Spring {
  var value: CGFloat
  var velocity: CGFloat = 0

  init(_ value: CGFloat) { self.value = value }

  mutating func step(to target: CGFloat, stiffness: CGFloat, damping: CGFloat, dt: CGFloat) {
    let acceleration = -stiffness * (value - target) - damping * velocity
    velocity += acceleration * dt
    value += velocity * dt
  }

  var isSettled: Bool { abs(velocity) < 0.05 }
}

/// The dictation capsule (spec §1): one dark pill that morphs in place across
/// every state. Geometry (width/height/radius) is spring-driven; the contents of
/// the current state cross-fade inside the morphing shape. Anchored at the bottom
/// of a fixed transparent envelope panel so it can grow upward for the live
/// transcript without the window ever resizing.
private final class DictationOverlayView: NSView {
  private let onDictate: () -> Void
  private let onLongPressStart: () -> Void
  private let onLongPressEnd: () -> Void
  private let onStop: () -> Void
  private let onCancel: () -> Void
  private var state = "idle"
  // True only in the locked (double-press) hands-free state.
  private var isLatched = false
  private var targetAudioLevel = 0.0
  private var displayedAudioLevel = 0.0
  private var animationPhase = 0.0
  private var animationTimer: Timer?
  private(set) var isHovering = false
  private var shortcutSymbol = "⌥"
  // Extended contract (spec §6).
  private var condition: OverlayCondition?
  private var transcriptFinal = ""
  private var transcriptPartial = ""
  private var languageLabel = ""
  private var elapsedMs = 0
  private var writingMode = "clean"
  /// Memoised result of the two-line middle-truncation search, keyed on the
  /// transcript text and the available width.
  private var transcriptFitCache: (key: String, value: NSAttributedString)?

  // Spring-morphed capsule geometry (spec §5.1). Resting "dock" is intentionally
  // tiny — a subtle indicator, not a button.
  private var geoW = Spring(28)
  private var geoH = Spring(7)
  private var geoR = Spring(3.5)
  // Per-state content opacity, eased ~150 ms (spec §5.2).
  private var idleC: CGFloat = 1
  private var readyC: CGFloat = 0
  private var recordingC: CGFloat = 0
  private var processingC: CGFloat = 0
  private var conditionC: CGFloat = 0

  private var longPressTimer: Timer?
  private var pointerIsDown = false
  private var longPressTriggered = false
  /// Accumulated pointer travel for the current press, to tell a drag from a
  /// click. Set by the controller, which owns the panel being moved.
  private var dragDistance: CGFloat = 0
  var onDragBegan: (() -> Void)?
  var onDragChanged: (() -> Void)?
  var onDragEnded: (() -> Void)?

  // Bottom margin inside the envelope so the capsule sits just above the screen
  // edge and its shadow is not clipped.
  private let bottomMargin: CGFloat = 22

  init(
    onDictate: @escaping () -> Void,
    onLongPressStart: @escaping () -> Void,
    onLongPressEnd: @escaping () -> Void,
    onStop: @escaping () -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.onDictate = onDictate
    self.onLongPressStart = onLongPressStart
    self.onLongPressEnd = onLongPressEnd
    self.onStop = onStop
    self.onCancel = onCancel
    super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 190))
    wantsLayer = true
  }

  required init?(coder: NSCoder) { nil }

  func update(_ snapshot: DictationOverlaySnapshot) {
    state = snapshot.state
    if state != "idle", isHovering { isHovering = false }
    targetAudioLevel = min(max(snapshot.audioLevel * 9, 0), 1)
    isLatched = snapshot.isLatched
    shortcutSymbol = snapshot.shortcutKey == "control" ? "⌃" : "⌥"
    condition = OverlayCondition(snapshot.condition)
    transcriptFinal = snapshot.transcriptFinal
    transcriptPartial = snapshot.transcriptPartial
    languageLabel = snapshot.language
    elapsedMs = snapshot.elapsedMs
    writingMode = snapshot.writingMode
    startAnimating()
    needsDisplay = true
  }

  var stateIsIdle: Bool { state == "idle" }

  /// Driven by the controller's global mouse monitor: when the cursor is over the
  /// resting dock, the pill expands to the "Ready" mic capsule (spec state 2).
  /// Only meaningful at idle; a live session ignores hover.
  func setHovering(_ hovering: Bool) {
    guard state == "idle", hovering != isHovering else { return }
    isHovering = hovering
    startAnimating()
  }

  deinit {
    animationTimer?.invalidate()
    longPressTimer?.invalidate()
  }

  // MARK: Geometry

  /// The capsule's target size for the current state. Every state is this same
  /// pill at a different size; the springs interpolate between them.
  /// - Parameter holdingReady: the Ready label is still fading out, so keep the
  ///   expanded size for now (see `tick`).
  private func targetGeometry(holdingReady: Bool = false) -> (w: CGFloat, h: CGFloat, r: CGFloat) {
    // A terminal or blocking condition takes over the capsule entirely: one
    // glyph and one sentence, sized to its own text (spec states 6-11).
    if let condition, condition.replacesContent {
      let width = min(maxCapsuleWidth, conditionLabelWidth(condition) + 52)
      return (width, 30, 15)
    }
    switch state {
    // Preparing is the arming moment before audio arrives; it opens straight into
    // the recording row (spec §4), never the processing dots — otherwise pressing
    // the key flashes "Understanding…" for a frame.
    case "recording", "preparing":
      // State 3b: once partial text exists the SAME capsule grows taller to hold
      // it above the recording row. It never spawns a second floating element.
      return (recordingWidth, recordingRowHeight + transcriptBlockHeight(), 15)
    case "finalising":
      return (processingWidth, 30, 15)
    default: // idle
      return (isHovering || holdingReady) ? (134, 34, 17) : (28, 7, 3.5)
    }
  }

  /// Recording is wider than the bare waveform pill because the row also carries
  /// the language chip and the elapsed timer (spec state 3).
  private var recordingWidth: CGFloat { 224 }
  private var recordingRowHeight: CGFloat { 30 }
  private var processingWidth: CGFloat { 146 }
  private var maxCapsuleWidth: CGFloat { 420 }
  /// Horizontal padding for the transcript block inside the capsule.
  private let transcriptInset: CGFloat = 14

  /// The live transcript at full opacity, final words white and the not-yet-final
  /// tail muted. Empty when nothing has been recognised yet. The fade is applied
  /// by the context when drawing, so the measured and drawn strings are the same
  /// object and can be cached.
  private func transcriptText() -> NSAttributedString? {
    let final = transcriptFinal.trimmingCharacters(in: .whitespacesAndNewlines)
    let partial = transcriptPartial.trimmingCharacters(in: .whitespacesAndNewlines)
    if final.isEmpty, partial.isEmpty { return nil }
    let font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
    let result = NSMutableAttributedString()
    if !final.isEmpty {
      result.append(NSAttributedString(string: final, attributes: [
        .font: font,
        .foregroundColor: OverlayPalette.onPill,
      ]))
    }
    if !partial.isEmpty {
      if result.length > 0 { result.append(NSAttributedString(string: " ")) }
      result.append(NSAttributedString(string: partial, attributes: [
        .font: font,
        .foregroundColor: OverlayPalette.onPillMut,
      ]))
    }
    return result
  }

  /// The transcript never grows past two lines, so the capsule settles at one of
  /// three heights instead of creeping taller with every word.
  private static let transcriptMaxLines: CGFloat = 2
  private static let transcriptLineHeight: CGFloat = 16

  /// The width the transcript is laid out against. Deliberately the *settled*
  /// recording width rather than the animating capsule width: fitting against a
  /// width that changes every frame would re-run the truncation search each
  /// frame and make the capsule's height chase itself while it morphs.
  private var transcriptContentWidth: CGFloat { recordingWidth - 2 * transcriptInset }

  /// How much taller the capsule must grow to hold the transcript.
  private func transcriptBlockHeight() -> CGFloat {
    let width = transcriptContentWidth
    guard width > 0, let text = fittedTranscript(forWidth: width) else { return 0 }
    let bounds = text.boundingRect(
      with: NSSize(width: width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let cap = Self.transcriptMaxLines * Self.transcriptLineHeight
    return min(ceil(bounds.height), cap) + 12
  }

  /// The transcript trimmed to fit two lines by dropping from the **middle**.
  ///
  /// Truncating the head loses how the sentence began; truncating the tail hides
  /// the words just spoken. Keeping both ends means the first line always starts
  /// at the beginning and the last line always ends at the newest word.
  ///
  /// Recomputed only when the text or the width changes — the search costs
  /// several layout passes and the view redraws at 60 fps.
  private func fittedTranscript(forWidth width: CGFloat) -> NSAttributedString? {
    guard let full = transcriptText() else {
      transcriptFitCache = nil
      return nil
    }
    let key = "\(transcriptFinal)\u{1}\(transcriptPartial)\u{1}\(Int(width))"
    if let cache = transcriptFitCache, cache.key == key { return cache.value }

    let limit = NSSize(width: width, height: .greatestFiniteMagnitude)
    let cap = Self.transcriptMaxLines * Self.transcriptLineHeight + 1
    func fits(_ candidate: NSAttributedString) -> Bool {
      candidate.boundingRect(
        with: limit,
        options: [.usesLineFragmentOrigin, .usesFontLeading]
      ).height <= cap
    }

    var result = full
    if !fits(full) {
      // Binary search the largest number of characters that still fits, split
      // evenly between the head and the tail.
      let total = full.length
      var low = 0
      var high = total
      var best: NSAttributedString?
      while low <= high {
        let keep = (low + high) / 2
        let candidate = middleTruncated(full, keeping: keep)
        if fits(candidate) {
          best = candidate
          low = keep + 1
        } else {
          high = keep - 1
        }
      }
      result = best ?? middleTruncated(full, keeping: 0)
    }
    transcriptFitCache = (key: key, value: result)
    return result
  }

  /// `full` reduced to `keep` characters, half from the front and half from the
  /// back, joined by an ellipsis. Attributes ride along, so the final/partial
  /// white-and-grey split survives the trim.
  private func middleTruncated(_ full: NSAttributedString, keeping keep: Int) -> NSAttributedString {
    let total = full.length
    guard keep < total else { return full }
    let headLength = max(1, keep / 2)
    let tailLength = max(1, keep - headLength)
    guard headLength + tailLength < total else { return full }
    let output = NSMutableAttributedString()
    output.append(full.attributedSubstring(from: NSRange(location: 0, length: headLength)))
    output.append(NSAttributedString(string: " … ", attributes: [
      .font: NSFont.systemFont(ofSize: 12.5, weight: .regular),
      .foregroundColor: OverlayPalette.onPillMut,
    ]))
    output.append(
      full.attributedSubstring(
        from: NSRange(location: total - tailLength, length: tailLength))
    )
    return output
  }

  private func conditionLabelWidth(_ condition: OverlayCondition) -> CGFloat {
    let text = NSAttributedString(string: condition.label, attributes: [
      .font: NSFont.systemFont(ofSize: 12, weight: .medium),
    ])
    return ceil(text.size().width)
  }

  /// The capsule rect at its current animated size, anchored bottom-center.
  private var capsuleRect: NSRect {
    let w = geoW.value
    let h = geoH.value
    return NSRect(x: bounds.midX - w / 2, y: bottomMargin, width: w, height: h)
  }

  /// The live capsule rect in view coordinates, so the controller can hit-test
  /// hover against the exact pill (which grows as it expands) rather than a fixed
  /// zone. Padded so the tiny resting dock is still reachable.
  var hoverRectInView: NSRect { capsuleRect.insetBy(dx: -5, dy: -5) }

  // MARK: Drawing

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let rect = capsuleRect
    let radius = min(geoR.value, rect.height / 2)

    // Ready (hover) is two independent pitch-black widgets side by side, not one
    // container, so the single capsule fades out as Ready fades in.
    let baseOpacity = max(0, 1 - readyC)
    if baseOpacity > 0.001 {
      let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
      // Pitch black, matching the Ready widgets so every state is the same surface.
      fillPill(path, color: .black, opacity: 0.97 * baseOpacity)
      NSColor(calibratedWhite: 1, alpha: 0.10 * baseOpacity).setStroke()
      let border = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
      border.lineWidth = 0.75
      border.stroke()

      // Contents cross-fade inside the morphing capsule, clipped to its shape so
      // text never spills while the pill is still growing.
      NSGraphicsContext.saveGraphicsState()
      path.setClip()
      if recordingC > 0.001 { drawRecordingRow(in: rect, opacity: recordingC) }
      if processingC > 0.001 { drawProcessing(in: rect, opacity: processingC) }
      if conditionC > 0.001, let condition, condition.replacesContent {
        drawCondition(condition, in: rect, opacity: conditionC)
      }
      // Idle contributes no content — it is an empty pill.
      NSGraphicsContext.restoreGraphicsState()
    }

    if readyC > 0.001 { drawReadyRow(in: rect, opacity: readyC) }
  }

  /// Fills a pill path with a soft drop shadow, confined so the shadow never
  /// bleeds onto the contents drawn afterwards.
  private func fillPill(_ path: NSBezierPath, color: NSColor, opacity: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
    shadow.shadowBlurRadius = 16
    shadow.shadowOffset = NSSize(width: 0, height: -3)
    shadow.set()
    color.withAlphaComponent(opacity).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
  }

  /// Spec state 2 (Ready): two independent pitch-black widgets in a row — a round
  /// mic button and a "Dictate ⌥" pill — matching height and border. Shown on
  /// hover today; on text-field focus once the data contract lands.
  private func drawReadyRow(in rect: NSRect, opacity: CGFloat) {
    let text: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
      .foregroundColor: OverlayPalette.onPill.withAlphaComponent(opacity),
    ]
    let glyph: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
      .foregroundColor: OverlayPalette.onPillSoft.withAlphaComponent(opacity),
    ]
    let label = NSMutableAttributedString(string: "Dictate  ", attributes: text)
    label.append(NSAttributedString(string: shortcutSymbol, attributes: glyph))
    let labelSize = label.size()

    let height = rect.height
    let gap: CGFloat = 8
    let micWidget = NSRect(x: rect.minX, y: rect.minY, width: height, height: height)
    let dictateWidget = NSRect(
      x: micWidget.maxX + gap,
      y: rect.minY,
      width: max(0, rect.width - height - gap),
      height: height
    )

    drawBlackWidget(micWidget, opacity: opacity)
    drawMic(center: NSPoint(x: micWidget.midX, y: micWidget.midY), opacity: opacity)

    drawBlackWidget(dictateWidget, opacity: opacity)
    label.draw(at: NSPoint(
      x: dictateWidget.midX - labelSize.width / 2,
      y: dictateWidget.midY - labelSize.height / 2
    ))
  }

  /// One pitch-black widget of the Ready row.
  private func drawBlackWidget(_ frame: NSRect, opacity: CGFloat) {
    let radius = frame.height / 2
    let path = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    fillPill(path, color: .black, opacity: 0.97 * opacity)
    NSColor(calibratedWhite: 1, alpha: 0.10 * opacity).setStroke()
    let border = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    border.lineWidth = 0.75
    border.stroke()
  }

  private func drawMic(center: NSPoint, opacity: CGFloat) {
    OverlayPalette.onPill.withAlphaComponent(opacity).setStroke()
    let body = NSBezierPath(
      roundedRect: NSRect(x: center.x - 3.2, y: center.y - 1.5, width: 6.4, height: 10),
      xRadius: 3.2, yRadius: 3.2)
    body.lineWidth = 1.6
    body.stroke()
    let cradle = NSBezierPath()
    cradle.lineWidth = 1.6
    cradle.lineCapStyle = .round
    cradle.move(to: NSPoint(x: center.x - 5.4, y: center.y + 2))
    cradle.curve(
      to: NSPoint(x: center.x + 5.4, y: center.y + 2),
      controlPoint1: NSPoint(x: center.x - 5.4, y: center.y - 5.5),
      controlPoint2: NSPoint(x: center.x + 5.4, y: center.y - 5.5))
    cradle.move(to: NSPoint(x: center.x, y: center.y - 4.5))
    cradle.line(to: NSPoint(x: center.x, y: center.y - 7.5))
    cradle.stroke()
  }

  /// Spec state 3: cancel · waveform · language chip · elapsed · confirm. When a
  /// partial transcript exists (state 3b) the row sits at the bottom of the same
  /// capsule and the text is drawn above it — one element, never two.
  private func drawRecordingRow(in rect: NSRect, opacity: CGFloat) {
    // The row keeps its own height at the bottom; anything above it is transcript.
    let row = NSRect(
      x: rect.minX,
      y: rect.minY,
      width: rect.width,
      height: min(rect.height, recordingRowHeight)
    )
    if rect.height > row.height + 1 {
      drawTranscript(
        in: NSRect(
          x: rect.minX + transcriptInset,
          y: row.maxY,
          width: rect.width - 2 * transcriptInset,
          height: rect.height - row.height
        ),
        opacity: opacity
      )
    }

    let cancelCenter = NSPoint(x: row.minX + 15, y: row.midY)
    let confirmCenter = NSPoint(x: row.maxX - 15, y: row.midY)
    // Latched (spec state 4): the cancel slot becomes a lock chip, so the row
    // reads as hands-free rather than one tap from discarding the dictation.
    if isLatched {
      drawLockChip(center: cancelCenter, opacity: opacity)
    } else {
      drawCancel(center: cancelCenter, opacity: opacity)
    }
    drawConfirm(center: confirmCenter, opacity: opacity)

    // Right-hand metadata: elapsed first (fixed width), then the language chip.
    var metadataX = confirmCenter.x - 17
    let elapsed = NSAttributedString(string: elapsedLabel, attributes: [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
      .foregroundColor: OverlayPalette.onPillMut.withAlphaComponent(opacity),
    ])
    let elapsedSize = elapsed.size()
    metadataX -= elapsedSize.width
    elapsed.draw(at: NSPoint(x: metadataX, y: row.midY - elapsedSize.height / 2))

    // Spec state 11: a secure field keeps the full recording row — the user is
    // still dictating into it — but the chip becomes a lock so the "history off"
    // guarantee is visible for the whole session.
    let isSecureField = condition.map { if case .secure = $0 { return true } else { return false } } ?? false
    let chipLabel = isSecureField ? "private" : (isLatched ? "locked" : languageLabel)
    if !chipLabel.isEmpty {
      let chip = NSAttributedString(string: chipLabel, attributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
        .foregroundColor: OverlayPalette.onPillSoft.withAlphaComponent(opacity),
      ])
      let chipSize = chip.size()
      let glyphSpace: CGFloat = isSecureField ? 13 : 0
      let chipRect = NSRect(
        x: metadataX - 8 - (chipSize.width + 12 + glyphSpace),
        y: row.midY - 8,
        width: chipSize.width + 12 + glyphSpace,
        height: 16
      )
      OverlayPalette.pillBgAlt.withAlphaComponent(0.85 * opacity).setFill()
      NSBezierPath(roundedRect: chipRect, xRadius: 8, yRadius: 8).fill()
      if isSecureField {
        drawGlyph(
          .lock,
          center: NSPoint(x: chipRect.minX + 10, y: chipRect.midY),
          tint: OverlayPalette.onPillSoft,
          opacity: opacity
        )
      }
      chip.draw(at: NSPoint(
        x: chipRect.minX + 6 + glyphSpace,
        y: chipRect.midY - chipSize.height / 2
      ))
      metadataX = chipRect.minX
    }

    // Clear the icon radius (9) plus real breathing room so the wave never
    // touches the buttons or the metadata.
    drawWaveform(
      from: cancelCenter.x + 17,
      to: max(cancelCenter.x + 17, metadataX - 10),
      midY: row.midY,
      opacity: opacity
    )
  }

  /// `m:ss`, matching the reference image's `0:07`.
  private var elapsedLabel: String {
    let totalSeconds = max(0, elapsedMs / 1000)
    return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
  }

  /// Spec state 3b: the live transcript drawn inside the capsule, above the
  /// recording row, trimmed from the middle so both ends stay readable.
  private func drawTranscript(in rect: NSRect, opacity: CGFloat) {
    guard let text = fittedTranscript(forWidth: transcriptContentWidth) else { return }
    NSGraphicsContext.saveGraphicsState()
    // Fade the whole block at once rather than baking alpha into every colour,
    // which keeps the measured and drawn strings identical and cacheable.
    NSGraphicsContext.current?.cgContext.setAlpha(opacity)
    // Inset the top so the text is not flush against the capsule's shoulder.
    text.draw(with: NSRect(
      x: rect.minX,
      y: rect.minY,
      width: rect.width,
      height: max(0, rect.height - 6)
    ), options: [.usesLineFragmentOrigin, .usesFontLeading])
    NSGraphicsContext.restoreGraphicsState()
  }

  /// Spec state 4: the locked (hands-free) chip that replaces cancel.
  private func drawLockChip(center: NSPoint, opacity: CGFloat) {
    let circle = NSRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)
    OverlayPalette.pillBgAlt.withAlphaComponent(opacity).setFill()
    NSBezierPath(ovalIn: circle).fill()
    drawGlyph(.lock, center: center, tint: OverlayPalette.onPillSoft, opacity: opacity)
  }

  /// Spec states 6-11: one glyph plus one sentence, centred in the capsule.
  private func drawCondition(_ condition: OverlayCondition, in rect: NSRect, opacity: CGFloat) {
    let text = NSAttributedString(string: condition.label, attributes: [
      .font: NSFont.systemFont(ofSize: 12, weight: .medium),
      .foregroundColor: OverlayPalette.onPill.withAlphaComponent(opacity),
    ])
    let textSize = text.size()
    let glyphWidth: CGFloat = 20
    let gap: CGFloat = 9
    let groupWidth = glyphWidth + gap + textSize.width
    let originX = rect.midX - groupWidth / 2
    drawGlyph(
      condition.glyph,
      center: NSPoint(x: originX + glyphWidth / 2, y: rect.midY),
      tint: condition.tint,
      opacity: opacity
    )
    text.draw(at: NSPoint(
      x: originX + glyphWidth + gap,
      y: rect.midY - textSize.height / 2
    ))
  }

  /// The small vector glyphs shared by the condition states. Drawn rather than
  /// set as emoji so they inherit the tint and stay crisp at this size.
  private func drawGlyph(
    _ glyph: OverlayGlyph,
    center: NSPoint,
    tint: NSColor,
    opacity: CGFloat
  ) {
    let color = tint.withAlphaComponent(opacity)
    switch glyph {
    case .check:
      color.setFill()
      NSBezierPath(ovalIn: NSRect(
        x: center.x - 8, y: center.y - 8, width: 16, height: 16)).fill()
      OverlayPalette.onPill.withAlphaComponent(opacity).setStroke()
      let check = NSBezierPath()
      check.lineWidth = 1.7
      check.lineCapStyle = .round
      check.lineJoinStyle = .round
      check.move(to: NSPoint(x: center.x - 3.6, y: center.y - 0.4))
      check.line(to: NSPoint(x: center.x - 0.9, y: center.y - 3.1))
      check.line(to: NSPoint(x: center.x + 3.9, y: center.y + 3.1))
      check.stroke()
    case .warning:
      color.setStroke()
      let triangle = NSBezierPath()
      triangle.lineWidth = 1.5
      triangle.lineJoinStyle = .round
      triangle.move(to: NSPoint(x: center.x, y: center.y + 7))
      triangle.line(to: NSPoint(x: center.x + 7.5, y: center.y - 6))
      triangle.line(to: NSPoint(x: center.x - 7.5, y: center.y - 6))
      triangle.close()
      triangle.stroke()
      let bang = NSBezierPath()
      bang.lineWidth = 1.6
      bang.lineCapStyle = .round
      bang.move(to: NSPoint(x: center.x, y: center.y + 3.2))
      bang.line(to: NSPoint(x: center.x, y: center.y - 1.4))
      bang.stroke()
      color.setFill()
      NSBezierPath(ovalIn: NSRect(
        x: center.x - 0.9, y: center.y - 4.4, width: 1.8, height: 1.8)).fill()
    case .download:
      color.setStroke()
      let arrow = NSBezierPath()
      arrow.lineWidth = 1.6
      arrow.lineCapStyle = .round
      arrow.lineJoinStyle = .round
      arrow.move(to: NSPoint(x: center.x, y: center.y + 6.5))
      arrow.line(to: NSPoint(x: center.x, y: center.y - 2.2))
      arrow.move(to: NSPoint(x: center.x - 3.6, y: center.y + 1.4))
      arrow.line(to: NSPoint(x: center.x, y: center.y - 2.2))
      arrow.line(to: NSPoint(x: center.x + 3.6, y: center.y + 1.4))
      arrow.move(to: NSPoint(x: center.x - 6, y: center.y - 5.6))
      arrow.line(to: NSPoint(x: center.x + 6, y: center.y - 5.6))
      arrow.stroke()
    case .lock:
      color.setStroke()
      let shackle = NSBezierPath()
      shackle.lineWidth = 1.5
      shackle.lineCapStyle = .round
      shackle.move(to: NSPoint(x: center.x - 3.2, y: center.y + 0.8))
      shackle.line(to: NSPoint(x: center.x - 3.2, y: center.y + 3.2))
      shackle.curve(
        to: NSPoint(x: center.x + 3.2, y: center.y + 3.2),
        controlPoint1: NSPoint(x: center.x - 3.2, y: center.y + 6.6),
        controlPoint2: NSPoint(x: center.x + 3.2, y: center.y + 6.6))
      shackle.line(to: NSPoint(x: center.x + 3.2, y: center.y + 0.8))
      shackle.stroke()
      color.setFill()
      NSBezierPath(roundedRect: NSRect(
        x: center.x - 5, y: center.y - 5.4, width: 10, height: 6.6),
        xRadius: 1.6, yRadius: 1.6).fill()
    }
  }

  private func drawCancel(center: NSPoint, opacity: CGFloat) {
    let circle = NSRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)
    OverlayPalette.pillBgAlt.withAlphaComponent(opacity).setFill()
    NSBezierPath(ovalIn: circle).fill()
    OverlayPalette.onPillMut.withAlphaComponent(opacity).setStroke()
    let cross = NSBezierPath()
    cross.lineWidth = 1.6
    cross.lineCapStyle = .round
    cross.move(to: NSPoint(x: center.x - 3.4, y: center.y - 3.4))
    cross.line(to: NSPoint(x: center.x + 3.4, y: center.y + 3.4))
    cross.move(to: NSPoint(x: center.x + 3.4, y: center.y - 3.4))
    cross.line(to: NSPoint(x: center.x - 3.4, y: center.y + 3.4))
    cross.stroke()
  }

  private func drawConfirm(center: NSPoint, opacity: CGFloat) {
    let circle = NSRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)
    OverlayPalette.spruce.withAlphaComponent(opacity).setFill()
    NSBezierPath(ovalIn: circle).fill()
    OverlayPalette.onPill.withAlphaComponent(opacity).setStroke()
    let check = NSBezierPath()
    check.lineWidth = 1.7
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.move(to: NSPoint(x: center.x - 4, y: center.y - 0.5))
    check.line(to: NSPoint(x: center.x - 1, y: center.y - 3.5))
    check.line(to: NSPoint(x: center.x + 4.4, y: center.y + 3.5))
    check.stroke()
  }

  private func drawWaveform(from startX: CGFloat, to endX: CGFloat, midY: CGFloat, opacity: CGFloat) {
    // A fuller equalizer: more, slightly wider bars that swell from the centre,
    // so the waveform reads as the hero of the recording pill.
    let multipliers: [CGFloat] = [
      0.34, 0.5, 0.72, 0.55, 0.9, 0.68, 1.0, 0.74,
      0.9, 0.62, 1.0, 0.7, 0.88, 0.56, 0.76, 0.5, 0.34,
    ]
    let barCount = multipliers.count
    let span = max(0, endX - startX)
    let step = span / CGFloat(barCount - 1)
    let live = state == "recording" || state == "preparing"
    let maxHeight = min(CGFloat(20), midY * 1.55)
    OverlayPalette.saffron.withAlphaComponent(opacity).setFill()
    for index in 0..<barCount {
      let wave = (sin(animationPhase * 1.15 + Double(index) * 0.7) + 1) / 2
      let ambient = live ? 0.24 + wave * 0.22 : 0.14
      let strength = min(1, ambient + displayedAudioLevel * 0.9)
      let height = max(2.5, strength * maxHeight * multipliers[index])
      let bar = NSRect(
        x: startX + CGFloat(index) * step - 1,
        y: midY - height / 2,
        width: 2,
        height: height
      )
      NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
    }
  }

  /// Spec state 5: three sequenced dots + the writing-mode label, centered in the
  /// pill.
  private func drawProcessing(in rect: NSRect, opacity: CGFloat) {
    let label: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
      .foregroundColor: OverlayPalette.onPill.withAlphaComponent(opacity),
    ]
    let text = NSAttributedString(string: processingLabel, attributes: label)
    let textSize = text.size()
    let dotsWidth: CGFloat = 22
    let gap: CGFloat = 7
    let groupWidth = dotsWidth + gap + textSize.width
    let originX = rect.midX - groupWidth / 2
    for index in 0..<3 {
      let pulse = (sin(animationPhase * 1.5 - Double(index) * 0.7) + 1) / 2
      let alpha = opacity * (0.35 + CGFloat(pulse) * 0.65)
      OverlayPalette.saffron.withAlphaComponent(alpha).setFill()
      let diameter = 3.4 + CGFloat(pulse) * 1.4
      let dot = NSRect(
        x: originX + CGFloat(index) * 8 + (4 - diameter / 2),
        y: rect.midY - diameter / 2,
        width: diameter,
        height: diameter
      )
      NSBezierPath(ovalIn: dot).fill()
    }
    text.draw(at: NSPoint(x: originX + dotsWidth + gap, y: rect.midY - textSize.height / 2))
  }

  /// The Processing verb tracks what Swar is actually doing to the words, so
  /// Raw mode never claims to be "understanding" text it will not rewrite.
  private var processingLabel: String {
    switch writingMode {
    case "raw": return "Transcribing…"
    case "intent": return "Understanding…"
    default: return "Cleaning…"
    }
  }

  // MARK: Animation

  private func startAnimating() {
    guard animationTimer == nil else { return }
    let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      self?.tick()
    }
    animationTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func tick() {
    let dt: CGFloat = 1.0 / 60.0
    animationPhase += 0.10
    displayedAudioLevel += (targetAudioLevel - displayedAudioLevel) * 0.18
    targetAudioLevel *= 0.955

    // Content cross-fades (~150 ms), computed before the geometry so the label's
    // opacity can gate the collapse below.
    // A condition that replaces the content wins over every ordinary state, so
    // Success or Copied is never drawn on top of the processing dots.
    let takeover = condition?.replacesContent ?? false
    let conditionT: CGFloat = takeover ? 1 : 0
    let idleT: CGFloat = (!takeover && state == "idle" && !isHovering) ? 1 : 0
    let readyT: CGFloat = (!takeover && state == "idle" && isHovering) ? 1 : 0
    let recordingT: CGFloat = (!takeover && (state == "recording" || state == "preparing")) ? 1 : 0
    let processingT: CGFloat = (!takeover && state == "finalising") ? 1 : 0
    conditionC += (conditionT - conditionC) * 0.22
    idleC += (idleT - idleC) * 0.22
    // Ready fades out far faster than it fades in. On hover-out the mic and
    // "Dictate" label have to be gone *before* the capsule collapses, or the text
    // visibly squashes inside the shrinking pill.
    readyC += (readyT - readyC) * (readyT > readyC ? 0.22 : 0.55)
    recordingC += (recordingT - recordingC) * 0.22
    processingC += (processingT - processingC) * 0.22

    // Geometry springs. A touch of overshoot on grow reads as alive; shrink is
    // near-critical so Processing/idle collapse feel decisive (spec §5.1).
    // Hold the expanded size while Ready is still fading, so the two never
    // animate at once.
    let holdingReady = readyT == 0 && readyC > 0.06
    let target = targetGeometry(holdingReady: holdingReady)
    let growing = target.w > geoW.value
    let damping: CGFloat = growing ? 27 : 30
    geoW.step(to: target.w, stiffness: 240, damping: damping, dt: dt)
    geoH.step(to: target.h, stiffness: 240, damping: damping, dt: dt)
    geoR.step(to: target.r, stiffness: 240, damping: 31, dt: dt)

    needsDisplay = true

    // Park the timer once fully idle and settled to save power.
    if state == "idle", !isHovering, !takeover,
       readyC < 0.003, recordingC < 0.003, processingC < 0.003, conditionC < 0.003,
       geoW.isSettled, geoH.isSettled
    {
      readyC = 0; recordingC = 0; processingC = 0; conditionC = 0
      stopAnimating()
    }
  }

  private func stopAnimating() {
    animationTimer?.invalidate()
    animationTimer = nil
    targetAudioLevel = 0
    displayedAudioLevel = 0
  }

  // MARK: Mouse

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    dragDistance = 0
    onDragBegan?()
    if state == "idle" {
      pointerIsDown = true
      longPressTriggered = false
      let timer = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
        guard let self, self.pointerIsDown, self.dragDistance < Self.dragSlop else { return }
        self.longPressTriggered = true
        self.onLongPressStart()
      }
      longPressTimer = timer
      RunLoop.main.add(timer, forMode: .common)
      return
    }
    guard state == "recording", isLatched else { return }
    let point = convert(event.locationInWindow, from: nil)
    let rect = capsuleRect
    if point.x < rect.midX {
      onCancel()
    } else {
      onStop()
    }
  }

  /// How far the pointer must travel before the gesture counts as a drag rather
  /// than a click, so a slightly shaky click still starts dictation.
  private static let dragSlop: CGFloat = 4

  override func mouseDragged(with event: NSEvent) {
    dragDistance += abs(event.deltaX) + abs(event.deltaY)
    guard dragDistance >= Self.dragSlop else { return }
    // A drag is a reposition, never a long-press activation.
    longPressTimer?.invalidate()
    longPressTimer = nil
    if longPressTriggered {
      longPressTriggered = false
      onLongPressEnd()
    }
    onDragChanged?()
  }

  override func mouseUp(with event: NSEvent) {
    let wasDragged = dragDistance >= Self.dragSlop
    if wasDragged { onDragEnded?() }
    guard pointerIsDown else { return }
    pointerIsDown = false
    longPressTimer?.invalidate()
    longPressTimer = nil
    if longPressTriggered {
      onLongPressEnd()
    } else if !wasDragged {
      // Repositioning the bar must never also start a dictation.
      onDictate()
    }
    longPressTriggered = false
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // Clicks pass through everywhere except the visible capsule when it has an
    // action: the hovered Ready pill (click to dictate) or a locked recording
    // (cancel/stop). The tiny resting dock is passive, so a stray click can never
    // start dictation.
    let interactive = (state == "idle" && isHovering) || (state == "recording" && isLatched)
    guard interactive else { return nil }
    let local = convert(point, from: nil)
    return capsuleRect.insetBy(dx: -4, dy: -4).contains(local) ? self : nil
  }
}
