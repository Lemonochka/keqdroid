import Carbon.HIToolbox
import Cocoa
import FlutterMacOS
import Foundation
import ImageIO

final class MacosPlatformBridge {
  private static let hotKeySignature: OSType = 0x4B455144 // 'KEQD'
  private static let iconCache: NSCache<NSString, NSString> = {
    let cache = NSCache<NSString, NSString>()
    cache.countLimit = 256
    return cache
  }()

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

  func notifyOpenSettings() {
    DispatchQueue.main.async { [weak self] in
      self?.vpnChannel.invokeMethod("onOpenSettings", arguments: nil)
    }
  }

  func notifyAppWillTerminate(completion: @escaping (Bool) -> Void) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        completion(false)
        return
      }
      self.vpnChannel.invokeMethod("onAppWillTerminate", arguments: nil) { res in
        if res is FlutterError || (res as? NSObject) === FlutterMethodNotImplemented {
          completion(false)
        } else {
          completion(true)
        }
      }
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
      if let cached = Self.iconCache.object(forKey: path as NSString) {
        result(cached as String)
        return
      }
      // AppKit's NSWorkspace/NSImage must only be touched on the main thread;
      // extract an immutable CGImage here and encode PNG off the main thread.
      guard let cgImage = Self.loadAppIconCGImageOnMain(path: path) else {
        result(nil)
        return
      }
      DispatchQueue.global(qos: .utility).async {
        let pngBase64 = Self.encodeIconPngBase64(cgImage: cgImage)
        if let pngBase64 = pngBase64 {
          Self.iconCache.setObject(pngBase64 as NSString, forKey: path as NSString)
        }
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

  private static func loadAppIconCGImageOnMain(path: String) -> CGImage? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let icon = NSWorkspace.shared.icon(forFile: path)
    var rect = NSRect(x: 0, y: 0, width: 48, height: 48)
    return icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
  }

  private static func encodeIconPngBase64(cgImage: CGImage) -> String? {
    let size = 48
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
      return nil
    }
    ctx.interpolationQuality = .high
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let scaled = ctx.makeImage() else { return nil }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
      data,
      "public.png" as CFString,
      1,
      nil
    ) else {
      return nil
    }
    CGImageDestinationAddImage(dest, scaled, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return (data as Data).base64EncodedString()
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
