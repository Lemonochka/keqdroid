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
| Live speed / session stats | EventChannel from VpnService | TUN: virtual adapter counters; Proxy: Xray StatsService API |
| App updates | GitHub `v*` release (`.apk` asset) | Same `v*` release; portable `.zip` is applied in-place (extract + replace + restart) |
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
- **Traffic stats in Proxy mode:** Xray inbound counters via StatsService (`127.0.0.1:10985`).

## Windows desktop shell

- **System tray:** closing the window hides to tray; left-click (or double-click) restores the main window; right-click opens a themed Flutter menu (connect/disconnect, server list, Proxy/TUN, open app, exit).
- Tray icon appears after the first minimize-to-tray (close button).
- TUN from tray without admin rights opens the full app with the same restart-as-administrator dialog as the sidebar.

## Planned (not in code yet)

- Autostart, MSI/MSIX in-app installer
- Windows toast for subscription refresh results
- Tray tooltip reflects VPN connected state
