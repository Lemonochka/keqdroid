# mihomo groups

Some panels (Remnawave, Marzban) send a ready-made mihomo config from the provider instead of a plain server list: servers, groups and rules. For example, it can have a “YouTube” group where you choose which country to open YouTube through, while everything else goes through your main server. These pages call such a config a template.

```yaml
proxy-groups:
  - name: Main
    type: select
    proxies: [Germany, Netherlands]
  - name: YouTube
    type: select
    proxies: [Netherlands, Germany, DIRECT]
rules:
  - GEOSITE,youtube,YouTube
  - MATCH,Main
```

## When the template is used

The template arrives if the panel serves the subscription in Clash or mihomo format. Remnawave, for instance, does this for mihomo-based clients. To get it, set such a client's User-Agent in “Device identity” in the subscription settings.

The app accepts the template if, besides the main group, it has at least one group with manual selection and no groups that mihomo doesn't support (for example, `relay`). Otherwise the subscription works as a regular server list.

Servers of a subscription with a template always run on mihomo, whichever core is selected in settings, because the template is written for it. A server you've edited by hand runs separately, without the template.

## What you see on screen

A subscription with a template gets a “Servers | Groups” switch next to the “Auto” button.

**The main group** is where everything goes that the template's rules don't catch. You pick its server with a normal tap in the server list. If the provider's main group picks a server by itself, the app turns it into a regular one: everything goes through the server you tapped.

If the main group also contains other groups, such as a shared pool or trial servers, it is shown first on the “Groups” tab, labeled “Everything not sent to other groups goes here”. The group selected in it carries all remaining traffic until you tap a server in the list again.

**Selectable groups** are shown as rows on the “Groups” tab. Tap a row to open a list: servers, “Direct”, “Block” and other groups. Your choice only changes the path for the sites the template's rules send to that group. If no rule leads to the group and it's only chosen inside another group, it's labeled “Works when chosen in …”.

**Groups that pick a server by themselves** (by ping, by availability or by load balancing) don't get rows of their own. In other groups' lists such an item is labeled “picks by itself”, and while connected, something like “now Germany”.

While the VPN is connected, you can open a group that picks by ping or availability: its servers are sorted from fastest to slowest. If you pick a server, it gets pinned, and the group shows something like “pinned Germany”. A pinned server stays as long as it responds; if it stops, the group picks another one by itself. “Automatically” removes the pin. The pin is remembered and restored on every connection. A load-balancing group can't have a pinned server.

Hidden groups and groups with nothing to choose from are not shown.

The choice is saved in the subscription. While the VPN is connected through a server from this subscription, the choice takes effect immediately, no reconnect needed. When a server from another subscription is connected, these groups don't apply, and the tab tells you so.

## The template and your routes

<GroupOrder />

| Step | What | Whose |
|---|---|---|
| 1 | service rules, server addresses direct | the app |
| 2 | template rules | the provider |
| 3 | your routes: Block, Direct, local network, Another server, Via VPN | you |
| 4 | the template's “everything else”, which is the main group | the provider |

What this means:

- if a site is both in the template's rules and in your routes, the template decides;
- your routes work for everything the template doesn't catch, and “Via VPN” leads to the server selected in the main group;
- your “Everything else” has no effect with a template, the main group takes its place.

To let your routes decide, turn on “Rules” in “Ignore from provider”. The template is then switched off, and the subscription's servers become regular separate servers on the core from settings.

## What the template does not control

The template runs almost exactly as sent, but the app always keeps some settings to itself:

- ports, TUN mode, local network sharing and anything that opens access to the core or touches the system;
- the operating mode: it's always rule-based, because in global mode the core would bypass both leak protection and split tunneling;
- site detection in connections: it comes from the app settings;
- rules the app has no databases for (`IP-ASN`, unknown `GEOSITE` codes): they're removed or replaced with similar ones, otherwise mihomo would refuse to start the whole config.

DNS is taken from the template if it has one, otherwise from the app settings.
