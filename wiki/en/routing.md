# Routing

Routes decide where each connection goes: through the VPN, direct, through another server, or nowhere. The core checks them from top to bottom, and the first one that fits wins.

| Where | What happens |
|---|---|
| Via VPN | through the server you are connected to |
| Direct | bypassing the VPN, the site sees your normal address |
| Another server | through another server from your list, see [which servers work](/en/servers#server-for-a-route) |
| Block | the connection is not opened |

## Order

<RouteOrder />

The order is the same on both cores. Routes within one row are checked in the order they appear on screen. Rows 4, 6 and 7 can be rearranged, see [Custom order](#custom-order).

1. **Blocking.** Comes first, so it applies even to apps that have their own route.
2. **Your server.** The address of your server, of chain hops and of servers used in “Another server” routes always goes direct. Otherwise the connection to the server would go through the server itself.
3. **Specific apps.** An app's sites and lists are checked first, then all of its traffic. The home network (router, printer) goes direct even earlier, so a rule like “all of this app's traffic through a server” doesn't affect it.
4. **Direct.** Unless you've changed the order, it's checked before “Via VPN”: if a site is in both routes, it goes direct.
5. **Local network.** Addresses like 192.168.x.x and 10.x.x.x always go direct, a route can't send them into the VPN.
6. **Another server.**
7. **Via VPN.**
8. **Everything else.** Catches everything that didn't fit above. Where it goes is up to you: through the VPN, direct or blocked.

A route with a protocol or port sits in the same row as a regular route with the same target.

### Custom order

In the “All apps” section you can press and hold a route and drag it up or down. After that the core checks the section's routes in the order they appear on screen, not by target. This way you can send one site through the VPN while the rest of its country goes direct: put the site's route above the country's route.

A new route still lands in place by its target: “Direct” higher, “Via VPN” lower. Blocking, specific apps and the local network stay where they are, and “Everything else” is always last. Each profile has its own order. It isn't included in a [profile link](/en/provider/links#share-your-profile).

::: details What it looks like in the core config
Take these routes as an example: “Block” `ads.example, geosite:category-ads-all`, “Direct” `direct.example, 10.10.0.0/16`, “Another server” `route.example, geoip:de`, “Via VPN” `proxy.example, geosite:google`, “Everything else” via VPN. The current server is `198.51.100.33`, the other server is `198.51.100.34`.

```json
"rules": [
  {"ip": ["169.254.0.0/16", "224.0.0.0/4", "255.255.255.255/32"], "outboundTag": "block", "ruleTag": "block-special"},
  {"port": "53", "network": "tcp,udp", "outboundTag": "dns-out", "ruleTag": "dns-out"},
  {"domain": ["full:www.cloudflare.com"], "outboundTag": "proxy", "ruleTag": "exit-ip-probe"},
  {"domain": ["domain:ads.example", "geosite:category-ads-all"], "outboundTag": "block", "ruleTag": "block-domains"},
  {"ip": ["198.51.100.33"], "outboundTag": "direct", "ruleTag": "server-ip"},
  {"ip": ["198.51.100.34"], "outboundTag": "direct", "ruleTag": "route-server-0"},
  {"domain": ["domain:direct.example"], "outboundTag": "direct", "ruleTag": "direct-domains"},
  {"ip": ["10.10.0.0/16", "10.0.0.0/8", "192.168.0.0/16", "…"], "outboundTag": "direct", "ruleTag": "direct-private"},
  {"domain": ["domain:route.example"], "outboundTag": "keq-srv-0", "ruleTag": "keq-srv-0-domains"},
  {"ip": ["geoip:de"], "outboundTag": "keq-srv-0", "ruleTag": "keq-srv-0-geoip"},
  {"domain": ["domain:proxy.example", "geosite:google"], "outboundTag": "proxy", "ruleTag": "proxy-domains"},
  {"ip": ["0.0.0.0/0", "::/0"], "outboundTag": "proxy", "ruleTag": "final"}
]
```

This is Xray. mihomo has the same steps in the same order, just written as `DOMAIN-SUFFIX,direct.example,DIRECT` and so on, with `MATCH` at the end.

The last rule is written as “any IP” rather than “any connection” because the example has a custom IP (`10.10.0.0/16`). Xray resolves the site's address and checks IP rules only if no rule matched by name, and an “any connection” rule would always match.
:::

## Name or IP

Name rules (`vk.com`, `geosite:`) compare the site's name, address rules (`1.2.3.4`, `10.0.0.0/8`, `geoip:`) compare its IP. Sometimes a program hands the core only the name, and an address rule has nothing to compare.

If your routes include custom IPs or subnets, the core resolves the site's address itself in that case, but only when no name rule matched. `geoip:` entries don't trigger this: otherwise checking the country would cost an extra DNS query for every connection. This behavior is controlled by the “Routing domain strategy” setting.

## How to write sites and addresses

Separate entries with commas, spaces or new lines.

| Entry | What it matches |
|---|---|
| `vk.com` | vk.com and all subdomains |
| `.vk.com`, `*.vk.com` | the same |
| `ru` | everything ending in .ru |
| `full:vk.com` | only vk.com, no subdomains |
| `regexp:…` | names matching a regular expression |
| `geosite:google` | a ready-made list of a service's domains |
| `1.2.3.4` | a single address |
| `10.0.0.0/8` | a subnet |
| `geoip:de` | a country's addresses |

`geosite` holds lists of services, not countries. For a country, use `geoip`.

Android ships with a trimmed country database: it only has the codes the built-in lists need (`private`, `ru`, `telegram`, `refilter` and the Iranian ones). To use any other country, like `geoip:de`, download the full database: “About” → “Download the full database”. Without it, such an entry is dropped before connecting, and the route screen shows the warning “Missing from the geo databases, will be ignored”.

### Lists by link

You can paste a link to an AdBlock or hosts list into the sites field. The app downloads it and refreshes it once a day, and a new version takes effect from the next connection.

From AdBlock lists, only whole-domain rules like `||example.com^` are used. Rules with paths, cosmetic rules and rules for specific sites are skipped. The core doesn't support them, and treating them as rules for the whole domain would block more than the list author intended.

## Built-in lists

| List | What's inside |
|---|---|
| Russian sites | `geosite:category-ru` |
| Iranian sites | `geosite:ir`, `geoip:ir` and Iranian CDNs |
| Ads & trackers | `geosite:category-ads-all` |
| Blocked in Russia (Re-filter) | `geosite:refilter`, `geoip:refilter` |
| Russian mobile whitelists | `geosite:ru-whitelist` |

“Russian sites” doesn't include `geoip:ru`. Cache servers of foreign services hosted at Russian ISPs also look Russian by address. With `geoip:ru`, such a service would go direct to its cache and stop opening wherever it's blocked. If a site you need isn't on the list, add it as a separate route.

## Which rule matched

The “Connections” screen shows which rule matched each connection. On mihomo that's the rule type and value, for example `DomainSuffix(vk.com)`. On Xray it's the rule name:

| Name | What it is |
|---|---|
| `block-domains`, `block-geoip`, `block-ips` | Block |
| `direct-domains`, `direct-geoip` | Direct |
| `direct-private` | local network and custom IPs from “Direct” |
| `keq-srv-N-…` | Another server, N is its number among route servers, counting from zero |
| `proxy-domains`, `proxy-geoip`, `proxy-ips` | Via VPN |
| `keq-app-N…` | a route for a specific app |
| `keq-proto-N…` | a route with a protocol or port |
| `server-…`, `chain-hop-N`, `route-server-N` | server addresses |
| `user-…` | your routes on top of a provider's ready-made config |
| `block-quic` | QUIC on a Vision server, see below |
| `exit-ip-probe` | the country lookup for the flag |
| `dns-out`, `tun-dns` | DNS |
| `outside-vpn` | an app outside the VPN tried to get through the tunnel, see [Core patches](/en/cores#apps-outside-the-vpn) |
| `tun-…` | split tunneling on desktop |
| no rule | Everything else |

## Profiles

Routes and “Everything else” live in a profile. The “Main” profile applies to every subscription that doesn't have its own. When connecting, the app uses the profile of the subscription the server was picked from. A subscription can have only one profile. If a profile is turned off, “Main” is used instead. Split tunneling is shared by all profiles.

A provider can send a profile along with the subscription. It works as sent: you can view it but not edit it. If you turn on “Rules” in “Ignore from provider”, new profiles from the provider stop coming, and the one you already have becomes yours.

## Ready-made config from the provider

A ready-made Xray or Clash config has its own rules, and they are checked first. Your routes apply to everything they don't catch. What the app keeps in such a config and what it removes is described on the [Subscriptions and servers](/en/servers#ready-made-configs) page.

The “Rules” item in “Ignore from provider” removes the config's rules that send sites direct or block them, along with its own “everything else”. Then your routes decide. How this works with a mihomo template with groups is described on the [mihomo groups](/en/mihomo-groups#the-template-and-your-routes) page.

## QUIC on Vision servers

If the server is connected over VLESS with Vision (`xtls-rprx-vision`) and “Everything else” goes through the VPN, the app blocks QUIC (UDP to port 443) on Xray. A Vision server doesn't let QUIC through anyway, but it only refuses after a full handshake, so the browser lost time on every attempt. With the block, the browser switches to a regular connection right away. The `xtls-rprx-vision-udp443` variant has no block, because there the server does let QUIC through.
