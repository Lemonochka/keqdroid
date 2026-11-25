import Carbon.HIToolbox
import Cocoa
import FlutterMacOS
import Foundation

final class MacosPlatformBridge {
  private static let hotKeySignature: OSType = 0x4B455144 // 'KEQD'

  private let vpnChannel: FlutterMethodChannel
  private let hotkeyChannel: FlutterMethodChannel
  private let screenChannel: FlutterMethodChannel
  private weak var appDelegate: AppDelegate?

  private var hotKeyEventHandler: EventHandlerRef?
  private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
  private var hotKeyActions: [UInt32: String] = [:]
  private var nextHotKeyId: UInt32 = 1

  init(messenger: FlutterBinaryMessenger, appDelegate: AppDelegate?) {
    self.appDelegate = appDelegate
    self.vpnChannel = FlutterMethodChannel(
      name: "keqdroid_vpn_channel",
      binaryMessenger: messenger
    )
    self.hotkeyChannel = FlutterMethodChannel(
      name: "keqdroid/macos_hotkeys",
      binaryMessenger: messenger
    )
    self.screenChannel = FlutterMethodChannel(
      name: "keqdroid/macos_screen",
      binaryMessenger: messenger
    )

    vpnChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleVpnCall(call, result: result)
    }
    hotkeyChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleHotkeyCall(call, result: result)
    }
    screenChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleScreenCall(call, result: result)
    }
  }

  deinit {
    unregisterAllHotKeys()
    if let handler = hotKeyEventHandler {
      RemoveEventHandler(handler)
    }
  }

  func notifyDeepLinkArrived() {
    DispatchQueue.main.async { [weak self] in
      self?.vpnChannel.invokeMethod("onDeepLink", arguments: nil)
    }
  }

  func notifyAppWillTerminate() {
    DispatchQueue.main.async { [weak self] in
      self?.vpnChannel.invokeMethod("onAppWillTerminate", arguments: nil)
    }
  }

  private func handleVpnCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPendingDeepLink":
      result(appDelegate?.takePendingDeepLink())
    case "confirmAppTerminate":
      appDelegate?.confirmTerminate()
      result(nil)
    case "getDeviceModel":
      result(Self.hardwareModel())
    case "getAppIcon":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            !path.isEmpty else {
        result(nil)
        return
      }
      DispatchQueue.global(qos: .utility).async {
        let pngBase64 = Self.renderAppIconBase64(path: path)
        DispatchQueue.main.async { result(pngBase64) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleHotkeyCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setGlobalHotkeys":
      guard let items = call.arguments as? [[String: Any]] else {
        result([String]())
        return
      }
      result(registerHotKeys(items))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleScreenCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capture":
      DispatchQueue.global(qos: .userInitiated).async {
        let path = Self.captureScreenPng()
        DispatchQueue.main.async {
          if let path = path {
            result(["path": path])
          } else {
            result(nil)
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func installHotKeyHandlerIfNeeded() {
    guard hotKeyEventHandler == nil else { return }
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let userData = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, eventRef, userData -> OSStatus in
        guard let eventRef = eventRef, let userData = userData else {
          return OSStatus(eventNotHandledErr)
        }
        var hotKeyId = EventHotKeyID()
        let status = GetEventParameter(
          eventRef,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyId
        )
        guard status == noErr else { return status }
        let bridge = Unmanaged<MacosPlatformBridge>.fromOpaque(userData).takeUnretainedValue()
        bridge.dispatchHotKey(id: hotKeyId.id)
        return noErr
      },
      1,
      &eventType,
      userData,
      &hotKeyEventHandler
    )
  }

  private func registerHotKeys(_ items: [[String: Any]]) -> [String] {
    unregisterAllHotKeys()
    if items.isEmpty { return [] }
    installHotKeyHandlerIfNeeded()

    var failed: [String] = []
    for item in items {
      guard let action = item["action"] as? String,
            let keyCode = item["keyCode"] as? Int,
            let modBits = item["modifiers"] as? Int else {
        continue
      }
      // Matches HotkeyBinding.windowsModifiers: alt=1, ctrl=2, shift=4, meta=8
      var carbonMods: UInt32 = 0
      if (modBits & 1) != 0 { carbonMods |= UInt32(optionKey) }
      if (modBits & 2) != 0 { carbonMods |= UInt32(controlKey) }
      if (modBits & 4) != 0 { carbonMods |= UInt32(shiftKey) }
      if (modBits & 8) != 0 { carbonMods |= UInt32(cmdKey) }

      let id = nextHotKeyId
      nextHotKeyId &+= 1
      let hotKeyId = EventHotKeyID(signature: Self.hotKeySignature, id: id)
      var ref: EventHotKeyRef?
      let status = RegisterEventHotKey(
        UInt32(keyCode),
        carbonMods,
        hotKeyId,
        GetApplicationEventTarget(),
        0,
        &ref
      )
      if status == noErr, let ref = ref {
        hotKeyRefs[id] = ref
        hotKeyActions[id] = action
      } else {
        failed.append(action)
      }
    }
    return failed
  }

  private func unregisterAllHotKeys() {
    for ref in hotKeyRefs.values {
      UnregisterEventHotKey(ref)
    }
    hotKeyRefs.removeAll()
    hotKeyActions.removeAll()
  }

  private func dispatchHotKey(id: UInt32) {
    guard let action = hotKeyActions[id] else { return }
    DispatchQueue.main.async { [weak self] in
      self?.hotkeyChannel.invokeMethod("onHotkeyPressed", arguments: ["action": action])
    }
  }

  private static func hardwareModel() -> String? {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else {
      return nil
    }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
      return nil
    }
    let model = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    return model.isEmpty ? nil : model
  }

  private static func renderAppIconBase64(path: String) -> String? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let icon = NSWorkspace.shared.icon(forFile: path)
    let size = 48
    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: size,
      pixelsHigh: size,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else {
      return nil
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(
      in: NSRect(x: 0, y: 0, width: size, height: size),
      from: .zero,
      operation: .copy,
      fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])?.base64EncodedString()
  }

  private static func captureScreenPng() -> String? {
    let tmpDir = FileManager.default.temporaryDirectory
    let fileUrl = tmpDir.appendingPathComponent("keqdroid-qr-\(UUID().uuidString).png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-t", "png", fileUrl.path]
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      try? FileManager.default.removeItem(at: fileUrl)
      return nil
    }
    guard process.terminationStatus == 0,
          FileManager.default.fileExists(atPath: fileUrl.path) else {
      try? FileManager.default.removeItem(at: fileUrl)
      return nil
    }
    return fileUrl.path
  }
}
