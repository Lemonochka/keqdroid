# Subscriptions and servers

Servers get into the app in two ways: through a subscription from your provider, which updates itself, or manually with a link, a file or a QR code.

## Subscriptions

### How to add

- On the “Subscriptions” tab, tap +, paste the subscription address and tap “Add & Fetch”.
- Tap the “Add to keqdroid” button on your provider's page, see [Links](/en/provider/links#add-a-subscription).
- On Android, scan a QR code with the subscription address: “Scan QR code” in the add menu.
- On a computer, press Ctrl+V on the “Subscriptions” tab to add the address from the clipboard.

Subscriptions are only downloaded over `https`, because they contain the server keys. A subscription with an `http` address is not updated, and its card shows a “Switch to https” button.

### Updates

By default a subscription updates every 12 hours. If the provider sets its own interval, that one is used on the first download, see [Subscription headers](/en/provider/headers#subscription-card). To change the interval, tap the clock badge on the subscription card: you can pick anything from an hour to 3 days, or “Do not update automatically”.

| Platform | How often the app checks whether a subscription is due |
|---|---|
| Android | about once an hour in the background, even when the app is closed; the system decides the exact time |
| Windows, Linux | once an hour while the app is running (including when it sits in the tray), plus 2 minutes after launch and whenever you come back to the window |

When the VPN is on, the subscription is downloaded through the server. On Android a background update can show a notification with the number of servers. Turn it on in “Behaviour” → “Subscription update notifications”.

On update, servers that are still in the subscription keep their name, pin, ping results and Auto mark. If the provider changed a server's address or key, the app still recognizes it by name and protocol, as long as only one server in the subscription has that name.

### Removing

Removing a subscription also removes all its servers.

## Adding servers manually

The add menu on the “Servers” tab has these items:

| Item | What you can add |
|---|---|
| “Paste link(s)” | server links, one per line, or a whole Xray, Clash, sing-box or AmneziaWG config |
| “Import file” | a file with links or a config |
| “Scan QR code” (Android) | a server link, a subscription or a routing profile |
| “Receive from phone” (Android TV) | a subscription from your phone, see [Platforms](/en/platforms#android-tv) |

On a computer, Ctrl+V on the “Servers” tab adds links from the clipboard. On Android, just tap a `vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://` or `hy2://` link and it opens in the app.

Servers you add manually go into the “Manual servers” group.

## Formats

| Protocol or format | How to add | Core |
|---|---|---|
| VLESS | `vless://` | Xray, mihomo |
| VMess | `vmess://` | Xray, mihomo |
| Trojan | `trojan://` | Xray, mihomo |
| Shadowsocks | `ss://` | Xray, mihomo |
| Hysteria 2 | `hysteria2://`, `hy2://` | Xray, mihomo |
| SOCKS5 | `socks://`, `socks5://`, `socks5h://` | Xray, mihomo |
| ShadowsocksR | `ssr://` | mihomo |
| TUIC | `tuic://` | mihomo |
| AnyTLS | `anytls://` | mihomo |
| Mieru | `mierus://` | mihomo |
| WireGuard, AmneziaWG | `.conf` file, `wg://`, `awg://`, `wireguard://` links | mihomo |
| Xray config | JSON: file, paste or subscription | Xray |
| Clash or mihomo config | YAML: file, paste or subscription | mihomo |
| sing-box config | JSON: file, paste or subscription | depends on the server |

Hysteria v1 links are not supported. A Hysteria v1 node inside a Clash config does work, through mihomo.

Which core connects a server that both cores support is explained on the [Xray or mihomo](/en/xray-or-mihomo) page.

## Ready-made configs

### Clash and sing-box

A Clash or sing-box config is split into separate servers, one per node, wherever it came from. If a node can't be written as a link (WireGuard and AmneziaWG, MASQUE, Snell, SSH) or has settings that links don't carry (`ss-opts`, `smux`, a `dialer-proxy` chain, shadow-tls), it still becomes a separate server and runs on mihomo as is.

A Clash config that can't be split (nodes from `proxy-providers`, unknown node types) is added as a single server and also runs on mihomo as is. A subscription with mihomo groups works differently, see [mihomo groups](/en/mihomo-groups).

### Xray

A ready-made Xray config becomes one server, and a list of configs gives one server per config. Such a server runs with its own routing, its own DNS and its own outbound chains. The server name comes from the `remarks` field at the top level of the config.

The app always sets up the core's inbounds and log itself. The log path from the config is ignored, because it would let the core write to any file on the device. On top of that, everything that acts on the device itself rather than on the connection to the server is removed from the config:

| Removed | Why it's risky |
|---|---|
| `api`, `metrics` | open ports on the device |
| `env` | changes the core's environment |
| `geodata` | overwrites geo database files on a schedule |
| `reverse`, `reverse` on a VLESS outbound | lets the server open connections into your local network |
| `script` in routing | can run programs on the device |
| `webhook` on rules | sends connection details to an outside address |

Your routes apply to whatever the config's own rules didn't catch. How the “Rules” and “DNS” items in “Ignore from provider” change this is covered in [Routing](/en/routing#ready-made-config-from-the-provider) and [DNS](/en/dns#ready-made-config-from-the-provider).

## Chains

A chain sends traffic through several servers in turn: your device connects to the first, the first to the second, and the last one goes out to the internet. The “Build a chain” item appears in the add menu once the list has at least two servers that can be chained.

- A chain has 2 to 8 nodes.
- A chain is run by the core that supports all of its nodes: with AmneziaWG that's mihomo, with mKCP it's Xray. When you pick a node, the list shows the servers that the core selected in settings can chain.
- If you delete a server that is part of a chain, the chain keeps working from a saved copy of its settings.
- A chain is always pinged over HTTP, because TCP and ICMP only reach the first node.

## Server for a route

The “Another server” route sends chosen sites through another server from your list without changing your main server. These servers can be used for it:

| Server | On Xray | On mihomo |
|---|---|---|
| link | if Xray supports it | if mihomo supports it |
| WireGuard, AmneziaWG | no | yes |
| chain | no | yes, if mihomo supports all its nodes |
| Xray config | yes, its main outbound | no |
| Clash config | no | yes, its first group, or its first node if there are no groups |

From a ready-made config, only the outbounds and everything they connect through go into the route. That config's rules and DNS don't apply inside another connection. A Clash config can't be a route server if its groups take nodes from `proxy-providers` or via `include-all`, or filter them by name with `exclude-filter`.

## Editing and order

“Edit configuration” opens the server's settings, either as fields or as text. The editor warns you about settings the core will refuse to work with: Vision not over TCP with TLS or REALITY, REALITY without a public key or on an unsuitable transport, an unknown flow. It also warns that the core will only let VLESS without TLS, REALITY or Encryption into the local network.

- If you edit a server from a subscription, your edit survives updates: updates no longer touch or remove that server, even if the provider drops it. “Restore subscription config” undoes the edit.
- “Rename” changes the name only in the app, “Reset” brings back the original.
- “Pin server” moves it to the top of the list. Pinned servers stay on top with any sorting, in the order you pinned them.

Servers can be sorted by default (subscription order), by ping, by speed or by name.
