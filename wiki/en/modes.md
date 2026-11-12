# Modes and split tunneling

## VPN and Proxy

| | VPN (called TUN on desktop) | Proxy |
|---|---|---|
| what goes through the server | all device traffic | only programs set to use the proxy |
| DNS interception | yes | no |
| per-app routes and split tunneling | work | don't work |
| Fake IP | works | doesn't work |
| what it needs | Android: VPN permission. Windows: admin rights. Linux: root | nothing |

In Proxy mode the app runs SOCKS on `127.0.0.1:2080` and HTTP on `127.0.0.1:2081`. On Windows it sets the system proxy itself, and browsers and most programs pick it up. On Linux the proxy is written into GNOME and KDE settings. Otherwise, set the address and port in the program manually.

In this mode the proxy has no password, because neither the system proxy nor the proxy field in Wi-Fi settings accepts one. Android is the exception: there the password is on by default and can be turned off in “About” → “Password for the local proxy”.

In VPN mode the same ports are open too, but protected by a password that changes on every connection. The app itself uses them: to update subscriptions, check for updates and look up the country for the flag. Other programs can't use them.

## Split tunneling

<SplitModes />

| Mode | What goes through the VPN |
|---|---|
| All apps | everything |
| Selected only | only the checked apps, the rest go direct |
| All except selected | everything except the checked apps |

Works only in VPN mode. The list is shared by all routing profiles.

**Android.** The system itself applies the list: an app left out of the VPN works as if the VPN were off. The “Add Russian apps to bypass” button checks the installed apps from a built-in list.

**Windows and Linux.** Here all traffic enters the tunnel, and the core then sends the programs that shouldn't be in it around the tunnel. You can specify a program by name (`chrome.exe`, `firefox`) or by full path. A name matches any program with that name, a path matches only that one. On Windows case doesn't matter, and the app adds `.exe` itself. In “All apps” mode, Tailscale, WireGuard and OpenVPN always bypass the tunnel so you don't end up with a tunnel inside a tunnel.

keqdroid itself is never in the VPN, otherwise its connections to the server would loop back into its own tunnel. Its requests go through the local password-protected proxy, so they still go through the server.

## Split tunneling or a per-app route

- Split tunneling decides whether an app enters the VPN at all.
- A per-app route decides where the traffic of an app that is already in the VPN goes: direct, through another server or blocked.

So a route for an app that split tunneling keeps out of the VPN has no effect. The app warns you about this on the route card.

## Sharing over the local network

The “LAN Proxy” setting opens the proxy to other devices on your network: SOCKS on port 1080 and HTTP on port 8080, optionally with a username and password. This way you can route, say, a TV or a set-top box that has no client of its own through the server.

Only devices from private networks can connect. Their traffic goes through the server entirely, your routes don't apply to it.
