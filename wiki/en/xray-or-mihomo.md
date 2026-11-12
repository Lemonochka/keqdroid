# Xray or mihomo

Servers in keqdroid run on one of two cores, Xray or mihomo. You pick the core in “Settings” → “About” → “Cores”, Xray is the default. The choice affects servers that both cores support. A server that only one core supports always runs on that core whatever you pick, and “About” says why.

## Why the choice sometimes has no effect

A core silently skips settings it doesn't know and doesn't report an error. For example, if you hand mihomo a VMess server on the XHTTP transport, which mihomo doesn't have for VMess, it connects without XHTTP. The server won't accept that connection, and from the outside it looks as if the server is down. That's why the app doesn't hand a server to a core that can't handle it.

| Server | Core |
|---|---|
| regular `vless://`, `vmess://`, `trojan://`, `ss://`, `hy2://`, `socks://` links | your choice |
| `tuic://`, `anytls://`, `ssr://`, `mierus://` | mihomo |
| Shadowsocks with a plugin or UDP-over-TCP | mihomo |
| VLESS and VMess on the HTTP/2 transport | mihomo, Xray no longer supports it |
| mKCP | Xray |
| VMess and Trojan on XHTTP | Xray |
| a link with finalmask (`fm=`, as 3X-UI produces) | Xray |
| ready-made Xray config | Xray |
| ready-made Clash or mihomo config | mihomo |
| WireGuard and AmneziaWG | mihomo |
| subscription with mihomo groups | mihomo, unless “Rules” is on in “Ignore from provider” |
| chain | the core that supports all its hops: with AmneziaWG it's mihomo, with mKCP it's Xray |

Neither core supports Hysteria v1 links. A Hysteria v1 node inside a Clash config does work, on mihomo. All formats and ways to add a server are listed on the [Subscriptions and servers](/en/servers#formats) page.

A server is pinged by the same core that will later connect it. Otherwise the ping could show a live server that you then can't connect to.

## How the cores differ

Routes, profiles, split tunneling, Fake IP and Auto work the same on both cores. The differences:

| | Xray | mihomo |
|---|---|---|
| provider groups, the “Groups” tab | no | yes, see [mihomo groups](/en/mihomo-groups) |
| traffic under the connect button | combined | can be counted separately for VPN and direct: “Appearance” → “VPN and direct traffic separately”, off by default |
| rule on the “Connections” screen | rule name, see [the table](/en/routing#which-rule-matched) | type and value, for example `DomainSuffix(vk.com)` |
| QUIC blocking on Vision servers | yes, see [QUIC](/en/routing#quic-on-vision-servers) | no |
| DNS over DoT (`tls://`) | no | yes |
