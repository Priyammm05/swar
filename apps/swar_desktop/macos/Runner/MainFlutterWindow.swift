import Cocoa
import ApplicationServices
import FlutterMacOS
import QuartzCore

class MainFlutterWindow: NSWindow {
  private var desktopChannel: FlutterMethodChannel?
  private var shortcutController: OptionKeyMonitor?
  private var overlayController: DictationOverlayController?

  override func awakeFromNib() {
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
      case "requestInsertionPermission":
        // This is intentionally a silent status check. Permission guidance
        // belongs in Swar's Settings; normal dictation must never summon TCC.
        result(accessibility.isTrusted)
      case "updateDictationOverlay":
        if let arguments = call.arguments as? [String: Any] {
          overlay.update(
            state: arguments["state"] as? String ?? "recording",
            audioLevel: arguments["audioLevel"] as? Double ?? 0,
            isLatched: arguments["isLatched"] as? Bool ?? false
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

private final class AccessibilityAccessController {
  var isTrusted: Bool { AXIsProcessTrusted() }
}

private final class OptionKeyMonitor {
  private let onPressed: () -> Void
  private let onReleased: () -> Void
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private var isPressed = false

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

  private func handle(_ event: NSEvent) {
    let pressed = event.modifierFlags.contains(.option)
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
  private var targetSize = NSSize(width: 44, height: 7)

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
    content.onHoverChanged = { [weak self] hovering in
      guard let self, self.content.isIdle else { return }
      self.resize(to: hovering ? NSSize(width: 100, height: 58) : NSSize(width: 44, height: 7))
    }
  }

  func update(state: String, audioLevel: Double, isLatched: Bool) {
    let idle = state == "idle"
    if idle { commandOverlay.hide() }
    panel.ignoresMouseEvents = false
    content.update(state: state, audioLevel: audioLevel, isLatched: isLatched)
    resize(
      to: idle
        ? (content.isHovering ? NSSize(width: 100, height: 58) : NSSize(width: 44, height: 7))
        : NSSize(width: 106, height: 30)
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

  private func resize(to size: NSSize) {
    guard size != targetSize else { return }
    targetSize = size
    let frame = panel.frame
    let resizedFrame = NSRect(
      x: frame.midX - size.width / 2,
      y: frame.minY,
      width: size.width,
      height: size.height
    )
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      context.allowsImplicitAnimation = true
      panel.animator().setFrame(resizedFrame, display: true)
    }
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
      contentRect: NSRect(x: 0, y: 0, width: 44, height: 7),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    self.contentView = contentView
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    level = .statusBar
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

private final class DictationOverlayView: NSView {
  private let onDictate: () -> Void
  private let onLongPressStart: () -> Void
  private let onLongPressEnd: () -> Void
  private let onStop: () -> Void
  private let onCancel: () -> Void
  private var state = "idle"
  private var targetAudioLevel = 0.0
  private var displayedAudioLevel = 0.0
  private var animationPhase = 0.0
  private var animationTimer: Timer?
  private(set) var isHovering = false
  private var hoverProgress: CGFloat = 0
  private var activeProgress: CGFloat = 0
  private var trackingArea: NSTrackingArea?
  private var longPressTimer: Timer?
  private var pointerIsDown = false
  private var longPressTriggered = false
  var onHoverChanged: ((Bool) -> Void)?
  var isIdle: Bool { state == "idle" }

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
    super.init(frame: NSRect(x: 0, y: 0, width: 44, height: 7))
    wantsLayer = true
  }

  required init?(coder: NSCoder) { nil }

  func update(state: String, audioLevel: Double, isLatched: Bool) {
    self.state = state
    if state != "idle", isHovering {
      isHovering = false
      onHoverChanged?(false)
    }
    targetAudioLevel = min(max(audioLevel * 9, 0), 1)
    _ = isLatched
    startAnimating()
    needsDisplay = true
  }

  deinit {
    animationTimer?.invalidate()
    longPressTimer?.invalidate()
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let idleOpacity = max(0, 1 - activeProgress)
    if idleOpacity > 0.001 {
      drawIdlePill(opacity: idleOpacity * (1 - hoverProgress))
      drawHoverControl(opacity: idleOpacity * hoverProgress)
    }
    if activeProgress > 0.001 { drawActiveControl(opacity: activeProgress) }
  }

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
    let point = convert(event.locationInWindow, from: nil)
    if point.x < 44 {
      onCancel()
    } else if point.x > bounds.width - 44 {
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

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    guard state == "idle" else { return }
    isHovering = true
    startAnimating()
    onHoverChanged?(true)
  }

  override func mouseExited(with event: NSEvent) {
    guard state == "idle" else { return }
    if pointerIsDown { return }
    isHovering = false
    startAnimating()
    onHoverChanged?(false)
  }

  private func drawIdlePill(opacity: CGFloat) {
    guard opacity > 0.001 else { return }
    let pill = NSRect(x: bounds.midX - 22, y: 0, width: 44, height: 7)
      .insetBy(dx: 0.5, dy: 0.5)
    NSColor(calibratedWhite: 0.25, alpha: 0.90 * opacity).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
    NSColor(calibratedWhite: 1, alpha: 0.28 * opacity).setStroke()
    let border = NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6)
    border.lineWidth = 0.75
    border.stroke()
  }

  private func drawHoverControl(opacity: CGFloat) {
    guard opacity > 0.001, bounds.height > 12 else { return }
    let hint = NSRect(x: 3, y: 32, width: 94, height: 24)
    NSColor(calibratedWhite: 0.02, alpha: 0.98 * opacity).setFill()
    NSBezierPath(roundedRect: hint, xRadius: 12, yRadius: 12).fill()
    let textAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
      .foregroundColor: NSColor.white.withAlphaComponent(opacity),
    ]
    let optionAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 14, weight: .bold),
      .foregroundColor: NSColor.white.withAlphaComponent(opacity),
    ]
    let label = NSMutableAttributedString(string: "Dictate ", attributes: textAttributes)
    label.append(NSAttributedString(string: "⌥", attributes: optionAttributes))
    let labelSize = label.size()
    label.draw(
      at: NSPoint(x: hint.midX - labelSize.width / 2, y: hint.midY - labelSize.height / 2)
    )

    let rail = NSRect(x: 28, y: 0, width: 44, height: 6)
    NSColor(calibratedWhite: 0.42, alpha: 0.72 * opacity).setFill()
    NSBezierPath(roundedRect: rail, xRadius: 4, yRadius: 4).fill()

    let button = NSRect(x: 29, y: 3, width: 42, height: 27)
    NSColor(calibratedWhite: 0.16, alpha: 0.99 * opacity).setFill()
    NSBezierPath(roundedRect: button, xRadius: 13.5, yRadius: 13.5).fill()
    drawMicrophone(center: NSPoint(x: button.midX, y: button.midY + 1), opacity: opacity)
  }

  private func drawMicrophone(center: NSPoint, opacity: CGFloat) {
    NSColor.white.withAlphaComponent(opacity).setStroke()
    let body = NSBezierPath(roundedRect: NSRect(
      x: center.x - 4,
      y: center.y - 3,
      width: 7,
      height: 11
    ), xRadius: 4, yRadius: 4)
    body.lineWidth = 2
    body.stroke()
    let cradle = NSBezierPath()
    cradle.lineWidth = 2
    cradle.move(to: NSPoint(x: center.x - 7, y: center.y + 2))
    cradle.curve(
      to: NSPoint(x: center.x + 7, y: center.y + 2),
      controlPoint1: NSPoint(x: center.x - 7, y: center.y - 7),
      controlPoint2: NSPoint(x: center.x + 7, y: center.y - 7)
    )
    cradle.move(to: NSPoint(x: center.x, y: center.y - 5))
    cradle.line(to: NSPoint(x: center.x, y: center.y - 9))
    cradle.stroke()
  }

  private func drawActiveControl(opacity: CGFloat) {
    let capsule = bounds.insetBy(dx: 0.75, dy: 0.75)
    NSColor(calibratedWhite: 0.015, alpha: 0.99 * opacity).setFill()
    NSBezierPath(roundedRect: capsule, xRadius: 15, yRadius: 15).fill()
    NSColor(calibratedWhite: 1, alpha: 0.13 * opacity).setStroke()
    let border = NSBezierPath(roundedRect: capsule, xRadius: 15, yRadius: 15)
    border.lineWidth = 0.75
    border.stroke()
    drawCancel(opacity: opacity)
    drawWaveform(opacity: opacity)
    drawConfirm(opacity: opacity)
  }

  private func drawCancel(opacity: CGFloat) {
    let circle = NSRect(x: 3, y: 5, width: 20, height: 20)
    NSColor(calibratedWhite: 0.20, alpha: opacity).setFill()
    NSBezierPath(ovalIn: circle).fill()
    NSColor(calibratedWhite: 0.90, alpha: opacity).setStroke()
    let cross = NSBezierPath()
    cross.lineWidth = 1.5
    cross.move(to: NSPoint(x: 9, y: 11))
    cross.line(to: NSPoint(x: 17, y: 19))
    cross.move(to: NSPoint(x: 17, y: 11))
    cross.line(to: NSPoint(x: 9, y: 19))
    cross.stroke()
  }

  private func drawWaveform(opacity: CGFloat) {
    let centerX: CGFloat = 29
    let heights: [CGFloat] = [0.48, 0.72, 0.94, 0.68, 1.0, 0.82, 0.64, 0.92, 0.73, 0.56, 0.42]
    let stateOpacity: CGFloat = state == "finalising" ? 0.62 : 1.0
    NSColor(calibratedWhite: 1, alpha: stateOpacity * opacity).setFill()
    for (index, multiplier) in heights.enumerated() {
      let wave = (sin(animationPhase + Double(index) * 0.82) + 1) / 2
      let ambient = state == "recording" ? 0.16 + wave * 0.18 : 0.13
      let strength = min(1, ambient + displayedAudioLevel * 0.82)
      let height = max(3, CGFloat(strength) * 24 * multiplier)
      let rect = NSRect(
        x: centerX + CGFloat(index) * 4.25,
        y: 15 - height / 2,
        width: 2.35,
        height: height
      )
      NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
    }
  }

  private func startAnimating() {
    guard animationTimer == nil else { return }
    let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.animationPhase += 0.10
      self.displayedAudioLevel += (self.targetAudioLevel - self.displayedAudioLevel) * 0.18
      self.targetAudioLevel *= 0.955
      let hoverTarget: CGFloat = self.isHovering && self.state == "idle" ? 1 : 0
      let activeTarget: CGFloat = self.state == "idle" ? 0 : 1
      self.hoverProgress += (hoverTarget - self.hoverProgress) * 0.20
      self.activeProgress += (activeTarget - self.activeProgress) * 0.20
      self.needsDisplay = true
      if self.state == "idle", !self.isHovering,
         self.hoverProgress < 0.002, self.activeProgress < 0.002
      {
        self.hoverProgress = 0
        self.activeProgress = 0
        self.stopAnimating()
      }
    }
    animationTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func stopAnimating() {
    animationTimer?.invalidate()
    animationTimer = nil
    targetAudioLevel = 0
    displayedAudioLevel = 0
  }

  private func drawConfirm(opacity: CGFloat) {
    let circle = NSRect(x: 83, y: 5, width: 20, height: 20)
    NSColor.white.withAlphaComponent(opacity).setFill()
    NSBezierPath(ovalIn: circle).fill()
    NSColor(calibratedWhite: 0.08, alpha: opacity).setStroke()
    let check = NSBezierPath()
    check.lineWidth = 1.6
    check.move(to: NSPoint(x: 88, y: 15))
    check.line(to: NSPoint(x: 92, y: 11))
    check.line(to: NSPoint(x: 99, y: 18))
    check.stroke()
  }
}
