# Core patches

keqdroid ships two cores: [Xray-core](https://github.com/XTLS/Xray-core) 26.10.10 and [mihomo](https://wiki.metacubex.one/) 1.19.32. Both are built from source with patches: the official builds lack things the app relies on, and they have a few bugs that are fixed here. The patches themselves are in [`tool/patches/`](https://github.com/Lemonochka/keqdroid/tree/master/tool/patches).

The cores are built with current Go releases that fix known vulnerabilities in Go itself: mihomo with Go 1.26.10, Xray with Go 1.27.3.

| Patch | Core | Where | What it gives |
|---|---|---|---|
| [REALITY client version](#reality-client-version) | mihomo | everywhere | servers with a minimum client version no longer refuse the connection |
| [Firefox fingerprint](#firefox-fingerprint) | mihomo | everywhere | REALITY with `fp=firefox` works on updated servers |
| [who opened the connection](#who-opened-the-connection) | both | Android | per-app routes work |
| [package list](#package-list) | mihomo | Android | mihomo's TUN starts at all |
| [apps outside the VPN](#apps-outside-the-vpn) | both | Android | an excluded app can't learn the server address |
| [UDP by address](#udp-by-destination-address) | both | everywhere | UDP goes where the routes say |
| [TUN on desktop](#tun-on-desktop) | Xray | Windows, Linux | split tunneling, honest ping, clean shutdown |
| [TUN on Linux](#tun-on-linux) | both | Linux | TUN works with strict reverse path filtering, WebRTC doesn't reveal your address, servers on the computer answer people who connect from outside |
| [geo database memory](#geo-database-memory) | mihomo | everywhere | `geosite` and `geoip` rules use less memory |

## REALITY on mihomo

### REALITY client version

A REALITY client tells the server its version, and the server owner can set a minimum. mihomo always reports the same old version and doesn't let you change it. If the server's minimum is higher, the server refuses, and silently, as REALITY always does. The client says “REALITY authentication failed” even though the key and address are correct, while the same server works through Xray.

The patch reports the same version as the Xray bundled with the app. This version doesn't protect anything, it only tells the server which revision of the protocol the client understands, and mihomo does understand it.

### Firefox fingerprint

Since September 2026, new Xray versions on the server reject connections without a post-quantum key. mihomo's `fp=firefox` fingerprint is taken from an old Firefox that doesn't have that key yet. So as soon as a server owner updated Xray, all REALITY servers with `fp=firefox` stopped working on mihomo with the same “REALITY authentication failed” error. Chrome fingerprints do carry the key, but where the app is used, filters cut connections with a Chrome fingerprint.

The patch sets a fresh Firefox fingerprint, the same one Xray uses. It will be removed once mihomo updates the fingerprint itself.

## Android

### Who opened the connection

A per-app route only works if the core knows which app opened the connection. Since Android 10 the system doesn't tell regular programs this. The core found nothing, and no per-app route worked.

Only the app that owns the VPN can find out whose connection it is. So the core asks keqdroid, and keqdroid asks the system. Nobody else on the phone can use this channel.

Xray also got a fix for which connection to ask about. For sites the core identified by name, it asked by name, but the system only knows connections by address, so there was no answer.

### Package list

When starting TUN on Android, mihomo reads the list of installed apps. Since Android 11 regular apps aren't allowed to do that, and TUN didn't start even though the app showed “Connected”: the proxy worked, but not a single packet went through the tunnel.

mihomo only needs this list for its own split tunneling, and in keqdroid the system handles split tunneling. The patch skips reading the list when it isn't needed.

### Apps outside the VPN

An app that split tunneling took out of the VPN can still send data into the tunnel on its own: on Android this needs no special permissions. Its data then goes through your server, and the app learns the server's address. A banking app, for example, could notice the VPN this way.

The system knows about such connections and, asked about the owner, answers “not yours”. In that case keqdroid gives the owner a special name, and the first rule in the config rejects the connection.

Workarounds are closed too:

- the connection is rejected before it has a chance to open, otherwise the very fact that it opened would show the tunnel is working;
- through the tunnel's DNS such an app could ask which address the query came from and get the server's address. Now the core answers queries with no known owner only with site addresses;
- system DNS in “Selected only” mode also arrives without an owner, but the app recognizes it and lets it through, otherwise the selected apps would be left without DNS.

If keqdroid doesn't answer the core, the connection goes through: only what the system explicitly called someone else's is rejected.

## UDP by destination address

Both cores picked the UDP path once, by the first packet. If a game first contacted an address outside your routes, its voice chat kept going that way no matter where the route sent it. And if the first packet matched “Direct”, everything else bypassed the tunnel too.

With the “Route UDP by each destination address” setting, the path is chosen by your routes separately for each address. It's off by default: calls, games and torrents that connect to each other directly may stop doing so if the routes split them across different paths.

## TUN on desktop

TUN on Windows and Linux used to run on sing-box, now it's Xray's own TUN. What sing-box could do had to be added to Xray:

- **Split tunneling.** “Selected only” sends all other programs around the tunnel, and Xray had no way to say “any program except these”. On Windows program names are now compared case-insensitively, otherwise `winword` didn't match `WINWORD.EXE`. The “Connections” screen shows which program opened a connection.
- **Ping.** With TUN on, any address, even a nonexistent one, answered `ping` in about 1 ms, because the tunnel itself was answering. Now `ping` and `tracert` show the real network.
- **UDP timeout.** The “UDP timeout” setting in TUN closes idle UDP sessions. Xray didn't have this.
- **Shutdown.** On Windows the core stopped so abruptly that it didn't clean up after itself: traces of the tunnel stayed in network settings and the DNS cache. Now the core stops the same way as on Ctrl+C.
- **Traffic counters.** The app reads them from the core at a local address that any program on the computer can reach. Xray used to expose extra information about itself there, now only the counters.

## TUN on Linux

There are three patches here. The first is in Xray only, the other two are in both cores.

- **Strict reverse path filtering.** Xray put the route into the tunnel in Linux's main routing table. If the system has strict reverse path filtering on (`rp_filter=1`, often turned on for hardening), Linux dropped every reply from the server. By the main table, a reply to that address would go into the tunnel, but it arrived through the network card, so Linux took the packet for a forged one. The core started, but no traffic went through. Now the route lives in a table of its own that rules lead to, as in sing-box and mihomo. Along the way, a DNS query to any address goes into the tunnel, not only to the addresses in `/etc/resolv.conf`.
- **WebRTC.** A browser also sends WebRTC requests from the address of each network card. In mihomo such a request bypassed the tunnel, and the site saw your real address. Now in both cores everything a regular user's programs send goes into the tunnel.
- **Replies to connections from outside.** If a server runs on the computer and people connect to it from the internet, Sunshine for game streaming for example, then in Xray its replies went into the tunnel and never reached whoever connected. Now both cores mark replies to connections started from outside, and those replies leave the way the request came in. sing-box does the same. This needs nftables. Without it the core writes a warning to the log, and the replies still go into the tunnel. The exception is a UDP server that doesn't say which address to reply from: its replies go into the tunnel too. Sunshine does say it.

## Geo database memory

On the first `geosite` or `geoip` rule, mihomo kept a list in memory for good that no rule uses, and stored every loaded domain list in two copies. The patch removes both. With Russian sites, ads and `geoip:ru` the core uses about 2.5 MB less memory, with large lists about 5 MB. Routing is not affected.
