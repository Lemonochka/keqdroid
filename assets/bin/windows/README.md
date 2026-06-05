# Windows cores

Place official builds here **before** `flutter run` / build (files must exist at compile time to bundle):

| File | Role |
|------|------|
| `xray.exe` | Required for Proxy and TUN |
| `sing-box.exe` | Required for TUN only |

**Proxy:** `xray.exe` + system proxy (HTTP + SOCKS ports from app settings).

**TUN:** `xray.exe` → local SOCKS → `sing-box.exe` (run app as **Administrator**).

Place `wintun.dll` (amd64) in the same folder as `sing-box.exe` if TUN fails to start.

If binaries are missing, connect shows an error in the UI.

Alternatives without bundling: copy `xray.exe` / `sing-box.exe` (and `wintun.dll`) next to `keqdroid.exe`, or add them to `PATH`.
