# Linux core binaries

Place the Linux (`x86_64` / ELF) core binaries here **before building** the
Linux desktop app. They are bundled into `flutter_assets` and resolved by
`LinuxCorePaths` (extracted to a temp dir and `chmod +x`-ed at runtime).

Expected files:

| File         | Source |
|--------------|--------|
| `xray`       | Xray-core release for `linux-amd64` |
| `sing-box`   | sing-box release for `linux-amd64` (only needed once TUN mode lands) |
| `wireproxy`  | wireproxy-awg built for `linux/amd64` (AmneziaWG proxy mode) |
| `geoip.dat`  | Xray geoip data (optional, for `geoip:` routing rules) |
| `geosite.dat`| Xray geosite data (optional, for `geosite:` routing rules) |

Prebuilt sources used (x86_64):
- `xray` — Xray-core `Xray-linux-64.zip` (v26.x).
- `wireproxy` — `artem-russkikh/wireproxy-awg` release `wireproxy_linux_amd64` (checksum-verified).
- `sing-box` — `SagerNet/sing-box` `sing-box-*-linux-amd64`. **Must match the
  Windows version** (`assets/bin/windows/sing-box.exe`, currently 1.14.0-alpha.27)
  — the TUN config targets the 1.12+ DNS schema, and an older/newer line breaks
  name resolution ("tun up but nothing loads"). Check with `sing-box version`.
- `geoip.dat` / `geosite.dat` — copied from `assets/bin/windows/` so routing is identical across platforms.

> Proxy mode needs `xray` (and `wireproxy` for AmneziaWG profiles).
> TUN mode additionally needs `sing-box` and is launched with root via
> `pkexec` (polkit) at connect time.
