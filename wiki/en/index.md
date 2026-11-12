# keqdroid

These pages explain how keqdroid works and why it behaves the way it does. A short overview and the feature list are in the [README](https://github.com/Lemonochka/keqdroid#readme), builds are on the [Releases](https://github.com/Lemonochka/keqdroid/releases) page.

The app runs one of two cores, [Xray-core](https://github.com/XTLS/Xray-core) or [mihomo](https://wiki.metacubex.one/), and writes the config for it itself.

| Section | What it covers |
|---|---|
| [Subscriptions and servers](/en/servers) | adding and updating subscriptions, supported server formats, ready-made configs, chains |
| [Platforms](/en/platforms) | Android, Android TV, Windows and Linux: controls, permissions, tray, autostart, backup |
| [Updates and release signing](/en/updates) | when the app looks for a new version, how it checks the signature and installs the update |
| [Routing](/en/routing) | the order routes are checked in, how to write sites, how to see which rule matched |
| [DNS](/en/dns) | who answers DNS queries, custom servers, Fake IP, leak tests |
| [Modes and split tunneling](/en/modes) | VPN and Proxy, which apps go into the tunnel, sharing the proxy on your local network |
| [Xray or mihomo](/en/xray-or-mihomo) | which core runs a server and why the setting sometimes has no effect |
| [mihomo groups](/en/mihomo-groups) | subscriptions with provider groups and how they work with your routes |
| [Auto](/en/auto) | how the server score works, when Auto switches and when it switches back |
| [Server checks](/en/ping) | what TCP, ICMP, HTTP ping and the speed test measure |
| [Core patches](/en/cores) | what was changed in Xray and mihomo and why |
| [Subscription headers](/en/provider/headers) | what the app sends to the panel and which headers it reads |
| [Links](/en/provider/links) | the “Add to keqdroid” button, server links and routing profile links |
