# Android ↔ Windows feature parity

## Parity matrix (user-facing)

| Feature | Android | Windows |
|---------|---------|---------|
| VPN connect | TUN (VpnService + Xray + tun2socks) | Proxy (default): Xray + system proxy; TUN: Xray → sing-box |
| Split tunneling | Per-app (packages) | Per-process (TUN only) |
| TCP / UDP ping | Yes | Yes |
| URL ping | Native ephemeral Xray | Dart `EphemeralXrayPing` (xray.exe) |
| Xray debug logs | Native buffer | Session stdout/stderr export |
| Proxy debug logs | — | Yes |
| Subscriptions | Foreground + WorkManager | Foreground + periodic timer while app runs |
| Live speed / session stats | EventChannel from VpnService | `getTrafficStats` (virtual TUN or loopback in Proxy) |
| App updates | GitHub `Android*` APK | GitHub `Desktop*` zip/msix (download or browser) |
| Notifications / background VPN | Yes | Not implemented (desktop has no VpnService) |
| System proxy | — | Yes (+ Firefox user.js) |

## Windows-only

- Connection mode Proxy / TUN UI
- System proxy + Firefox helper
- Process list for split tunnel
- Proxy debug logs
- Side-by-side servers layout on wide windows

## Android-only

- VpnService permission flow
- Package-based split tunnel
- Notification launch → connect
- Foreground VPN notification in service
- Quick Settings tile
- WorkManager when app is killed

## Intentional limitations

- **Split tunnel in Proxy mode (Windows):** not equivalent to Android per-app VPN; use **TUN** mode.
- **Background refresh on Windows:** runs on a timer and on app resume, not when the app is fully closed.
- **Traffic stats in Proxy mode:** based on loopback adapter counters (approximate).

## Windows desktop shell

- **System tray:** closing the window hides to tray; double-click tray icon or **Show KeqDroid** restores; **Exit** quits.
- Tray icon appears after the first minimize-to-tray (close button).

## Planned (not in code yet)

- Autostart, in-app MSI installer
- Windows toast for subscription refresh results
- Tray tooltip reflects VPN connected state
