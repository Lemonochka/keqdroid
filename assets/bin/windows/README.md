# Windows binaries

Put the official builds here before `flutter run` or a release build. They're
bundled at compile time, so they have to exist first.

| File | Used for |
|------|----------|
| `xray.exe` | Proxy and TUN (VLESS, VMess, …) |
| `sing-box.exe` | TUN — both xray TUN and AmneziaWG TUN |
| `wireproxy.exe` | the AmneziaWG core (wireproxy-awg) |
| `wintun.dll` | the TUN adapter sing-box uses |
| `geoip.dat` | optional, enables `geoip:ru` and similar routing rules (Proxy mode) |
| `geosite.dat` | optional, enables `geosite:…` rules (Proxy mode) |

Proxy mode runs `xray.exe` and points the Windows system proxy at it. TUN mode
chains `xray.exe` → local SOCKS → `sing-box.exe` and needs the app running as
administrator.

AmneziaWG runs through `wireproxy.exe` (wireproxy-awg, which embeds amneziawg-go).
Build it with `tool/build_amneziawg.ps1 -Windows`. There's no official Windows
release of wireproxy-awg, so it's built locally and unsigned — Defender
sometimes flags it as a PUA. The build script keeps the symbols (no `-s -w`),
which avoids most of that; if it still gets quarantined, add a Defender
exclusion for the repo folder.

`geoip.dat` and `geosite.dat` only matter in Proxy mode: xray loads them through
`XRAY_LOCATION_ASSET`. sing-box (TUN) uses its own `.db` format and ignores these
files, so geo rules don't apply there.

A missing binary just shows an error when you try to connect. If you'd rather not
bundle them, put the exes next to `keqdroid.exe` or on `PATH`.
