# Android vs Windows

How the two platforms compare, feature by feature.

| Feature | Android | Windows |
|---------|---------|---------|
| VPN connect | TUN (VpnService + Xray + tun2socks) | Proxy by default (Xray + system proxy); TUN is Xray → sing-box |
| Split tunneling | per app (packages) | per process (TUN only) |
| TCP / UDP ping | yes | yes |
| URL ping | native ephemeral Xray | Dart `EphemeralXrayPing` (xray.exe) |
| Xray debug logs | native buffer | session stdout/stderr export |
| Proxy debug logs | — | yes |
| Subscriptions | foreground + WorkManager | foreground + a timer while the app is open |
| Live speed / session stats | EventChannel from VpnService | TUN: adapter counters; Proxy: Xray StatsService API |
| App updates | GitHub `v*` release (`.apk`) | same release; the portable `.zip` is applied in place (extract, replace, restart) |
| Background VPN / notifications | yes | no — the desktop has no VpnService |
| System proxy | — | yes, plus the Firefox `user.js` helper |

## Only on Windows

- the Proxy / TUN connection mode UI
- system proxy and the Firefox helper
- the process list for split tunneling
- proxy debug logs
- a side-by-side server layout on wide windows

## Only on Android

- the VpnService permission flow
- package-based split tunneling
- tapping the notification to connect
- the foreground VPN notification
- the Quick Settings tile
- WorkManager refresh when the app is killed

## Where the platforms differ on purpose

- Split tunneling in Proxy mode on Windows isn't the same as Android's per-app
  VPN. Use TUN mode if you need that.
- Background refresh on Windows runs on a timer and when the app resumes, not
  while it's fully closed.
- Proxy-mode traffic stats come from Xray's StatsService on `127.0.0.1:10985`.

## The Windows desktop shell

- Closing the window hides it to the tray. Left-click (or double-click) the tray
  icon to bring it back; right-click opens a small themed menu — connect/
  disconnect, the server list, Proxy/TUN, open the app, exit.
- The tray icon shows up the first time you close to tray.
- Switching to TUN from the tray without admin rights opens the full app and
  shows the same "restart as administrator" dialog as the sidebar.

## Not done yet

- an MSI/MSIX installer instead of the in-place zip update
- a Windows toast with subscription-refresh results
- a tray tooltip that reflects the connected state
