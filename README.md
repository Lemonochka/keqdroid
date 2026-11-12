# keqdroid

Proxy and VPN client for Android, Android TV, Windows and Linux, built on Xray-core and mihomo. keqdroid manages subscriptions, server configurations and traffic routing in a single application.

[![Release](https://img.shields.io/github/v/release/Lemonochka/keqdroid?label=release)](https://github.com/Lemonochka/keqdroid/releases)
[![Build](https://img.shields.io/github/actions/workflow/status/Lemonochka/keqdroid/ci.yml?branch=master&label=build)](https://github.com/Lemonochka/keqdroid/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)
[![Telegram](https://img.shields.io/badge/Telegram-chat-26A5E4?logo=telegram&logoColor=white)](https://t.me/keqdroid)

English | [Русский](README.ru.md)

keqdroid does not provide servers. It requires a subscription or a server configuration from a provider of your choice. You are responsible for complying with the laws of your country.

https://github.com/user-attachments/assets/e1f899dd-4f2c-4ca2-896c-1da64a3a5645

## Download

Builds are published on the [Releases](https://github.com/Lemonochka/keqdroid/releases) page.

| Platform | Package |
|----------|---------|
| Android 7.0 and later, Android TV | `keqdroid-<version>-android.apk` |
| Android 7.0 and later, 32-bit firmware | `keqdroid-<version>-armeabi-v7a-android.apk` |
| Windows x64 | `keqdroid-windows-x64-<version>-setup.exe` (installer) |
| Windows x64 | `keqdroid-windows-x64-<version>.zip` (portable) |
| Linux x86_64 | `.AppImage`, `.deb`, `.rpm`, `.tar.gz`, `PKGBUILD` |

Each release includes `SHA256SUMS` with the hash of every file and `SHA256SUMS.sig` with its signature. The built-in updater verifies both before installing an update.

## Features

**Servers and subscriptions**

- Subscriptions with scheduled updates, added by URL or from a provider panel through a `keqdroid://` link
- Servers added from links, files, the clipboard or a QR code
- Proxy chains through several servers in a set order
- Automatic server selection within a subscription, with servers that can be excluded from it
- Separate device identity for each subscription
- Follows a subscription to a new address when the provider moves it, and uses the provider's backup address when the main one is unavailable
- TCP, HTTP and ICMP latency tests and speed tests

**Routing**

- Routes that block a destination, send it directly, through the tunnel or through another server
- Destinations defined by domain, IP address, built-in list, or AdBlock or hosts list by URL
- Routes limited to selected applications, TCP or UDP, and ports
- Routing profiles per subscription, including profiles supplied by the provider
- Profiles shared as a link or QR code; Happ and Incy routing links are accepted
- Split tunneling by application on Android and by program on Windows and Linux
- Live list of connections with the rule applied to each one

**Application**

- Light and dark themes, color presets and Material You on Android
- Interface scale from 70% to 140%; adaptive layout for tablets and landscape
- Backup and restore of settings, servers and subscriptions
- Local proxy sharing over LAN
- Hotkeys for the main actions
- Signed updates from GitHub Releases
- English, Russian, German, Chinese and Persian

## Supported formats

| Protocol or format | Import | Core |
|--------------------|--------|------|
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
| WireGuard, AmneziaWG | `.conf` file; `wg://`, `awg://`, `wireguard://` | mihomo |
| Xray configuration | JSON file, paste or subscription | Xray |
| Clash or mihomo configuration | YAML file, paste or subscription | mihomo |

For servers that both cores support, the core is selected in Settings → About; the default is Xray. A server that uses a transport available in only one core runs on that core.

Clash and sing-box configurations are imported as individual servers. Subscriptions that supply a mihomo template with proxy groups keep those groups and run on mihomo.

A ready-made configuration keeps its own routing, DNS and outbounds. Inbounds and logging are managed by the application, and sections that act on the device rather than the connection are removed.

## Platforms

| Platform | Mode | Description | Privileges |
|----------|------|-------------|------------|
| Android | VPN | All device traffic goes through the tunnel | VPN permission on first connection |
| Android | Proxy | Local SOCKS and HTTP proxy on `127.0.0.1` | None |
| Windows | Proxy | System proxy | None |
| Windows | TUN | All traffic goes through a virtual adapter | Administrator |
| Linux | Proxy | System proxy on GNOME and KDE; manual setup elsewhere | None |
| Linux | TUN | All traffic goes through a virtual adapter | Root through `pkexec`, or Passwordless TUN in Settings → Advanced → Permissions |

**Android.** The connection can be controlled from the notification, the Quick Settings tile, a home screen widget and launcher shortcuts. Per-application routing and DNS interception require VPN mode. An active VPN session resumes after an application update or a device restart.

**Android TV.** The application is operated with a remote control. A subscription can be sent from keqdroid on a phone by scanning a QR code on the TV.

**Windows.** The installer places the application in Program Files and can remove it together with its data; the portable version runs from any folder. The application can start with the system, connect automatically and stay in the tray. Settings are stored in `%APPDATA%\com.keqdroid\keqdroid\` and are shared by both versions.

**Linux.** The application can start at login and connect automatically. On Arch Linux, install with `makepkg -si` using the `PKGBUILD` from the release.

## Getting started

1. Open **Subscriptions**, paste the subscription URL and select **Add & Fetch**.
2. Open **Servers** and select a server.
3. Press the connect button.

Routing, split tunneling, the connection mode and other options are available in **Settings**.

## Documentation

Detailed documentation is available at [kequinq.art/docs/keqdroid](https://kequinq.art/docs/keqdroid/en/):

- [Routing](https://kequinq.art/docs/keqdroid/en/routing) and [DNS](https://kequinq.art/docs/keqdroid/en/dns)
- [Connection modes and split tunneling](https://kequinq.art/docs/keqdroid/en/modes)
- [Xray or mihomo](https://kequinq.art/docs/keqdroid/en/xray-or-mihomo) and [mihomo groups](https://kequinq.art/docs/keqdroid/en/mihomo-groups)
- [Automatic server selection](https://kequinq.art/docs/keqdroid/en/auto) and [server checks](https://kequinq.art/docs/keqdroid/en/ping)
- For providers: [subscription headers](https://kequinq.art/docs/keqdroid/en/provider/headers) and [links](https://kequinq.art/docs/keqdroid/en/provider/links)

## Privacy

keqdroid has no servers of its own and collects no usage statistics. It connects to:

- **the subscriptions, servers and rule lists you add.** A subscription request carries a device ID, the OS name and version and the device model, which subscription panels use to limit devices. Turn it off in Settings → *Share device HWID*;
- **GitHub** (`api.github.com`, `github.com`): update checks when the app starts or comes back to the foreground, update downloads, and the full geo database on Android when you ask for it;
- **`www.cloudflare.com/cdn-cgi/trace`**, through the connected server, to show the country of the exit;
- **the latency test address** when servers are tested: `connectivitycheck.gstatic.com` by default, changeable in the settings; **`speed.cloudflare.com`** when you run a speed test.

On Android, crash reports go to Google Firebase Crashlytics: the error with links, keys and tokens cut out, the stack trace and the device, OS and app version that Crashlytics attaches. The Windows and Linux builds do not include Firebase.

## Code signing policy

Free code signing provided by [SignPath.io](https://signpath.io), certificate by [SignPath Foundation](https://signpath.org). Signing is being set up; until it is enabled, Windows builds are not signed.

- Committers and reviewers: [Lemonochka](https://github.com/Lemonochka)
- Approvers: [Lemonochka](https://github.com/Lemonochka)

Releases after 0.35.0 are built from this repository by [GitHub Actions](.github/workflows/release.yml). `gh attestation verify <file> --repo Lemonochka/keqdroid` confirms that a file came from that build. Signing covers `keqdroid.exe`; the bundled `xray.exe` and `mihomo.exe` are builds of the upstream Xray-core and mihomo.

## Security

Report vulnerabilities as described in [SECURITY.md](SECURITY.md).

## Building from source

```bash
flutter pub get
flutter build apk --debug        # Android
flutter build windows --release  # Windows
```

A release APK needs a signing key in `android/key.properties`. Prebuilt cores are included in the repository. Linux builds, rebuilding the cores, tests and the release process are described in [docs/BUILD.md](docs/BUILD.md).

## Community

Questions and discussion: [Telegram chat](https://t.me/keqdroid).

## License

keqdroid is licensed under [AGPL-3.0](LICENSE). The bundled cores keep their upstream licenses: Xray-core (MPL-2.0) and mihomo (GPL-3.0).
