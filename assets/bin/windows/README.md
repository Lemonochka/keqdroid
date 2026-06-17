# Windows cores

Place official builds here **before** `flutter run` / build (files must exist at compile time to bundle):

| File | Role |
|------|------|
| `xray.exe` | Required for Proxy and TUN (VLESS, VMess, …) |
| `sing-box.exe` | Required for TUN (xray TUN and AmneziaWG TUN) |
| `wireproxy.exe` | AmneziaWG core (wireproxy-awg; embeds amneziawg-go → local SOCKS5/HTTP) |
| `wintun.dll` | Required for TUN (sing-box) |
| `geoip.dat` | Optional. Enables `geoip:ru` etc. in routing (xray / **Proxy** mode) |
| `geosite.dat` | Optional. Enables `geosite:category-…` in routing (xray / **Proxy** mode) |

**Proxy:** `xray.exe` + system proxy (HTTP + SOCKS ports from app settings).

**TUN:** `xray.exe` → local SOCKS → `sing-box.exe` (run app as **Administrator**).

AmneziaWG uses `wireproxy.exe` (userspace, embeds amneziawg-go) as its core in both modes:

**AmneziaWG (Proxy):** `wireproxy.exe` exposes a local SOCKS5/HTTP proxy wired to the Windows
system proxy. **No admin rights**, but only proxies apps that honor the system proxy.

**AmneziaWG (TUN):** `wireproxy.exe` (local SOCKS5) → `sing-box.exe` TUN — same pipeline as
xray TUN, so routing / split-tunnel / kill-switch / traffic stats all apply. Run app as **Administrator**.

Place `wintun.dll` (amd64) in this folder (next to `sing-box.exe`).

Build the AmneziaWG core: `powershell -File tool/build_amneziawg.ps1` (see repo root).

`geoip.dat` / `geosite.dat` are passed to xray via `XRAY_LOCATION_ASSET`, so `geoip:`/`geosite:` rules work in **Proxy** mode. sing-box (**TUN**) uses a different `.db` format and does **not** read these `.dat` files, so geo rules are ignored in TUN.

If binaries are missing, connect shows an error in the UI.

Alternatives without bundling: copy `xray.exe` / `sing-box.exe` (and `wintun.dll`) next to `keqdroid.exe`, or add them to `PATH`.
