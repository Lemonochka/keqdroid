# DNS

DNS tells programs which IP address a site has. In VPN mode the core answers programs' DNS queries, using the DNS servers from the app settings. The core needs addresses itself too: to check IP rules, connect to sites directly and find your server.

<DnsPath />

## Interception

In VPN mode the core intercepts all DNS queries from programs and answers them itself. In Proxy mode there's no interception: a program either resolves the address itself or passes the site name to the proxy, and then the core resolves it.

### Private DNS on Android

In “Automatic” mode Android checks whether the network's DNS server supports DoT, and if it does, switches to it. The core only intercepts plain DNS, so the app gives the system a DNS server inside the tunnel, where there is no DoT. Otherwise all system DNS would bypass the core, and the custom DNS servers from settings wouldn't work at all.

If a hostname is set in Private DNS, Android connects to it over DoT by itself, through the tunnel, like to any other site. Your custom DNS servers aren't used then, but domain routes still work: the core sees the site name in the connection itself.

## Where the core gets answers

By default it's DoH from Cloudflare and Google: `https://1.1.1.1/dns-query` and `https://8.8.8.8/dns-query`.

| “Everything else” | How the core's DNS queries go |
|---|---|
| via VPN | through your server; your ISP only sees the connection to the server |
| direct or blocked | straight from the device |

Xray asks servers one by one: if one doesn't answer within 2.5 s, it asks the next. System DNS comes last. Where the ISP blocks DoH, the core couldn't even find your server's address without it. mihomo asks all servers at once and takes the first answer.

::::: details What it looks like in the core config
For the routes from the example on the [Routing](/en/routing) page:

::: code-group

```json [Xray]
"dns": {
  "servers": [
    {"address": "localhost", "domains": ["domain:direct.example"], "skipFallback": true},
    {"address": "https://1.1.1.1/dns-query"},
    {"address": "https://8.8.8.8/dns-query"},
    {"address": "localhost"}
  ],
  "queryStrategy": "UseIPv4"
}
```

```yaml [mihomo]
dns:
  enable: true
  ipv6: false
  nameserver: [https://1.1.1.1/dns-query, https://8.8.8.8/dns-query]
  proxy-server-nameserver: [https://1.1.1.1/dns-query, https://8.8.8.8/dns-query]
  direct-nameserver: [https://1.1.1.1/dns-query, https://8.8.8.8/dns-query, 1.1.1.1, 8.8.8.8]
  respect-rules: true
```

:::

:::::

## Domains from “Direct”

A CDN hands out the node closest to whoever asks. If you resolve a “Direct” site through the VPN, you get a node near the server, even though the connection goes from home. So the addresses of domains from “Direct” are resolved directly as well.

**Xray.** This is the “Split resolver for direct domains” setting, on by default. Domains from “Direct” are resolved by system DNS, so names on your home or work network resolve too. If you set custom DNS servers, the first of them resolves these domains. This doesn't apply to a site whose route is [moved above](/en/routing#custom-order) “Direct”: its address is resolved like any other site's.

**mihomo.** Always does this. To make it work, plain DNS on the same addresses is added alongside DoH: some ISPs block DoH, and “Direct” sites used to open with a 5 second delay ([issue #9](https://github.com/Lemonochka/keqdroid/issues/9)). Plain DNS isn't used for other sites, because ISPs spoof the addresses of blocked domains in it.

## The address of your server

If your server is set by name, the core always resolves its address directly: there's no tunnel yet at that point.

## Custom DNS servers

One address per line, or several separated by commas.

| Entry | Xray | mihomo |
|---|---|---|
| `https://dns.example/dns-query` | DoH | DoH |
| `tls://1.1.1.1` | no | DoT |
| `quic://dns.example` | DoQ, always direct | DoQ |
| `9.9.9.9`, `udp://9.9.9.9` | plain DNS | plain DNS |
| `tcp://9.9.9.9` | plain DNS over TCP | plain DNS over TCP |
| `localhost` | system DNS | system DNS |
| `h2c://dns.example/dns-query` | DoH without TLS | no |
| `dhcp://en0` | no | DNS from network settings |
| `https+local://…` | direct, bypassing routes | direct, bypassing routes |

An entry the current core doesn't understand is skipped. Neither core understands `sdns://`.

## Custom addresses for domains

`hosts` entries are a name and an address separated by a space, one per line. The address can be IPv4 or IPv6. The “address name” order, as in a `hosts` file, works too. Instead of an address you can give another name.

```
nas.home 192.168.1.10, fd00::10
*.dev.example 10.0.0.5
old.example new.example
```

“Resolver for specific domains” sets which DNS server answers for a given domain:

```
home.lan 192.168.1.1
*.corp.example https://dns.corp.example/dns-query
```

In these two fields a plain name matches only the domain itself, subdomains need the `*.` mask. Routes work the other way round: there `vk.com` already includes subdomains.

## IPv4 and IPv6

| Strategy | Which addresses the core requests |
|---|---|
| `UseIPv4`, the default | IPv4 only |
| `UseIP` | IPv4 and IPv6 |
| `UseIPv6` | IPv6 only |

`PreferIPv4` and `PreferIPv6` exist only on Xray: the core resolves both kinds of addresses but connects over IPv4 (or IPv6) first, and over the other one only if the site has no such addresses. mihomo only has `UseIPv4` and `UseIP`, and on mihomo `UseIPv4` turns IPv6 off completely, not just in DNS.

## Fake IP

Normally a program waits for the core to find the site's real address, and when “Everything else” goes through the VPN, that's a query through the server. With Fake IP the core immediately answers with a stand-in address from `198.18.0.0/16` and remembers which site it gave it to. When the program connects to that address, the core sends the site name to the server, and the server looks up the real address. Opening a site for the first time gets faster by one round trip to the server.

- Works only in VPN mode.
- A stand-in address lives for 1 second, so it doesn't linger in the system cache after the VPN is turned off.
- Connectivity checks and local names always get the real address: `*.lan`, `*.local`, `*.home.arpa`, `localhost`, `connectivitycheck.gstatic.com`, `*.msftconnecttest.com`, `captive.apple.com`, `*.ntp.org` and similar. If the system got a stand-in address for a connectivity check, it would show “no internet” even though the VPN works.

## Leak tests show a different resolver

Tests like dnsleaktest show Google or Cloudflare even though the app is set to, say, Quad9. This is not a leak.

The core resolves the address with its own DNS to check routes, but sends the server the site name, not the address it found. The server resolves the address again with its own resolver, and that's what the test sees. Only the server's settings can change this.

Another common source of an unexpected resolver is DoH in the browser itself. Firefox uses Cloudflare by default, and the core doesn't see such queries as DNS.

## Ready-made config from the provider

If a ready-made Xray or Clash config has its own DNS, that DNS is used. The “DNS” item in “Ignore from provider” on the routing screen replaces it with the DNS from the app settings.
