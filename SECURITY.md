# Security policy

keqdroid is a VPN client: a flaw in it can expose a user's traffic, IP address or device. Vulnerability reports take priority over all other work.

## Supported versions

Only the latest release gets security fixes. Older versions get no backports; the built-in updater offers the fixed release.

## Reporting a vulnerability

Don't report a vulnerability in a public issue, pull request or the Telegram chat.

Report it privately: **Security** tab → **[Report a vulnerability](https://github.com/Lemonochka/keqdroid/security/advisories/new)**. If GitHub doesn't work for you, write to lenorakirechaeva@gmail.com. Russian or English, whichever is easier.

A useful report includes:

- the app version and platform;
- what an attacker can do and under which conditions;
- steps to reproduce or a proof of concept;
- logs or configurations, with subscription links, UUIDs, passwords and keys removed.

## What happens next

- You get a reply within 7 days.
- A confirmed vulnerability is fixed in a new release. Details stay private until that release is out.
- After the release, a security advisory is published under [Security → Advisories](https://github.com/Lemonochka/keqdroid/security/advisories), with a CVE where it applies.
- You are credited in the advisory unless you prefer to stay anonymous.

Research done in good faith is welcome: test on your own devices, accounts and servers, don't access other people's data and don't disrupt services.

## Scope

In scope:

- traffic, DNS queries or the IP address leaving past the tunnel while the app shows it is connected;
- the keqdroid service that runs TUN on Windows as LocalSystem, and the passwordless TUN helper with its polkit rule on Linux;
- the updater and the check of release signatures;
- subscriptions, links, `keqdroid://` links, ready-made configurations and routing profiles that make the app or a core do more than route traffic: open ports, read or write files, reach the local network;
- access to the local proxy or the core from other apps or devices when LAN Proxy is off;
- encrypted backups and their transfer to another device;
- installers and packages: file permissions and install paths;
- the patches keqdroid applies to the cores (`tool/patches/`).

Out of scope:

- bugs in Xray-core or mihomo that don't depend on how keqdroid configures or ships them. Report those to the Xray-core or mihomo project;
- servers and subscription panels of VPN providers;
- attacks that need root, malware already on the device or physical access to an unlocked device;
- unofficial builds and forks;
- scanner output without a demonstrated impact.

## Verifying releases

Download keqdroid only from the [Releases](https://github.com/Lemonochka/keqdroid/releases) page. Every release includes `SHA256SUMS` with the hash of every file and `SHA256SUMS.sig`, its Ed25519 signature. The updater installs nothing without a valid signature; the public keys are in [`lib/services/release_signature.dart`](lib/services/release_signature.dart). Releases after 0.35.0 are built by GitHub Actions, and `gh attestation verify <file> --repo Lemonochka/keqdroid` confirms that a file came from that build.
