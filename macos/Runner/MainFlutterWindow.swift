import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let initialFrame = NSRect(x: 0, y: 0, width: 1040, height: 700)
    self.contentViewController = flutterViewController
    self.setFrame(initialFrame, display: true)
    self.minSize = NSSize(width: 720, height: 520)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    let delegate = NSApp.delegate as? AppDelegate
    let bridge = MacosPlatformBridge(
      messenger: flutterViewController.engine.binaryMessenger,
      appDelegate: delegate
    )
    delegate?.platformBridge = bridge

    super.awakeFromNib()

    if Self.startsInTray() {
      self.orderOut(nil)
    }
  }

  private static func startsInTray() -> Bool {
    guard CommandLine.arguments.contains("--autostart") else { return false }
    guard let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      return false
    }
    let marker = appSupport
      .appendingPathComponent("com.keqdroid.keqdroid", isDirectory: true)
      .appendingPathComponent("autostart-in-tray")
    return FileManager.default.fileExists(atPath: marker.path)
  }
}
