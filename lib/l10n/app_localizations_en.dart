// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'KEQDIS';

  @override
  String vpnConnectedTo(Object serverName) {
    return 'Connected to: $serverName';
  }

  @override
  String get vpnConnecting => 'Connecting...';

  @override
  String get vpnDisconnecting => 'Disconnecting...';

  @override
  String vpnTapToConnect(Object serverName) {
    return 'Tap to connect to $serverName';
  }

  @override
  String get vpnSelectServer => 'Select a server below';

  @override
  String get vpnSelectServerFirst => 'Select a server first';

  @override
  String get updateTitle => 'Update Available';

  @override
  String get updateWhatsNew => 'What\'s new:';

  @override
  String get updateActionLater => 'Later';

  @override
  String get updateActionNow => 'Update';

  @override
  String get updateApplying => 'Applying update...';

  @override
  String get errorSubscriptionTitle => 'Subscription error';

  @override
  String get errorConnectionPermission => 'Connection failed: permission';

  @override
  String get errorConnectionNetwork => 'Connection failed: network';

  @override
  String get errorConnectionConfig => 'Connection failed: config';

  @override
  String get errorConnectionAuth => 'Connection failed: auth';

  @override
  String get errorConnectionGeneric => 'Connection error';

  @override
  String get errorProviderConfigTitle => 'Provider configuration required';

  @override
  String get errorProviderNoHostsMessage => 'Provider has no hosts assigned to this subscription.';

  @override
  String get errorProviderNoHostsAction => 'Open provider panel, add or assign hosts, then refresh subscription.';

  @override
  String errorActionLabel(Object action) {
    return 'Action: $action';
  }

  @override
  String get splitTunnelingTitle => 'Split Tunneling';

  @override
  String get splitModeAllApps => 'All apps';

  @override
  String get splitModeSelectedOnly => 'Selected only';

  @override
  String get splitModeAllExceptSelected => 'All except selected';

  @override
  String get splitSearchHint => 'Search apps...';

  @override
  String get splitNoAppsFound => 'No apps found';

  @override
  String splitFailedLoadApps(Object error) {
    return 'Failed to load apps: $error';
  }

  @override
  String splitSelectedAppsCount(int count) {
    return '$count app(s) selected';
  }

  @override
  String get splitHideSystemApps => 'Hide system apps';

  @override
  String get splitShowSystemApps => 'Show system apps';

  @override
  String get splitAddRussianAppsBypass => 'Add Russian apps to bypass';

  @override
  String get splitClear => 'Clear';

  @override
  String get splitNoRussianAppsFound => 'No Russian apps found in the installed apps list';

  @override
  String get splitRussianAppsAlreadyAdded => 'All Russian apps already in bypass list';

  @override
  String splitAddedRussianApps(int count) {
    return 'Added $count Russian app(s) to bypass list';
  }

  @override
  String get navServers => 'Servers';

  @override
  String get navSubscriptions => 'Subscriptions';

  @override
  String get navSettings => 'Settings';

  @override
  String get serversEmptyTitle => 'No servers yet';

  @override
  String get serversEmptyHint => 'Add a subscription in the Subscriptions tab';

  @override
  String get subscriptionsTitle => 'Subscriptions';

  @override
  String get subscriptionsAddButton => 'Add subscription';

  @override
  String get subscriptionsEmptyTitle => 'No subscriptions';

  @override
  String get subscriptionsEmptyHint => 'Tap + to add a subscription URL';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsThemeTitle => 'Appearance';

  @override
  String get settingsSplitTitle => 'Split Tunneling';

  @override
  String get settingsRoutingTitle => 'Routing Rules';

  @override
  String settingsSplitConfigured(int count) {
    return '$count apps configured';
  }

  @override
  String get settingsRoutingSubtitle => 'Direct / proxy / block rules and presets';

  @override
  String get settingsResetRoutingTitle => 'Reset routing to defaults';

  @override
  String get settingsRoutingResetDone => 'Routing rules reset';

  @override
  String get settingsRoutingHeaderDesc => 'Decide which sites go directly past the VPN, which are forced through it, and which are blocked. Use a preset for a quick start, then fine-tune each list below.';

  @override
  String get settingsRoutingPresetsTitle => 'Quick presets';

  @override
  String get settingsRoutingPresetsHint => 'Pick a curated list and add it to the matching list below. You can edit or remove entries afterwards.';

  @override
  String get settingsRoutingPresetChoose => 'Choose a preset…';

  @override
  String get settingsRoutingPresetAdd => 'Add';

  @override
  String get settingsRoutingPresetRuTitle => 'Russian sites — Direct';

  @override
  String get settingsRoutingPresetRuDesc => 'All .ru / .рф domains and major RU services bypass the VPN (adds domains to Direct)';

  @override
  String get settingsRoutingPresetRuGeoipTitle => 'Russia IPs (GeoIP) — Direct';

  @override
  String get settingsRoutingPresetRuGeoipDesc => 'All Russian IP ranges bypass the VPN via GeoIP — works in Proxy mode';

  @override
  String get settingsRoutingPresetRuGeositeTitle => 'Russia sites (GeoSite) — Direct';

  @override
  String get settingsRoutingPresetRuGeositeDesc => 'Russian domains from the GeoSite database bypass the VPN';

  @override
  String get settingsRoutingPresetBanksTitle => 'Banks & gov — Direct';

  @override
  String get settingsRoutingPresetBanksDesc => 'Banking, payments and state portals bypass the VPN';

  @override
  String get settingsRoutingPresetLanIpsTitle => 'Local network — Direct';

  @override
  String get settingsRoutingPresetLanIpsDesc => 'Private LAN IP ranges (192.168.x, 10.x, …) bypass the VPN';

  @override
  String get settingsRoutingPresetAdsTitle => 'Ads & trackers — Block';

  @override
  String get settingsRoutingPresetAdsDesc => 'Drop common ad / analytics hosts';

  @override
  String get settingsRoutingPresetAdsGeositeTitle => 'Ads (GeoSite) — Block';

  @override
  String get settingsRoutingPresetAdsGeositeDesc => 'Block a broad ad / tracker list from the GeoSite database';

  @override
  String get settingsRoutingPresetStreamingTitle => 'Streaming — Proxy';

  @override
  String get settingsRoutingPresetStreamingDesc => 'Force YouTube, Netflix, Twitch through the VPN';

  @override
  String get settingsRoutingPresetMessengersTitle => 'Messengers — Proxy';

  @override
  String get settingsRoutingPresetMessengersDesc => 'Force Telegram, Discord, WhatsApp through the VPN';

  @override
  String settingsRoutingPresetApplied(String name) {
    return 'Added \"$name\"';
  }

  @override
  String get settingsRoutingDirectTitle => 'Direct (bypass VPN)';

  @override
  String get settingsRoutingDirectDesc => 'Domains and IPs here connect directly, without the VPN.';

  @override
  String get settingsRoutingProxyTitle => 'Proxy (force VPN)';

  @override
  String get settingsRoutingProxyDesc => 'Domains and IPs here always go through the VPN.';

  @override
  String get settingsRoutingBlockTitle => 'Blocked';

  @override
  String get settingsRoutingBlockDesc => 'Domains and IPs here are dropped and never connect.';

  @override
  String get settingsRoutingSyntaxHint => 'Each list accepts domains and IPs together, comma- or line-separated:\n• ru — every *.ru host (a bare word = domain suffix)\n• vk.com — that domain and its subdomains\n• .example.com — subdomains only\n• 10.0.0.0/8 or 1.2.3.4 — IP address or CIDR range\n• geoip:ru / geosite:refilter — GeoIP/Geosite codes from the bundled databases\nPrivate/LAN IPs and your server always stay direct automatically.';

  @override
  String get settingsRoutingValuesHint => 'One per line, or comma separated';

  @override
  String get settingsRoutingFinalTitle => 'Unmatched traffic';

  @override
  String get settingsRoutingFinalDesc => 'Default action for traffic outside the rules.';

  @override
  String get settingsRoutingFinalProxy => 'Proxy';

  @override
  String get settingsRoutingFinalDirect => 'Bypass';

  @override
  String get settingsRoutingFinalBlock => 'Block';

  @override
  String get settingsRoutingAdvancedTitle => 'Custom rules';

  @override
  String get settingsRoutingAdvancedHint => 'Individual rules with their own on/off switch. Applied on top of the lists above.';

  @override
  String get settingsRoutingAdvancedEmpty => 'No custom rules yet';

  @override
  String get settingsRoutingAdvancedAdd => 'Add rule';

  @override
  String get settingsRoutingRuleNewTitle => 'New rule';

  @override
  String get settingsRoutingRuleEditTitle => 'Edit rule';

  @override
  String get settingsRoutingRuleName => 'Name';

  @override
  String get settingsRoutingRuleNameHint => 'e.g. Streaming';

  @override
  String get settingsRoutingRuleValues => 'Values';

  @override
  String get settingsRoutingRuleValuesHint => 'One per line or comma-separated';

  @override
  String get settingsRoutingRuleMatchBy => 'Match by';

  @override
  String get settingsRoutingRuleTypeDomain => 'Domain';

  @override
  String get settingsRoutingRuleTypeIp => 'IP / CIDR';

  @override
  String get settingsRoutingRuleTypeGeoip => 'GeoIP';

  @override
  String get settingsRoutingRuleTypeGeosite => 'GeoSite';

  @override
  String get settingsRoutingRuleAction => 'Action';

  @override
  String get settingsRoutingRuleSave => 'Save';

  @override
  String get settingsRoutingRuleDeleteConfirm => 'Delete this rule?';

  @override
  String get routingCheatSheetTitle => 'How to write rules';

  @override
  String get routingCheatSheetBody => 'Rules are just a list: what goes where. Each line is a domain, an IP, or a geo tag, and next to it the action — straight out (bypass), through the VPN (proxy), or blocked.\n\n## Domains\nvk.com — the domain itself and all its subdomains\nru — anything ending in .ru (a bare word, no dot)\n.example.com — subdomains only, not the domain itself\nfull:example.com — exactly this host, no subdomains\nregexp:… — a regex, if you really need to get fancy\n\n## IP addresses\n1.2.3.4 — a single address\n10.0.0.0/8 — a whole range (CIDR)\n\n## GeoIP — by country\ngeoip:ru — every Russian IP. Swap ru for any country: us, de, cn, ua, kz…\nPlus ready-made bundles: geoip:private (LAN), geoip:telegram, geoip:google.\nNeed it by country? This is the one — geoip knows them all.\n\n## GeoSite — ready-made lists\ngeosite:google, geosite:netflix, geosite:telegram, geosite:category-ads-all…\nThese aren\'t countries but service categories someone already put together for you.\nHardly any countries here (just geolocation-cn and geolocation-!cn), so by-country is really geoip\'s job.\n\n## On PC (keqrnel core)\nGeo works the same as on the phone: the xray built into keqrnel does the matching. It just needs geoip.dat and geosite.dat sitting next to keqdroid.exe — a release build already has them there. If geo rules look ignored, check those two files first.\n\n## Order\nTop to bottom: block first, then your server (always direct, or you\'d get a loop), then bypass, then proxy. Whatever is left follows the Unmatched traffic switch up top.';

  @override
  String settingsRoutingItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
      zero: 'empty',
    );
    return '$_temp0';
  }

  @override
  String settingsAndroidColorsSubtitle(Object mode) {
    return 'Android colors · $mode';
  }

  @override
  String settingsSystemColorsSubtitle(Object mode) {
    return 'System colors · $mode';
  }

  @override
  String get themeModeDark => 'Dark';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeCustomizationTitle => 'Appearance';

  @override
  String get themeUseDynamicColors => 'Use Android dynamic colors';

  @override
  String get themeUseDynamicColorsSubtitle => 'Use Android dynamic colors when available';

  @override
  String get themeDynamicPaletteHint => 'Dynamic Android palette is active. Light/Dark works independently.';

  @override
  String get themeSystemPaletteHint => 'System accent palette is active. Light/Dark works independently.';

  @override
  String get themeUseSystemColors => 'Use system accent colors';

  @override
  String get themeUseSystemColorsSubtitle => 'Follow Windows or Linux accent colors when available';

  @override
  String get themeCustomPaletteHint => 'Custom palette is active. Light/Dark works independently.';

  @override
  String get themeColorThemesTitle => 'Color themes';

  @override
  String get serversTwoColumnsTitle => 'Two-column server list';

  @override
  String get serversTwoColumnsSubtitle => 'Show servers in two columns to fit more on screen';

  @override
  String get settingsLanProxyTitle => 'LAN Proxy';

  @override
  String get settingsOff => 'Off';

  @override
  String settingsLanSharingOnIp(Object ip) {
    return 'Sharing on $ip';
  }

  @override
  String get settingsDeviceIpListTitle => 'Device IP addresses on the network:';

  @override
  String get settingsIpCopied => 'IP copied';

  @override
  String get settingsSetupAnotherDeviceTitle => 'Setup on another device:';

  @override
  String get settingsSocks5PortLabel => 'SOCKS5 port';

  @override
  String get settingsHttpPortLabel => 'HTTP port';

  @override
  String get settingsLanUsernameLabel => 'Username';

  @override
  String get settingsLanPasswordLabel => 'Password';

  @override
  String get settingsLanAuthHint => 'Both fields set — devices sign in to the proxy with them. Empty — no password (anyone on your network can use it).';

  @override
  String get settingsLocalPortsTitle => 'Local proxy ports';

  @override
  String get settingsLocalPortsHint => 'Listen ports for the local SOCKS5 and HTTP proxies (defaults 2080 / 2081). Applied on the next connection. The two ports must differ.';

  @override
  String get settingsPortInvalid => 'Enter a port between 1 and 65535';

  @override
  String get settingsPortsMustDiffer => 'SOCKS and HTTP ports must differ';

  @override
  String get settingsTurnOffToChange => 'Turn off to change setting';

  @override
  String settingsProxyCopied(Object label, Object address) {
    return '$label $address copied';
  }

  @override
  String get settingsXrayCoreTitle => 'Core settings';

  @override
  String get settingsXrayCoreSubtitle => 'Ports, DNS, XMUX, TUN, log and routing';

  @override
  String get settingsXrayDnsSection => 'DNS';

  @override
  String get settingsXrayDnsCustom => 'Custom DNS servers';

  @override
  String get settingsXrayDnsCustomHint => 'One address per line (DoH, DoT, or plain)';

  @override
  String get settingsXrayDnsServers => 'DNS servers';

  @override
  String get settingsXrayDnsSplitDirect => 'Split resolver for direct domains';

  @override
  String get settingsXrayDnsSplitDirectHint => 'Uses first server for domains from direct list';

  @override
  String get settingsXrayDnsQueryStrategy => 'Query strategy';

  @override
  String get settingsXrayDnsDisableCache => 'Disable DNS cache';

  @override
  String get settingsXrayXmuxSection => 'XMUX (XHTTP)';

  @override
  String get settingsXrayXmuxEnable => 'Enable XMUX';

  @override
  String get settingsXrayXmuxEnableHint => 'Multiplexing for XHTTP transport (client-side)';

  @override
  String get settingsXrayGeneralSection => 'General';

  @override
  String get settingsXrayLogLevel => 'Log level';

  @override
  String get settingsXrayDomainStrategy => 'Routing domain strategy';

  @override
  String get settingsXraySniffing => 'Inbound sniffing';

  @override
  String get settingsXraySniffingRouteOnly => 'Sniffing route only';

  @override
  String get settingsXrayCoreIntro => 'These options are injected into the generated Xray config. Change only if you know what they do.';

  @override
  String get settingsXrayDnsDefaultNote => 'Default: Cloudflare and Google DoH';

  @override
  String get settingsXrayXmuxParamsTitle => 'Tuning';

  @override
  String get settingsXrayXmuxParamsHint => 'Leave empty to use Xray defaults. Values can be a number or range (e.g. 16-32).';

  @override
  String get settingsXraySniffingHint => 'Detect destination protocol and domain from inbound traffic';

  @override
  String get settingsXraySniffingRouteOnlyHint => 'Off (default): the sniffed domain becomes the destination, so it is resolved again — locally for direct routes, on the server for proxied ones. On: the domain is used only to pick a rule, and the connection still goes to the address the app supplied — which is wrong whenever that address came from a resolver on the far side of the tunnel (RU sites then load over a direct route to a foreign CDN node).';

  @override
  String get settingsXrayResetDefaults => 'Reset to defaults';

  @override
  String get settingsXrayResetDone => 'Xray core settings restored';

  @override
  String get settingsXrayXmuxMaxConcurrency => 'Max concurrency';

  @override
  String get settingsXrayXmuxMaxConnections => 'Max connections';

  @override
  String get settingsXrayXmuxCMaxReuseTimes => 'Connection reuse limit';

  @override
  String get settingsXrayXmuxHMaxRequestTimes => 'Max requests per stream';

  @override
  String get settingsXrayXmuxHMaxReusableSecs => 'Stream reuse time (sec)';

  @override
  String get settingsXrayXmuxHKeepAlivePeriod => 'Keep-alive period (sec)';

  @override
  String get settingsTunSection => 'TUN mode';

  @override
  String get settingsTunSectionNote => 'sing-box TUN interface options (desktop). Applied on next connection.';

  @override
  String get settingsTunStackTitle => 'Network stack';

  @override
  String get settingsTunStackSystemHint => 'OS kernel TCP/IP stack — fastest, but on Windows it terminates TCP on a listener at the TUN address and needs a Windows Firewall rule; when that rule does not stick, the tunnel comes up with no traffic at all';

  @override
  String get settingsTunStackGvisorHint => 'Userspace stack — default. Runs entirely inside the core, so it needs neither a listener nor firewall rules; a bit slower. Needs a core built with gVisor (cores from app 0.7.1 and older exit with code 1)';

  @override
  String get settingsTunStackMixedHint => 'gVisor for TCP, system for UDP. Needs a core built with gVisor (cores from app 0.7.1 and older exit with code 1)';

  @override
  String get settingsTunMtu => 'MTU';

  @override
  String get settingsTunMtuHint => '576–65535, default 9000';

  @override
  String get settingsTunUdpTimeout => 'UDP timeout (sec)';

  @override
  String get settingsTunUdpTimeoutHint => 'NAT lifetime of idle UDP sessions, default 300';

  @override
  String get settingsTunStrictRouteTitle => 'Strict route';

  @override
  String get settingsTunStrictRouteHint => 'Prevents traffic from leaking around the TUN. On Windows it can break routing when another VPN (e.g. Tailscale) is active';

  @override
  String get settingsTunStrictRouteAuto => 'Auto';

  @override
  String get settingsTunStrictRouteAutoHint => 'Linux: on, Windows: off';

  @override
  String get settingsTunStrictRouteOn => 'Enabled';

  @override
  String get settingsTunStrictRouteOff => 'Disabled';

  @override
  String get settingsTunEin => 'Endpoint-independent NAT';

  @override
  String get settingsTunEinHint => 'Full-cone NAT for UDP — helps P2P and games. gVisor/mixed stack only';

  @override
  String get settingsTunAutoRoute => 'Auto route';

  @override
  String get settingsTunAutoRouteHint => 'Adds system routes into the tunnel automatically. Disable only if you manage routes yourself — without it no traffic enters the TUN';

  @override
  String get settingsTunIpv6 => 'Keep IPv6 inside the tunnel';

  @override
  String get settingsTunIpv6Hint => 'A TUN interface with only an IPv4 address gets no IPv6 routes, so on a dual-stack machine IPv6 traffic goes around the tunnel — past the routing rules and past the proxy. With this on the interface also gets an IPv6 address and IPv6 egress is closed, so apps fall back to IPv4, which is already tunnelled. The address is added only when the machine really has global IPv6. Xray/keqrnel core only';

  @override
  String get settingsMihomoSection => 'mihomo core';

  @override
  String get settingsMihomoFakeIp => 'Fake IP';

  @override
  String get settingsMihomoFakeIpHint => 'Answers DNS with a placeholder address instead of the real one: lookups become instant and domain rules stop depending on sniffing. In exchange, IP rules have to be resolved again before they can match, so the same routing lists behave a little differently than on Xray. Applies only where mihomo owns the tunnel — TUN mode and Android.';

  @override
  String get settingsPingTitle => 'Server ping';

  @override
  String get settingsPingMethodTitle => 'Ping method';

  @override
  String get settingsPingMethodTcp => 'TCP ping';

  @override
  String get settingsPingMethodTcpHint => 'Fast reachability check';

  @override
  String get settingsPingMethodIcmp => 'ICMP ping';

  @override
  String get settingsPingMethodIcmpHint => 'Echo to server IP (some servers block it)';

  @override
  String get settingsPingMethodUrl => 'HTTP via proxy';

  @override
  String get settingsPingMethodUrlHint => 'Measures GET latency through the server';

  @override
  String get settingsPingKeepAliveTitle => 'Measurement';

  @override
  String get settingsPingKeepAlive => 'Keep-alive';

  @override
  String get settingsPingKeepAliveHint => 'Sends two requests over one connection and keeps the better one, so the result is the server\'s response time without the cost of opening the connection. Turn it off to measure a full request, handshake included — larger numbers, closer to what a browser waits for.';

  @override
  String get settingsPingMethodSpeed => 'Speed test';

  @override
  String get settingsPingMethodSpeedHint => 'Downloads a fixed payload through the server and shows throughput in Mbps (works without VPN)';

  @override
  String get settingsPingTargetTitle => 'HTTP test URL';

  @override
  String get settingsPingTargetGstatic => 'Google (generate_204)';

  @override
  String get settingsPingTargetCloudflare => 'Cloudflare (trace)';

  @override
  String get settingsPingTargetMicrosoft => 'Microsoft (connect test)';

  @override
  String get settingsPingTargetCustom => 'Custom URL';

  @override
  String get settingsPingCustomUrl => 'URL';

  @override
  String get settingsPingCustomUrlHint => 'https:// or http:// address for GET request';

  @override
  String get settingsPingCustomUrlInvalid => 'Invalid or unsafe URL (no localhost or private networks)';

  @override
  String get subscriptionNameLabel => 'Name';

  @override
  String get subscriptionNameHint => 'My Subscription';

  @override
  String get subscriptionUrlLabel => 'URL';

  @override
  String get subscriptionUrlHint => 'https://example.com/sub?token=...';

  @override
  String get subscriptionsAddSubscription => 'Add Subscription';

  @override
  String get subscriptionsAddAndFetch => 'Add & Fetch';

  @override
  String get subscriptionsEditSubscription => 'Edit subscription';

  @override
  String get subscriptionsCopyUrl => 'Copy URL';

  @override
  String get subscriptionsUrlCopied => 'URL copied';

  @override
  String get subscriptionsShareButton => 'Share (QR + link)';

  @override
  String get subscriptionsShareAction => 'Share';

  @override
  String subscriptionsShareFailed(Object error) {
    return 'Could not share: $error';
  }

  @override
  String get subscriptionIdentityTitle => 'Device identity';

  @override
  String get subscriptionIdentityHint => 'What this panel sees: HWID, User-Agent and device headers. Applies to this subscription only.';

  @override
  String get subscriptionIdentityEnable => 'Use a custom identity';

  @override
  String get subscriptionIdentityAppDefault => 'App default';

  @override
  String get subscriptionIdentityAppDefaultHint => 'Send this device\'s real value';

  @override
  String get subscriptionIdentityHwid => 'HWID';

  @override
  String get subscriptionIdentityHwidOff => 'Sharing the device HWID is turned off in Advanced settings, so no HWID is sent — custom or not.';

  @override
  String get subscriptionIdentityUserAgent => 'User-Agent';

  @override
  String get subscriptionIdentityDeviceOs => 'Device OS';

  @override
  String get subscriptionIdentityDeviceModel => 'Device model';

  @override
  String get subscriptionIdentityOsVersion => 'OS version';

  @override
  String get subscriptionIdentitySectionUsed => 'Already in use';

  @override
  String get subscriptionIdentitySearchOrEnter => 'Search or type your own';

  @override
  String get subscriptionIdentityUseTyped => 'Use this value';

  @override
  String get subscriptionIdentityReset => 'Reset';

  @override
  String get subscriptionIdentityApply => 'Apply';

  @override
  String get subscriptionsDeleteSubscription => 'Delete subscription';

  @override
  String subscriptionsDeleteConfirm(Object name) {
    return 'Are you sure you want to delete \"$name\"?\n\nThis will also remove all associated servers.';
  }

  @override
  String get subscriptionsRetry => 'Retry';

  @override
  String get subscriptionsCancel => 'Cancel';

  @override
  String get subscriptionsDelete => 'Delete';

  @override
  String get subscriptionsSave => 'Save';

  @override
  String get subscriptionsOff => 'OFF';

  @override
  String get subscriptionsExpired => 'Expired';

  @override
  String get subscriptionsEveryHour => 'Every hour';

  @override
  String subscriptionsEveryHours(int hours) {
    return 'Every $hours hours';
  }

  @override
  String get subscriptionsEveryDay => 'Every day';

  @override
  String subscriptionsEveryDays(int days) {
    return 'Every $days days';
  }

  @override
  String get subscriptionsAutoUpdateInterval => 'Auto-update interval';

  @override
  String subscriptionsCurrentInterval(int hours) {
    return 'every ${hours}h';
  }

  @override
  String subscriptionsIntervalShort(int hours) {
    return '${hours}h';
  }

  @override
  String get subscriptionsJustNow => 'just now';

  @override
  String subscriptionsMinutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String subscriptionsHoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String subscriptionsDaysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String subscriptionsInDays(int days) {
    return 'in ${days}d';
  }

  @override
  String subscriptionsInHours(int hours) {
    return 'in ${hours}h';
  }

  @override
  String get subscriptionsSoon => 'soon';

  @override
  String get serversAddServer => 'Add server';

  @override
  String get serversPasteLinks => 'Paste link(s)';

  @override
  String get serversImportFile => 'Import file';

  @override
  String get serversAddServerTitle => 'Add Server';

  @override
  String get serversPasteVlessHint => 'Paste vless://, vmess://, trojan://, ss://, hysteria2://, hy2:// or wg:// (one per line), or a whole config: Xray JSON, Clash YAML, AmneziaWG .conf';

  @override
  String get serversPasteHint => 'vless://… or hy2://host:port?auth=…';

  @override
  String get serversAdd => 'Add';

  @override
  String get serversManualServers => 'Manual servers';

  @override
  String get serversRefreshSubscription => 'Refresh subscription';

  @override
  String get serversPingAll => 'Ping all';

  @override
  String get settingsAdvanced => 'Advanced';

  @override
  String get settingsAdvancedSubtitle => 'Core settings, ping, routing, HWID and debug';

  @override
  String get serverEditorJsonValid => 'Valid Xray config';

  @override
  String get serverEditorJsonFormat => 'Format';

  @override
  String get subscriptionsCardMenu => 'More';

  @override
  String get subscriptionsAutoUpdateOff => 'Do not update automatically';

  @override
  String get subscriptionsProviderPage => 'Subscription page';

  @override
  String get subscriptionsSupport => 'Support';

  @override
  String get subscriptionsLinkOpenFailed => 'Could not open the link';

  @override
  String get settingsAdvancedGroupTraffic => 'Traffic and core';

  @override
  String get settingsAdvancedGroupSystem => 'System';

  @override
  String get settingsAdvancedGroupDiagnostics => 'Diagnostics';

  @override
  String get settingsBackupRestore => 'Backup & restore';

  @override
  String get settingsBackupRestoreSubtitle => 'Export/import split tunneling, subscriptions, servers and settings';

  @override
  String get settingsSelectAtLeastOne => 'Select at least one section to export';

  @override
  String get settingsBackupSaved => 'Backup saved successfully';

  @override
  String get settingsSelectLocation => 'Select location to save backup';

  @override
  String get settingsExportFile => 'Export file';

  @override
  String get settingsImportFile => 'Import from file';

  @override
  String get settingsImportBackup => 'Import backup';

  @override
  String get settingsChooseWhatToImport => 'Choose what to import (selected sections will replace your current data).';

  @override
  String get settingsSplitTunnelingApps => 'Split tunneling apps';

  @override
  String get settingsSubscriptions => 'Subscriptions';

  @override
  String get settingsServersActive => 'Servers (and active server)';

  @override
  String get settingsAppSettings => 'App settings';

  @override
  String get settingsAppSettingsHint => 'Routing, DNS, appearance, ping and language. Ports, LAN sharing and TUN stay as they are on this machine.';

  @override
  String get settingsImport => 'Import';

  @override
  String get settingsExport => 'Export';

  @override
  String get settingsCreateFileToSave => 'Create a file you can save and import on another device.';

  @override
  String get settingsPickExportedFile => 'Pick a previously exported file and restore selected sections.';

  @override
  String get settingsWorking => 'Working...';

  @override
  String settingsImportedSections(int count) {
    return 'Imported: $count section(s)';
  }

  @override
  String get settingsDebugMode => 'Debug mode';

  @override
  String get settingsDebugModeOn => 'Extended diagnostics enabled';

  @override
  String get settingsDebugModeOff => 'Off';

  @override
  String get settingsOpenXrayLogs => 'Open core logs';

  @override
  String get settingsXrayCoreLogs => 'Core logs';

  @override
  String get settingsRefresh => 'Refresh';

  @override
  String get settingsCopyLogs => 'Copy logs';

  @override
  String get settingsAppVersion => 'App version';

  @override
  String get settingsChecking => 'Checking...';

  @override
  String get settingsCheckFailed => 'Check failed';

  @override
  String get settingsUpdateAvailable => 'Update available';

  @override
  String get settingsUpToDate => 'Up to date';

  @override
  String get settingsNewVersionAvailable => 'New version available';

  @override
  String get settingsDownloading => 'Downloading...';

  @override
  String get settingsCheckForUpdates => 'Check for updates';

  @override
  String settingsExportFailed(Object error) {
    return 'Export failed: $error';
  }

  @override
  String settingsImportFailed(Object error) {
    return 'Import failed: $error';
  }

  @override
  String settingsDownloadFailed(Object error) {
    return 'Download failed: $error';
  }

  @override
  String settingsCheckFailedError(Object error) {
    return 'Check failed: $error';
  }

  @override
  String get settingsLanguageTitle => 'Language';

  @override
  String settingsLanguageSubtitle(Object language) {
    return '$language';
  }

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageGerman => 'Deutsch';

  @override
  String get settingsLanguageChinese => '中文';

  @override
  String get settingsLanguageFarsi => 'فارسی';

  @override
  String get settingsLanguageSheetTitle => 'Choose language';

  @override
  String get splitAddApp => 'Add app';

  @override
  String get splitAddAppTitle => 'Add application';

  @override
  String get splitAddAppHint => 'Path to .exe or name (e.g. chrome.exe)';

  @override
  String get splitAddAppPickFile => 'Browse…';

  @override
  String get splitAddAppInvalid => 'Enter a valid .exe name or path';

  @override
  String splitAddAppAdded(Object name) {
    return 'Added: $name';
  }

  @override
  String get splitProxyModeWarning => 'Split tunneling is not applied in Proxy mode — all traffic goes through the system proxy. Switch the connection mode to TUN (in the side panel) so per-process rules work.';

  @override
  String get settingsLatestVersionInstalled => 'You have the latest version';

  @override
  String get serversPingServer => 'Ping server';

  @override
  String get serversCopyAddress => 'Copy server address';

  @override
  String get serversCopiedToClipboard => 'Copied to clipboard';

  @override
  String get serversCopyConfig => 'Copy configuration';

  @override
  String get serversConfigCopied => 'Configuration copied';

  @override
  String get serversDeleteServer => 'Delete server';

  @override
  String get settingsDebugHintDesktop => 'Shows core session logs. Live VPN metrics are shown under the connect button.';

  @override
  String get settingsDebugHintMobile => 'Shows live VPN metrics in server cards and core logs.';

  @override
  String get desktopConnectionMode => 'Connection mode';

  @override
  String get desktopModeShort => 'Mode';

  @override
  String get settingsDesktopTitle => 'Windows';

  @override
  String get settingsDesktopSubtitle => 'Tray, autostart, auto-connect';

  @override
  String get settingsMinimizeToTray => 'Minimize to tray on close';

  @override
  String get settingsMinimizeToTrayHint => 'When off, closing the window exits the app';

  @override
  String get settingsLaunchAtStartup => 'Start with Windows';

  @override
  String get settingsLaunchAtStartupHint => 'Launch the app when you sign in';

  @override
  String get settingsAutoConnectOnAutostart => 'Connect on autostart';

  @override
  String get settingsAutoConnectOnAutostartHint => 'Connect to the last selected server using the mode from the sidebar. If TUN needs admin rights and they are unavailable, Proxy is used';

  @override
  String get settingsAutoConnectRequiresAutostart => 'Enable \"Start with Windows\" first';

  @override
  String get desktopTunAdminTitle => 'Administrator rights required';

  @override
  String get desktopTunAdminMessage => 'TUN mode needs administrator rights. Restart the app as administrator to use TUN. The current mode in the sidebar will be kept.';

  @override
  String get desktopTunAdminRestart => 'Restart as administrator';

  @override
  String get desktopTunAdminCancel => 'Cancel';

  @override
  String get desktopTunAdminRestartFailed => 'Could not restart as administrator';

  @override
  String get trayConnect => 'Connect';

  @override
  String get trayDisconnect => 'Disconnect';

  @override
  String get trayOpenApp => 'Open app';

  @override
  String get trayExit => 'Exit';

  @override
  String get trayPickServer => 'Select server…';

  @override
  String get trayModeProxy => 'Proxy';

  @override
  String get trayModeTun => 'TUN';

  @override
  String get trayStatusConnected => 'Connected';

  @override
  String get trayStatusDisconnected => 'Disconnected';

  @override
  String get trayStatusError => 'Error';

  @override
  String get serversSortTitle => 'Sort servers';

  @override
  String get serversSortDefault => 'Default order';

  @override
  String get serversSortPing => 'Ping (low → high)';

  @override
  String get serversSortSpeed => 'Speed (high → low)';

  @override
  String get serversSortName => 'Name (A → Z)';

  @override
  String get updateActionSkip => 'Skip this version';

  @override
  String updateSizeLabel(Object size) {
    return 'Size: $size';
  }

  @override
  String get updateOpenDownload => 'Open download';

  @override
  String get vpnConnectedGeneric => 'VPN connected';

  @override
  String serversImportedSummary(Object added, Object total) {
    return 'Servers added: $added of $total';
  }

  @override
  String get sidebarJumpTitle => 'Jump to';

  @override
  String get serversScrollToEnd => 'Jump to end';

  @override
  String get serversScrollToTop => 'Jump to top';

  @override
  String get serversJumpToActive => 'Show in list';

  @override
  String get serversManualGroup => 'Manual servers';

  @override
  String get serversEmptyGroupHint => 'No servers in this subscription';

  @override
  String get statsInLabel => 'In';

  @override
  String get statsTimeLabel => 'Time';

  @override
  String get qrScanTitle => 'Scan QR code';

  @override
  String get qrScanHint => 'Point the camera at a QR code';

  @override
  String get qrScanCameraError => 'Camera unavailable';

  @override
  String get serversScanQrHint => 'Server link or subscription link';

  @override
  String qrSubscriptionAdded(Object name) {
    return 'Subscription added: $name';
  }

  @override
  String get qrNotSubscriptionLink => 'QR code doesn\'t contain a subscription link';

  @override
  String get settingsHotkeysTitle => 'Hotkeys';

  @override
  String get settingsHotkeysSubtitle => 'Shortcuts for connection, mode and servers';

  @override
  String get hotkeysHintGlobal => 'Hotkeys work system-wide, even when the window is hidden in the tray. All hotkeys are disabled until you assign them.';

  @override
  String get hotkeysHintInApp => 'On Linux hotkeys work while the app window is focused. All hotkeys are disabled until you assign them.';

  @override
  String get hotkeyActionToggleConnection => 'Connect / disconnect';

  @override
  String get hotkeyActionToggleConnectionDesc => 'Toggle the tunnel for the active server';

  @override
  String get hotkeyActionToggleTun => 'Toggle TUN mode';

  @override
  String get hotkeyActionToggleTunDesc => 'Switch between Proxy and TUN, reconnecting if needed';

  @override
  String get hotkeyActionBestPing => 'Best-ping server';

  @override
  String get hotkeyActionBestPingDesc => 'Switch to the server with the lowest ping';

  @override
  String get hotkeyActionToggleWindow => 'Show / hide window';

  @override
  String get hotkeyActionToggleWindowDesc => 'Restore the window from the tray or hide it';

  @override
  String get hotkeyNotSet => 'Not set';

  @override
  String get hotkeyPressKeys => 'Press a shortcut…';

  @override
  String get hotkeyRecordingHint => 'Esc — cancel, Backspace — clear';

  @override
  String get hotkeyNeedsModifier => 'Use a modifier (Ctrl/Alt/Shift/Win) or an F-key';

  @override
  String hotkeyConflictTaken(Object combo) {
    return 'Shortcut $combo is already taken by another app';
  }

  @override
  String get hotkeyClearTooltip => 'Clear shortcut';

  @override
  String get hotkeyNoPingData => 'No ping results yet — run a ping test first';

  @override
  String get clipboardNoSubscriptionLink => 'Clipboard has no subscription link (http/https)';

  @override
  String get splitTunnelingReconnectHint => 'Changes apply after reconnecting the VPN';

  @override
  String serversDeleteConfirm(Object name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get errorTunAdminMessage => 'TUN mode on Windows needs Administrator rights.';

  @override
  String get errorTunAdminAction => 'Run the app as administrator or switch to Proxy mode in settings.';

  @override
  String get errorVpnPermissionMessage => 'VPN permission was not granted.';

  @override
  String get errorVpnPermissionAction => 'Allow VPN permission in the system dialog and try again.';

  @override
  String get errorHwidBindMessage => 'Provider requires HWID binding for this device.';

  @override
  String get errorHwidBindAction => 'Bind this device in provider panel, then refresh subscription.';

  @override
  String get errorDeviceLimitMessage => 'Provider refused subscription due to device limit.';

  @override
  String get errorDeviceLimitAction => 'Remove old devices in provider panel or raise device limit.';

  @override
  String get errorConfigInvalidMessage => 'Subscription or server configuration is invalid.';

  @override
  String get errorConfigInvalidAction => 'Check URL/config format and import a valid subscription link.';

  @override
  String get errorAuthDeniedMessage => 'Access to subscription is denied by provider.';

  @override
  String get errorAuthDeniedAction => 'Check token/credentials and verify subscription has not expired.';

  @override
  String get errorSubUrlInvalidMessage => 'Subscription link is missing or expired.';

  @override
  String get errorSubUrlInvalidAction => 'Request a fresh URL from provider and update it in app.';

  @override
  String get errorSubInsecureHttpMessage => 'Subscription link uses plain http, updates are blocked.';

  @override
  String get errorSubInsecureHttpAction => 'Replace the link with its https:// version.';

  @override
  String get subInsecureHttpWarning => 'http link — updates are blocked';

  @override
  String get subSwitchToHttps => 'Switch to https';

  @override
  String get errorNetworkMessage => 'Cannot reach server right now.';

  @override
  String get errorNetworkAction => 'Check internet, DNS, and server availability, then retry.';

  @override
  String get errorUnknownAction => 'Retry operation. If issue repeats, check server and app settings.';

  @override
  String get errorFileDialogMessage => 'This desktop session has no file chooser: neither an XDG portal backend nor zenity/kdialog.';

  @override
  String get errorFileDialogAction => 'Install xdg-desktop-portal-gtk (or zenity), or paste the config text instead of picking a file.';

  @override
  String get errorTunAdminTitle => 'Permission Required';

  @override
  String get errorVpnPermissionTitle => 'Permission Required';

  @override
  String get errorHwidBindTitle => 'Device Binding Required';

  @override
  String get errorDeviceLimitTitle => 'Device Limit Reached';

  @override
  String get errorProviderNoHostsTitle => 'Provider Configuration Required';

  @override
  String get errorConfigInvalidTitle => 'Configuration Error';

  @override
  String get errorAuthDeniedTitle => 'Authorization Failed';

  @override
  String get errorSubUrlInvalidTitle => 'Subscription URL Invalid';

  @override
  String get errorSubInsecureHttpTitle => 'Insecure Subscription URL';

  @override
  String get errorNetworkTitle => 'Network Error';

  @override
  String get errorUnknownTitle => 'Operation Failed';

  @override
  String get errorFileDialogTitle => 'No File Dialog';

  @override
  String get serversPin => 'Pin server';

  @override
  String get serversUnpin => 'Unpin server';

  @override
  String get serversPinDesc => 'Pinned servers stay on top of the list';

  @override
  String get serversRename => 'Rename';

  @override
  String get serversRenameTitle => 'Rename server';

  @override
  String get serversRenameHint => 'Server name';

  @override
  String get serversRenameReset => 'Reset';

  @override
  String serversRenameOriginal(Object name) {
    return 'Original name: $name';
  }

  @override
  String get serversEditConfig => 'Edit configuration';

  @override
  String get serversEditConfigDesc => 'SNI, fingerprint, transport and other settings';

  @override
  String get serverEditorTitle => 'Server configuration';

  @override
  String get serverEditorSectionGeneral => 'Server';

  @override
  String get serverEditorSectionSecurity => 'Security';

  @override
  String get serverEditorSectionTransport => 'Transport';

  @override
  String get serverEditorSectionProtocol => 'Protocol settings';

  @override
  String get serverEditorAddress => 'Address';

  @override
  String get serverEditorPort => 'Port';

  @override
  String get serverEditorPassword => 'Password';

  @override
  String get serverEditorMethod => 'Encryption method';

  @override
  String get serverEditorEncryption => 'Encryption';

  @override
  String get serverEditorSecurityMode => 'Security mode';

  @override
  String get serverEditorFingerprint => 'Fingerprint (uTLS)';

  @override
  String get serverEditorAlpn => 'ALPN (comma-separated)';

  @override
  String get serverEditorAllowInsecure => 'Allow insecure certificate (insecure)';

  @override
  String get serverEditorPbk => 'Public key (pbk)';

  @override
  String get serverEditorSid => 'Short ID (sid)';

  @override
  String get serverEditorSpx => 'SpiderX (spx)';

  @override
  String get serverEditorTransportType => 'Type';

  @override
  String get serverEditorPath => 'Path';

  @override
  String get serverEditorServiceName => 'gRPC service name';

  @override
  String get serverEditorMode => 'Mode';

  @override
  String get serverEditorHeaderType => 'Header type';

  @override
  String get serverEditorAuth => 'Auth password';

  @override
  String get serverEditorObfs => 'Obfuscation (obfs)';

  @override
  String get serverEditorObfsPassword => 'Obfuscation password';

  @override
  String get serverEditorUp => 'Upload, Mbps';

  @override
  String get serverEditorDown => 'Download, Mbps';

  @override
  String get serverEditorMport => 'Port hopping (mport)';

  @override
  String get serverEditorHopInterval => 'Hop interval, s';

  @override
  String get serverEditorPinSha256 => 'Certificate pinning (SHA-256)';

  @override
  String get serverEditorRawConfig => 'Raw config';

  @override
  String get serverEditorRawToggle => 'Edit as text';

  @override
  String get serverEditorRawOnlyNote => 'This format is edited as raw text';

  @override
  String get serverEditorPreview => 'Resulting link';

  @override
  String get serverEditorSubscriptionNote => 'This server comes from a subscription: your edits are kept when it refreshes.';

  @override
  String get serverEditorOverriddenNote => 'Config edited manually — subscription updates no longer replace it.';

  @override
  String get serverEditorRevert => 'Restore subscription config';

  @override
  String get serverEditorSaved => 'Configuration saved';

  @override
  String get serverEditorReconnecting => 'Configuration saved, reconnecting…';

  @override
  String get serverEditorInvalidPort => 'Invalid port';

  @override
  String get serverEditorServerMissing => 'Server no longer exists';

  @override
  String get appearanceTabGeneral => 'General';

  @override
  String get appearanceTabThemes => 'Themes';

  @override
  String get appearanceAmoled => 'Pure black (AMOLED)';

  @override
  String get appearanceAmoledSubtitle => 'True black background in the dark theme — saves power on OLED screens';

  @override
  String get appearanceAmoledNeedsDark => 'Available with the dark theme on';

  @override
  String get appearanceHaptics => 'Haptic feedback';

  @override
  String get appearanceHapticsSubtitle => 'Vibrate on connect, tab and server taps';

  @override
  String get appearanceShowTraffic => 'Show traffic';

  @override
  String get appearanceShowTrafficSubtitle => 'Speed and data usage chips under the connect button';

  @override
  String get appearanceShowTime => 'Show connection time';

  @override
  String get appearanceShowTimeSubtitle => 'Session duration chip under the connect button';

  @override
  String get appearanceFontTitle => 'Font';

  @override
  String get appearanceFontSystem => 'System';

  @override
  String get settingsResetConfirmTitle => 'Reset settings?';

  @override
  String get settingsResetConfirmAction => 'Reset';

  @override
  String get settingsResetRoutingConfirm => 'This restores the built-in routing rules and discards your direct/proxy/blocked lists. This can\'t be undone.';

  @override
  String get settingsXrayResetConfirm => 'This restores the default Xray core, TUN and local port settings. This can\'t be undone.';

  @override
  String get settingsPermissionsTitle => 'Permissions';

  @override
  String get settingsPermissionsSubtitle => 'App permissions you can review and revoke';

  @override
  String get settingsPermNotifTitle => 'Notifications';

  @override
  String get settingsPermNotifDesc => 'VPN status bar and subscription-update alerts';

  @override
  String get settingsPermStatusGranted => 'Granted';

  @override
  String get settingsPermStatusDenied => 'Denied';

  @override
  String get settingsPermCameraTitle => 'Camera';

  @override
  String get settingsPermCameraDesc => 'Scan config QR codes';

  @override
  String get settingsPermInstallTitle => 'Install apps';

  @override
  String get settingsPermInstallDesc => 'Install app updates';

  @override
  String get settingsPermOpenAppSettings => 'Open app settings';

  @override
  String get settingsPermRevokeHint => 'Revoke any permission in the system app settings.';

  @override
  String get settingsPermTunHeader => 'TUN MODE (LINUX)';

  @override
  String get settingsPermTunPasswordlessTitle => 'Passwordless TUN';

  @override
  String get settingsPermTunPasswordlessSubtitle => 'Start TUN mode without entering the polkit password each time';

  @override
  String get settingsPermTunDisabled => 'Passwordless TUN disabled';

  @override
  String get appearanceNotifSectionTitle => 'NOTIFICATION';

  @override
  String get appearanceNotifSpeedTitle => 'Connection speed in notification';

  @override
  String get appearanceNotifSpeedSubtitle => 'Show ↓/↑ speed in the VPN status notification';

  @override
  String get appearanceNotifUptimeTitle => 'Connection time in notification';

  @override
  String get appearanceNotifUptimeSubtitle => 'Show session uptime in the VPN status notification';

  @override
  String get appearanceNotifSubUpdatesTitle => 'Subscription update notifications';

  @override
  String get appearanceNotifSubUpdatesSubtitle => 'Notify when subscriptions refresh in the background';

  @override
  String get tunRememberTitle => 'Remember authorization?';

  @override
  String get tunRememberMessage => 'TUN mode needs root and asks for your password each time. Install a polkit rule so it starts without a password from now on? You\'ll be asked for your password once to install it.';

  @override
  String get tunRememberWarning => 'After this, any program running as your user can start the VPN core as root without a password. You can undo it anytime in Advanced → Permissions.';

  @override
  String get tunRememberEnable => 'Enable';

  @override
  String get tunRememberNotNow => 'Not now';

  @override
  String get tunRememberInstalled => 'Passwordless TUN enabled';

  @override
  String get tunRememberFailed => 'Could not change TUN authorization';

  @override
  String get settingsRoutingPresetTelegramGeoTitle => 'Telegram (GeoIP+GeoSite) — Proxy';

  @override
  String get settingsRoutingPresetTelegramGeoDesc => 'Telegram by domains and by IP ranges (MTProto uses bare IPs)';

  @override
  String get settingsRoutingPresetRefilterTitle => 'Blocked in Russia (Re-filter) — Proxy';

  @override
  String get settingsRoutingPresetRefilterDesc => 'Domains and IPs blocked in Russia go through the VPN, everything else stays direct';

  @override
  String get settingsRoutingGeoUnknownTitle => 'Missing from the geo databases — will be ignored';

  @override
  String get settingsRoutingGeoUnknownHint => 'The core aborts the whole config on an unknown geo code, so these entries are dropped before connecting. Pick an existing code with the globe button above.';

  @override
  String get settingsRoutingGeoPickerTooltip => 'Insert a geo code';

  @override
  String get settingsRoutingGeoPickerTitle => 'Geo codes in the bundled databases';

  @override
  String get settingsRoutingGeoPickerSearchHint => 'Search, e.g. telegram';

  @override
  String get settingsRoutingGeoPickerEmpty => 'No codes match';

  @override
  String get settingsRoutingGeoPickerGeosite => 'Domains (geosite)';

  @override
  String get settingsRoutingGeoPickerGeoip => 'IP ranges (geoip)';

  @override
  String get settingsOpenConnections => 'Connections';

  @override
  String get settingsConnectionsTitle => 'Connections';

  @override
  String get connectionsEmpty => 'No connections captured yet.';

  @override
  String get connectionsUnavailable => 'Connection list is unavailable.';

  @override
  String get connectionsFilterHint => 'Filter by domain, IP, process or rule';

  @override
  String connectionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count connections',
      one: '1 connection',
      zero: 'no connections',
    );
    return '$_temp0';
  }

  @override
  String get connectionsPause => 'Pause updates';

  @override
  String get connectionsResume => 'Resume updates';

  @override
  String get connectionsPaused => 'Paused';

  @override
  String get connectionsSourceApi => 'live from core';

  @override
  String get connectionsSourceLog => 'from core log';

  @override
  String get connectionsSourceUnavailable => 'no source';

  @override
  String get connectionsRuleHint => 'The core only logs which rule matched at log level Info.';

  @override
  String get connectionsRuleHintAction => 'Set Info';

  @override
  String get connectionsRuleHintApplied => 'Core log level set to Info — reconnect to apply';

  @override
  String get connectionsRuleDefault => 'no rule (default action)';

  @override
  String get connectionsRuleViaCore => 'decided inside the core (needs Info logs)';

  @override
  String get connectionsVerdictCore => 'CORE';

  @override
  String get connectionsVerdictProxy => 'PROXY';

  @override
  String get connectionsVerdictDirect => 'DIRECT';

  @override
  String get connectionsVerdictBlock => 'BLOCKED';

  @override
  String get connectionsClosed => 'closed';

  @override
  String get connectionsAppNamesHint => 'App names appear after reconnecting: the tunnel starts its detailed log together with debug mode.';

  @override
  String get connectionsSplitTunnelNote => 'Apps kept out of the tunnel are not listed here: Android routes them past it, so their traffic never reaches the core.';

  @override
  String subscriptionsExpiredOn(String date) {
    return 'Subscription expired on $date';
  }

  @override
  String get subscriptionsExpiredHint => 'The provider no longer updates the server list. Renew the subscription to keep it working.';

  @override
  String get subscriptionsExpiredNotifTitle => 'Subscription expired';

  @override
  String subscriptionsExpiredNotifBody(String name, String date) {
    return '\"$name\" expired on $date. The provider has stopped updating the server list — renew it to keep the servers working.';
  }

  @override
  String get chainTitle => 'Proxy chain';

  @override
  String get chainNew => 'New chain';

  @override
  String get chainCreate => 'Build a chain';

  @override
  String get chainCreateDesc => 'Send traffic through several servers in a row';

  @override
  String get chainGroupTitle => 'Chains';

  @override
  String get chainNameLabel => 'Chain name';

  @override
  String get chainNameHint => 'Leave empty to name it by the route';

  @override
  String get chainHint => 'Traffic goes top to bottom. The first node is the one this device connects to; the last one is the address sites see.';

  @override
  String get chainDeviceNode => 'This device';

  @override
  String get chainInternetNode => 'Internet';

  @override
  String get chainAddNode => 'Add node';

  @override
  String get chainRemoveNode => 'Remove node';

  @override
  String get chainExitNodeHint => 'Exit node — sites see this address';

  @override
  String get chainNodeMissing => 'Server is gone — using the saved copy';

  @override
  String get chainSave => 'Save chain';

  @override
  String get chainNeedsTwoNodes => 'A chain needs at least two nodes';

  @override
  String get chainPickNode => 'Choose a server';

  @override
  String get chainPickSearch => 'Search servers';

  @override
  String get chainPickEmpty => 'No servers can be a chain node here. VLESS, VMess, Trojan, Shadowsocks and Hysteria2 work; AmneziaWG and ready-made JSON configs do not.';

  @override
  String get chainEdit => 'Edit chain';

  @override
  String get chainDelete => 'Delete chain';

  @override
  String get chainRouteLabel => 'Route';

  @override
  String chainMaxNodes(int max) {
    return 'A chain holds at most $max nodes';
  }

  @override
  String chainDeleteConfirm(String name) {
    return 'Delete the chain \"$name\"? The servers it uses stay in the list.';
  }

  @override
  String chainNodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nodes',
      one: '1 node',
      zero: 'no nodes',
    );
    return '$_temp0';
  }

  @override
  String get settingsInternalsTitle => 'About';

  @override
  String get settingsInternalsSubtitle => 'Version, cores, geo databases and current session';

  @override
  String get settingsCoreXraySubtitle => 'Default core. Handles every server type, including chains and ready-made JSON configs.';

  @override
  String get settingsCoreMihomoSubtitle => 'Clash-compatible core. Chains and ready-made xray configs stay on Xray.';

  @override
  String get settingsCoreHint => 'Applies on the next connection — the running session is not restarted.';

  @override
  String get settingsProxyAuthTitle => 'Password for the local proxy';

  @override
  String get settingsProxyAuthSubtitle => 'Turn off for consumers with nowhere to enter it, like the Wi-Fi proxy fields';

  @override
  String get settingsProxyAuthUser => 'Username';

  @override
  String get settingsProxyAuthPass => 'Password';

  @override
  String get settingsTunnelModeSection => 'Connection mode';

  @override
  String get settingsTunnelModeVpn => 'VPN';

  @override
  String get settingsTunnelModeVpnSubtitle => 'All of the device\'s traffic goes through the tunnel';

  @override
  String get settingsTunnelModeProxy => 'Proxy';

  @override
  String get settingsTunnelModeProxySubtitle => 'A local proxy only — no system VPN, nothing is captured by itself';

  @override
  String get settingsTunnelModeHint => 'In Proxy mode the app opens SOCKS and HTTP on 127.0.0.1 and captures nothing on its own: point an app or the Wi-Fi proxy settings at it. The ports are in Settings → Local ports, and in this mode the local proxy asks for no password: the Wi-Fi proxy fields have nowhere to put one. Any app on the device can use it while the mode is on. Per-app routing and DNS interception belong to VPN mode; AmneziaWG servers always run as VPN.';

  @override
  String get settingsCoreAuto => 'Automatic';

  @override
  String get settingsCoreAutoSubtitle => 'The core is picked by the server\'s format: links run on Xray, ready-made configs run on the core they are written for.';

  @override
  String get settingsCoreSkipClash => 'The active server is a ready-made Clash config — only mihomo can run it, no matter which core is selected.';

  @override
  String get settingsCoreSkipCustom => 'The active server is a ready-made Xray JSON config (its routing and DNS come from the provider), so it runs on libxray no matter which core is selected. To use mihomo, take a subscription that hands out plain vless:// / vmess:// links — switch the client identity in the subscription\'s settings.';

  @override
  String get settingsCoreSkipChain => 'The active server is a proxy chain: its hops are linked by Xray\'s dialerProxy, so it runs on libxray no matter which core is selected.';

  @override
  String get settingsCoreSkipAwg => 'The active server is an AmneziaWG profile — it runs on its own core, wg-go, no matter which core is selected.';

  @override
  String get settingsCoreSkipPlatform => 'The mihomo core is not bundled for this platform, so the connection runs on the Xray core instead.';

  @override
  String get settingsInternalsCores => 'Cores';

  @override
  String get settingsInternalsGeo => 'Geo databases';

  @override
  String get settingsInternalsSession => 'Current session';

  @override
  String get settingsInternalsBuild => 'App and device';

  @override
  String get settingsInternalsCopyAll => 'Copy report';

  @override
  String get settingsInternalsCopied => 'Report copied to clipboard';

  @override
  String get settingsInternalsNoCores => 'No cores are bundled for this platform';

  @override
  String get settingsInternalsCoreMissing => 'not found';

  @override
  String get settingsInternalsVersionFromEngines => 'built from source';

  @override
  String get settingsInternalsRoleCore => 'Proxy engine and TUN';

  @override
  String get settingsInternalsRoleProxy => 'Proxy engine';

  @override
  String get settingsInternalsRoleTun => 'TUN device';

  @override
  String get settingsInternalsRoleAwg => 'AmneziaWG';

  @override
  String settingsInternalsGeoCodes(int count) {
    return 'codes: $count';
  }

  @override
  String get settingsInternalsStatus => 'Status';

  @override
  String get settingsInternalsStatusError => 'Error';

  @override
  String get settingsInternalsEngine => 'Engine';

  @override
  String get settingsInternalsMode => 'Mode';

  @override
  String get settingsInternalsPorts => 'Local ports';

  @override
  String get settingsInternalsClashPort => 'Clash API port';

  @override
  String get settingsInternalsUptime => 'Uptime';

  @override
  String get settingsInternalsCorePids => 'Core processes';

  @override
  String get settingsInternalsElevated => 'Administrator';

  @override
  String get settingsInternalsYes => 'yes';

  @override
  String get settingsInternalsNo => 'no';

  @override
  String get settingsInternalsAppVersion => 'App version';

  @override
  String get settingsInternalsPackage => 'Package';

  @override
  String get settingsInternalsOs => 'System';

  @override
  String get settingsInternalsAbi => 'Architecture';

  @override
  String get settingsInternalsDart => 'Dart';

  @override
  String get settingsInternalsBuildMode => 'Build';

  @override
  String get settingsInternalsUnavailable => '—';

  @override
  String get appearanceUiScaleTitle => 'Interface size';

  @override
  String get appearanceUiScaleSubtitle => 'Applied on top of the system text size, so 100% means \"as the system says\". Text and list rows resize; icons and spacing stay as they are.';

  @override
  String get appearanceIconShapeTitle => 'Icon shape';

  @override
  String get appearanceIconShapeCircle => 'Circle';

  @override
  String get subscriptionCardThemeTitle => 'Backdrop';

  @override
  String get subscriptionCardThemeNone => 'None';

  @override
  String get subscriptionCardThemeInServers => 'Show in server list';

  @override
  String get subscriptionCardThemeInServersHint => 'The picture also fills the group header. Colours taken from it stay either way.';

  @override
  String get subscriptionCardLookTitle => 'Card look';

  @override
  String get subscriptionCardVeilTitle => 'Image dimming';

  @override
  String get subscriptionCardVeilNone => 'Off';

  @override
  String get subscriptionCardVeilLight => 'Light';

  @override
  String get subscriptionCardVeilMedium => 'Medium';

  @override
  String get subscriptionCardVeilStrong => 'Heavy';

  @override
  String get subscriptionCardVeilHint => 'The text sits over the left side of the picture. Without dimming it can get lost on a light photo.';

  @override
  String get subscriptionCardContentTitle => 'What to show';

  @override
  String get subscriptionCardPresetFull => 'Full';

  @override
  String get subscriptionCardPresetCompact => 'Compact';

  @override
  String get subscriptionCardPresetMinimal => 'Minimal';

  @override
  String get subscriptionCardPresetCustom => 'Custom';

  @override
  String get subscriptionCardElementAnnounce => 'Provider announcement';

  @override
  String get subscriptionCardElementUsage => 'Traffic';

  @override
  String get subscriptionCardElementMeta => 'Expiry and last update';

  @override
  String get subscriptionCardElementActions => 'Buttons';

  @override
  String get subscriptionCardContentHint => 'Warnings are always shown: expired subscription, insecure link, failed update.';

  @override
  String get appearanceIconShapeSquare => 'Square';

  @override
  String get appearanceIconShapeArch => 'Arch';

  @override
  String get appearanceSectionServers => 'Server list and main screen';

  @override
  String get appearanceSectionFeel => 'Theme and feedback';

  @override
  String get appearanceIconShapeClover => 'Clover';

  @override
  String get appearanceIconShapeCookie => 'Cookie';

  @override
  String get appearanceIconShapeFlower => 'Flower';

  @override
  String get appearanceIconShapeSlanted => 'Slanted';

  @override
  String get appearanceIconShapePill => 'Pill';

  @override
  String get appearanceIconShapeGem => 'Gem';

  @override
  String get appearanceIconShapeSunny => 'Sunny';

  @override
  String get appearanceIconShapePuffy => 'Puffy';

  @override
  String get appearanceIconShapePebble => 'Pebble';

  @override
  String get cardImageRejectAspect => 'This image is too tall for a card. Pick a wide one — roughly from 3:2 to 5:1.';

  @override
  String cardImageRejectSmall(int width) {
    return 'Image is too small: at least $width px wide.';
  }

  @override
  String cardImageRejectLarge(int width) {
    return 'Image is too large: at most $width px wide.';
  }

  @override
  String get cardImageRejectUnreadable => 'Could not read this image.';
}
