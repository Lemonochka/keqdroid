# Links

Links that open keqdroid and add something to it: the “Add to keqdroid” button on a subscription page, a server link, a routing profile.

| Platform | Which links it opens |
|---|---|
| Android | `keqdroid://`, `keqdis://`, and also `vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`, `hy2://` |
| Windows | `keqdroid://`, `keqdis://` |
| Linux | none, paste the link into the app manually |

You can also simply paste any of these links into the app: the add button on the servers screen understands the same formats.

## Add a subscription

```
keqdroid://add?url=https%3A%2F%2Fsub.example.com%2Fabc
```

Only the `url` parameter matters: instead of `add` you can use `install-config`, `subscribe` or anything else, and `keqdis://` works the same as `keqdroid://`. The subscription address in `url` must be encoded (`encodeURIComponent`), otherwise an `&` in it cuts the link short.

The subscription address must use `https`, a subscription over `http` won't load, see [Subscription headers](/en/provider/headers#subscription-address).

After the tap, the subscription is added under the host name and downloaded right away. If the panel sends `profile-title`, the name is replaced with it. If the download fails, the subscription isn't kept in the list. If a subscription with that address already exists, it isn't added again.

## Server

A server link (`vless://…`, `vmess://…` and others) adds a single server outside any subscription. On Android such links open with a tap, on other platforms paste them manually.

## Routing profile

```
keqdroid://routing/add/<base64 JSON>
```

The format is the same as in Happ and Incy, so `happ://routing/add/…` and `incy://routing/add/…` are accepted too when pasted into the app. `onadd` works instead of `add`, no difference. The JSON looks like this:

```json
{
  "Name": "My profile",
  "GlobalProxy": "true",
  "BlockSites": ["geosite:category-ads-all"],
  "BlockIp": [],
  "DirectSites": ["geosite:category-ru", "vk.com"],
  "DirectIp": ["10.0.0.0/8"],
  "ProxySites": ["youtube.com"],
  "ProxyIp": []
}
```

| Key | What it is |
|---|---|
| `Name` | profile name |
| `GlobalProxy` | `"true"`: “Everything else” via VPN, `"false"`: direct |
| `BlockSites`, `BlockIp` | the “Block” route |
| `DirectSites`, `DirectIp` | the “Direct” route |
| `ProxySites`, `ProxyIp` | the “Via VPN” route |

Entries are written the same way as in routes, see [How to write sites and addresses](/en/routing#how-to-write-sites-and-addresses). `keyword:word` is supported too, while `ext:` entries and list links are skipped. The other Happ profile keys (DNS, geo databases, FakeDNS, `DomainStrategy`, `RouteOrder`) aren't carried over: in keqdroid these are global app settings, and route order works its own way.

A profile from such a link is added as your own: you can edit it and attach it to subscriptions on the routing screen. A profile the provider sends with the subscription works differently, see [Routing in headers](/en/provider/headers#routing).

### Share your profile

Your own profile, including “Main”, can be shared with the same kind of link or a QR code. The link leaves out what this format can't express:

- per-app routes;
- routes through another server;
- routes with a protocol or port, otherwise a QUIC block for YouTube would turn into a block of all of YouTube;
- lists by link;
- your custom route order: the recipient's routes are placed by target;
- “Everything else” set to block, because `GlobalProxy` only knows “via VPN” and “direct”.

When sharing, the app tells you how many routes didn't make it into the link.
