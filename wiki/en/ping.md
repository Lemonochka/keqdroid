# Server checks

The check method is chosen in settings: “Server ping” → “Ping method”. The methods measure different things, so their results can't be compared with each other.

<PingWhat />

| Method | What it measures | Green | Yellow |
|---|---|---|---|
| TCP ping | whether the server address responds | up to 80 ms | up to 150 ms |
| ICMP ping | whether the server address responds to a regular `ping` | up to 80 ms | up to 150 ms |
| HTTP via proxy | a request through the server to the test site and back | up to 600 ms | up to 1200 ms |
| Speed test | download speed through the server | from 25 Mbit/s | from 8 Mbit/s |

Anything worse is shown in red.

**TCP and ICMP** only check that the server address is reachable. They don't know whether the proxy itself works: a server with an expired subscription or a broken key still shows a good TCP ping. And many servers don't answer ICMP at all even though they work.

**HTTP ping** checks the whole server: the app connects to it the same way as for a real connection and opens the test site through it. The result includes the path to the server, from the server to the site and back, so it's several times higher than the TCP ping, and that's normal.

By default the request is sent twice and the second one counts, already without handshakes with the server. If you turn off “Measure on a warm connection”, the single request with all the handshakes counts, like opening a site for the first time.

The test site is chosen in “HTTP test URL”: Google (the default), Cloudflare, Microsoft or your own address.

**Speed test** downloads 2 MB from Cloudflare servers through the server.

## When the method changes by itself

- **In VPN mode**, while connected, TCP and ICMP are replaced by HTTP ping: through an active tunnel they would show the same 2–4 ms for every server.
- **Chains** always use HTTP ping, because TCP and ICMP only check the first hop.
- **Hysteria 2 and TUIC** get their UDP port checked instead of TCP. Hysteria 2 with obfuscation doesn't answer this check, so it always uses HTTP ping.
- **AmneziaWG** uses ICMP instead of TCP ping: it doesn't answer TCP or UDP checks.

## Ping and Auto

Auto checks servers with HTTP ping on its own schedule, whatever method is selected in settings, and picks a server based on recent measurements. Your manual checks go into the same history. More on the [Auto](/en/auto#server-score) page.
