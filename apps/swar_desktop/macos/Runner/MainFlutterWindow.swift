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
      case "updateDictationOverlay":
        if let arguments = call.arguments as? [String: Any] {
          overlay.update(
            state: arguments["state"] as? String ?? "recording",
            audioLevel: arguments["audioLevel"] as? Double ?? 0,
            isLatched: arguments["isLatched"] as? Bool ?? false,
            shortcutKey: arguments["shortcutKey"] as? String ?? "option"
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

private final class DictationOverlayController {
  private let panel: DictationOverlayPanel
  private let content: DictationOverlayView
  private let commandOverlay: CommandScreenOverlayController
  private var globalMouseMonitor: Any?
  private var localMouseMonitor: Any?
  private var hoverPollTimer: Timer?

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
  }

  deinit {
    if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
    if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
    hoverPollTimer?.invalidate()
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

  func update(state: String, audioLevel: Double, isLatched: Bool, shortcutKey: String) {
    let idle = state == "idle"
    if idle { commandOverlay.hide() }
    // At rest the capsule is a passive status indicator: ignore mouse so
    // hovering near it never expands to "Dictate" and a stray click can't start
    // dictation. It only accepts clicks while active (cancel/stop). Dictation is
    // started with the global shortcut key.
    panel.ignoresMouseEvents = idle
    content.update(
      state: state,
      audioLevel: audioLevel,
      isLatched: isLatched,
      shortcutKey: shortcutKey
    )
    position()
    panel.orderFrontRegardless()
  }

  func hide() {
    commandOverlay.hide()
    panel.orderOut(nil)
  }

  private func position() {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
    let frame = panel.frame
    let visible = screen.visibleFrame
    panel.setFrameOrigin(NSPoint(
      x: visible.midX - frame.width / 2,
      y: visible.minY + 10
    ))
  }
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

  private var longPressTimer: Timer?
  private var pointerIsDown = false
  private var longPressTriggered = false

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

  func update(state: String, audioLevel: Double, isLatched: Bool, shortcutKey: String) {
    self.state = state
    if state != "idle", isHovering { isHovering = false }
    targetAudioLevel = min(max(audioLevel * 9, 0), 1)
    self.isLatched = isLatched
    shortcutSymbol = shortcutKey == "control" ? "⌃" : "⌥"
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
    switch state {
    // Preparing is the arming moment before audio arrives; it opens straight into
    // the recording row (spec §4), never the processing dots — otherwise pressing
    // the key flashes "Understanding…" for a frame.
    case "recording", "preparing":
      return (162, 30, 15)
    case "finalising":
      return (130, 30, 15)
    default: // idle
      return (isHovering || holdingReady) ? (134, 34, 17) : (28, 7, 3.5)
    }
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

  /// Spec state 3: cancel · waveform · confirm, laid out relative to the capsule.
  /// (Language chip + elapsed timer + live transcript arrive with the extended
  /// data contract in the next slice.)
  private func drawRecordingRow(in rect: NSRect, opacity: CGFloat) {
    let cancelCenter = NSPoint(x: rect.minX + 15, y: rect.midY)
    let confirmCenter = NSPoint(x: rect.maxX - 15, y: rect.midY)
    drawCancel(center: cancelCenter, opacity: opacity)
    drawConfirm(center: confirmCenter, opacity: opacity)
    // Clear the icon radius (9) plus real breathing room so the wave never
    // touches the buttons.
    drawWaveform(
      from: cancelCenter.x + 17,
      to: confirmCenter.x - 17,
      midY: rect.midY,
      opacity: opacity
    )
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

  /// Spec state 5: three sequenced dots + a label, centered in the pill. (The
  /// writing-mode-specific label — Transcribing / Cleaning / Understanding —
  /// arrives with the extended data contract.)
  private func drawProcessing(in rect: NSRect, opacity: CGFloat) {
    let label: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
      .foregroundColor: OverlayPalette.onPill.withAlphaComponent(opacity),
    ]
    let text = NSAttributedString(string: "Understanding…", attributes: label)
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
    let idleT: CGFloat = (state == "idle" && !isHovering) ? 1 : 0
    let readyT: CGFloat = (state == "idle" && isHovering) ? 1 : 0
    let recordingT: CGFloat = (state == "recording" || state == "preparing") ? 1 : 0
    let processingT: CGFloat = (state == "finalising") ? 1 : 0
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
    if state == "idle", !isHovering,
       readyC < 0.003, recordingC < 0.003, processingC < 0.003,
       geoW.isSettled, geoH.isSettled
    {
      readyC = 0; recordingC = 0; processingC = 0
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
    if state == "idle" {
      pointerIsDown = true
      longPressTriggered = false
      let timer = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
        guard let self, self.pointerIsDown else { return }
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

  override func mouseUp(with event: NSEvent) {
    guard pointerIsDown else { return }
    pointerIsDown = false
    longPressTimer?.invalidate()
    longPressTimer = nil
    if longPressTriggered {
      onLongPressEnd()
    } else {
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
