# Windows binaries

Put these here before `flutter run` or a release build. They're bundled at
compile time, so they have to exist first.

| File | Used for | In git? |
|------|----------|---------|
| `keqrnel.exe` | the unified core: Proxy and TUN for all xray protocols (VLESS, VMess, Trojan, SS, Hysteria2). Embeds xray + sing-box. | yes (committed) |
| `mihomo.exe` | the Clash core: ready-made Clash configs and plain links; in TUN mode it owns the wintun adapter itself | yes (committed) |
| `wireproxy.exe` | the AmneziaWG core (wireproxy-awg) | no — place manually |
| `wintun.dll` | the Windows TUN adapter; loaded at runtime by sing-tun — which is what BOTH keqrnel and mihomo build on | no — place manually |
| `geoip.dat` | optional, enables `geoip:…` routing rules (xray side) | yes |
| `geosite.dat` | optional, enables `geosite:…` rules (xray side) | yes |

`keqrnel.exe` replaced the old `xray.exe` + `sing-box.exe` pair — one process now
does both the protocol stack (xray) and the TUN (sing-box). Proxy mode runs
keqrnel with a local SOCKS/HTTP inbound and points the Windows system proxy at
it; TUN mode runs keqrnel with a TUN inbound and needs the app as administrator
(plus `wintun.dll` next to keqrnel.exe).

Build `keqrnel.exe` from [Lemonochka/keqrnel](https://github.com/Lemonochka/keqrnel):

```sh
go build -trimpath -buildvcs=false -tags with_gvisor -o keqrnel.exe ./cmd/keqrnel
```

`with_gvisor` is not optional — the TUN stack is a user setting, and `gvisor` /
`mixed` (plus full-cone NAT) are missing from a build without that tag.

`mihomo.exe` is the second core, not a wrapper: which one runs a server is decided
by the server's **format** (Clash YAML → mihomo, Xray JSON → keqrnel, a plain link
→ whichever the user picked). In TUN mode mihomo creates the adapter itself, so it
needs the same two things as keqrnel: administrator rights and `wintun.dll` next to
the binary. Build it with `tool/build_mihomo.ps1 -Target windows` — a patched build,
see `tool/patches/`; it is deliberately left unstripped, like wireproxy, to keep
Defender calm.

AmneziaWG still runs through `wireproxy.exe` (wireproxy-awg, embeds amneziawg-go);
keqrnel wraps its local SOCKS into the TUN. Build wireproxy with
`tool/build_amneziawg.ps1 -Windows`. There's no official Windows release, so it's
built locally and unsigned — Defender sometimes flags it as a PUA; the build
keeps symbols to avoid most of that, else add a Defender exclusion for the repo.

`wintun.dll` is the official Wintun library (wintun.net); it's also bundled in
sing-box Windows releases. Without it, TUN mode can't create the adapter.

A missing binary just shows an error when you try to connect. If you'd rather not
bundle them, put the files next to `keqdroid.exe` or on `PATH`.
