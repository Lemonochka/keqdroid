import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private static let supportedSchemes: Set<String> = ["keqdroid", "keqdis"]

  var platformBridge: MacosPlatformBridge?
  private var pendingDeepLink: String?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag, let window = mainFlutterWindow {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    guard let url = urls.first(where: {
      guard let scheme = $0.scheme?.lowercased() else { return false }
      return Self.supportedSchemes.contains(scheme)
    }) else {
      return
    }
    pendingDeepLink = url.absoluteString
    platformBridge?.notifyDeepLinkArrived()
    if let window = mainFlutterWindow {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  func takePendingDeepLink() -> String? {
    let url = pendingDeepLink
    pendingDeepLink = nil
    return url
  }
}
