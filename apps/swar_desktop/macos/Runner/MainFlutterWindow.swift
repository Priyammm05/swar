import Cocoa
import ApplicationServices
import Carbon.HIToolbox
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var desktopChannel: FlutterMethodChannel?
  private var shortcutController: GlobalShortcutController?

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
    let shortcuts = GlobalShortcutController {
      channel.invokeMethod("shortcutPressed", arguments: nil)
    }
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "registerGlobalShortcut":
        result(shortcuts.register())
      case "unregisterGlobalShortcut":
        shortcuts.unregister()
        result(nil)
      case "requestInsertionPermission":
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        result(AXIsProcessTrustedWithOptions(options as CFDictionary))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    desktopChannel = channel
    shortcutController = shortcuts

    super.awakeFromNib()
  }
}

private final class GlobalShortcutController {
  private let onPressed: () -> Void
  private var hotKey: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?

  init(onPressed: @escaping () -> Void) {
    self.onPressed = onPressed
  }

  func register() -> Bool {
    if hotKey != nil { return true }
    var specification = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData -> OSStatus in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &identifier
        )
        guard status == noErr, identifier.id == 1 else {
          return OSStatus(eventNotHandledErr)
        }
        Unmanaged<GlobalShortcutController>.fromOpaque(userData)
          .takeUnretainedValue().onPressed()
        return noErr
      },
      1,
      &specification,
      context,
      &eventHandler
    )
    guard handlerStatus == noErr else { return false }

    let identifier = EventHotKeyID(signature: 0x53574152, id: 1) // SWAR
    let registrationStatus = RegisterEventHotKey(
      UInt32(kVK_Space),
      UInt32(controlKey),
      identifier,
      GetApplicationEventTarget(),
      0,
      &hotKey
    )
    if registrationStatus != noErr {
      unregister()
      return false
    }
    return true
  }

  func unregister() {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    if let eventHandler { RemoveEventHandler(eventHandler) }
    hotKey = nil
    eventHandler = nil
  }

  deinit {
    unregister()
  }
}
