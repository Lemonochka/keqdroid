# Linux core binaries

Place the Linux (`x86_64` / ELF) core binaries here **before building** the Linux
desktop app. They are **not** Flutter assets — `linux/CMakeLists.txt` installs them
next to the `keqdroid` executable, and `LinuxCorePaths` resolves them there at
runtime. (As Flutter assets they would be bundled into every platform, including the
Android APK.)

| File | Source | In git? |
|------|--------|---------|
| `keqrnel` | the unified core: proxy and TUN for all xray protocols. Embeds xray + sing-box. | yes (committed) |
| `wireproxy` | the AmneziaWG core (wireproxy-awg) | yes |
| `geoip.dat` | enables `geoip:…` routing rules | yes |
| `geosite.dat` | enables `geosite:…` rules | yes |

`keqrnel` is the only engine the Linux backend ever launches — proxy, TUN and the
traffic counters all go through it. Standalone `xray` and `sing-box` used to sit here
too; nothing executed them, CMake stopped installing them, and they are gone.

Proxy mode runs keqrnel with a local SOCKS/HTTP inbound and needs no privileges; TUN
mode runs it with a TUN inbound and asks for root via `pkexec` at connect time.

## Building keqrnel

Source: [Lemonochka/keqrnel](https://github.com/Lemonochka/keqrnel). From a checkout
of that repository:

```sh
GOOS=linux GOARCH=amd64 go build -trimpath -buildvcs=false -tags with_gvisor \
  -o keqrnel ./cmd/keqrnel
```

`with_gvisor` is required: the TUN stack is a user setting, and `gvisor` / `mixed`
(and with them full-cone NAT) do not exist in a build without that tag.

`wireproxy` comes from `artem-russkikh/wireproxy-awg` (`wireproxy_linux_amd64`,
checksum-verified). `geoip.dat` / `geosite.dat` are copied from
`assets/bin/windows/` so routing behaves identically on both platforms.
