import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var statusItem: NSStatusItem?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    configureStatusItem()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      showMainWindow()
    }
    return true
  }

  private func configureStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = item.button, let image = NSImage(named: "MenuBarIcon") {
      image.isTemplate = true
      image.size = NSSize(width: 32, height: 12)
      button.image = image
      button.imagePosition = .imageOnly
      button.toolTip = "Swar"
      button.setAccessibilityLabel("Swar")
    }

    let menu = NSMenu()
    let openItem = NSMenuItem(
      title: "Open Swar",
      action: #selector(showMainWindow),
      keyEquivalent: ""
    )
    openItem.target = self
    menu.addItem(openItem)
    menu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: "Quit Swar",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    menu.addItem(quitItem)

    item.menu = menu
    statusItem = item
  }

  @objc private func showMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    if let window = mainFlutterWindow {
      window.makeKeyAndOrderFront(nil)
      return
    }
    NSApp.windows
      .first(where: { $0 is MainFlutterWindow })?
      .makeKeyAndOrderFront(nil)
  }
}
