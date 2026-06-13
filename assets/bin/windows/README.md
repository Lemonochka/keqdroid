# Windows cores

Place official builds here **before** `flutter run` / build (files must exist at compile time to bundle):

| File | Role |
|------|------|
| `xray.exe` | Required for Proxy and TUN (VLESS, VMess, …) |
| `sing-box.exe` | Required for TUN only |
| `kphttp-client.exe` | Required for **KpHTTP** servers (your rust-kp core) |
| `geoip.dat` | Optional. Enables `geoip:ru` etc. in routing (xray / **Proxy** mode) |
| `geosite.dat` | Optional. Enables `geosite:category-…` in routing (xray / **Proxy** mode) |

**Proxy:** `xray.exe` + system proxy (HTTP + SOCKS ports from app settings).

**TUN:** `xray.exe` or `kphttp-client.exe` → local SOCKS → `sing-box.exe` (run app as **Administrator**).

Build `kphttp-client.exe` from sibling project `rust-kp`:

```powershell
powershell -File tool/build_kphttp.ps1 -Windows
```

Place `wintun.dll` (amd64) in the same folder as `sing-box.exe` if TUN fails to start.

`geoip.dat` / `geosite.dat` are passed to xray via `XRAY_LOCATION_ASSET`, so `geoip:`/`geosite:` rules work in **Proxy** mode. sing-box (**TUN**) uses a different `.db` format and does **not** read these `.dat` files, so geo rules are ignored in TUN.

If binaries are missing, connect shows an error in the UI.

Alternatives without bundling: copy `xray.exe` / `sing-box.exe` (and `wintun.dll`) next to `keqdroid.exe`, or add them to `PATH`.
