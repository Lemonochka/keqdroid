# Linux core binaries

Place the Linux (`x86_64` / ELF) core binaries here **before building** the Linux
desktop app. They are **not** Flutter assets — `linux/CMakeLists.txt` installs them
next to the `keqdroid` executable, and `LinuxCorePaths` resolves them there at
runtime. (As Flutter assets they would be bundled into every platform, including the
Android APK.)

| File | Source | In git? |
|------|--------|---------|
| `keqrnel` | the unified core: proxy and TUN for all xray protocols. Embeds xray + sing-box. | yes (committed) |
| `mihomo` | the Clash core: runs ready-made Clash configs and plain links; in TUN mode it owns the tun device itself | yes |
| `wireproxy` | the AmneziaWG core (wireproxy-awg) | yes |
| `geoip.dat` | enables `geoip:…` routing rules | yes |
| `geosite.dat` | enables `geosite:…` rules | yes |

Which core runs a server is decided by the server's **format**, not by a setting:
Clash YAML only mihomo can execute, an Xray JSON config only keqrnel; a plain link
is taken by whichever core the user picked. Standalone `xray` and `sing-box` used to
sit here too; nothing executed them, CMake stopped installing them, and they are gone.

Proxy mode runs the core with a local SOCKS/HTTP inbound and needs no privileges; TUN
mode asks for root via `pkexec` at connect time — keqrnel because of its sing-box TUN
inbound, mihomo because it creates the tun device itself.

## Building mihomo

`tool/build_mihomo.ps1 -Target linux` (runs on Windows, cross-compiles). It is NOT a
stock upstream build: `tool/patches/*.patch` are applied first, and the script fails
if any of them no longer applies.

## Building keqrnel

Source: [Lemonochka/keqrnel](https://github.com/Lemonochka/keqrnel). From a checkout
of that repository:

```sh
GOOS=linux GOARCH=amd64 go build -trimpath -buildvcs=false -tags with_gvisor \
  -o keqrnel ./cmd/keqrnel
```

`with_gvisor` is required: the TUN stack is a user setting, and `gvisor` / `mixed`
(and with them full-cone NAT) do not exist in a build without that tag.

## Building wireproxy

`tool/build_amneziawg.ps1` (runs on Windows, cross-compiles - pure Go, no CGO). The
same run produces `assets/bin/windows/wireproxy.exe` from the same pinned tag, and
that is deliberate: this file used to be a release download while Windows was built
from source, and the two ended up a protocol generation apart (AmneziaWG 2.0 against
3.1) with nothing in the app saying so. Which AmneziaWG generation a profile can use
is decided by this binary alone - the `.conf` reaches it verbatim.

`geoip.dat` / `geosite.dat` are copied from `assets/bin/windows/` so routing behaves
identically on both platforms.
