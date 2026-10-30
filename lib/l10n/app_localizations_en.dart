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
  String get settingsRoutingTitle => 'Routing';

  @override
  String settingsSplitConfigured(int count) {
    return '$count apps configured';
  }

  @override
  String get settingsRoutingPresetsTitle => 'Ready-made lists';

  @override
  String get settingsRoutingPresetRuTitle => 'Russian sites';

  @override
  String get settingsRoutingPresetAdsTitle => 'Ads & trackers';

  @override
  String get settingsRoutingDirectTitle => 'Direct';

  @override
  String get settingsRoutingProxyTitle => 'Via VPN';

  @override
  String get settingsRoutingBlockTitle => 'Block';

  @override
  String get settingsRoutingFinalTitle => 'Everything else';

  @override
  String get settingsRoutingReconnect => 'Reconnect';

  @override
  String get routingCheatSheetTitle => 'How to write rules';

  @override
  String get routingCheatSheetBody => 'A route reads “who → what → where”. In Custom sites each line is a domain, an IP, a geo tag or a link to a list, and where they go is the route’s own choice: direct, via VPN or blocked.\n\n## Domains\nvk.com — the domain itself and all its subdomains\nru — anything ending in .ru (a bare word, no dot)\n.example.com — subdomains only, not the domain itself\nfull:example.com — exactly this host, no subdomains\nregexp:… — a regex, if you really need to get fancy\n\n## IP addresses\n1.2.3.4 — a single address\n10.0.0.0/8 — a whole range (CIDR)\n\n## GeoIP: by country\ngeoip:ru — every Russian IP. Swap ru for any country: us, de, cn, ua, kz…\nPlus ready-made bundles: geoip:private (LAN), geoip:telegram, geoip:google.\nNeed it by country? This is the one, geoip knows them all.\n\n## GeoSite: ready-made lists\ngeosite:google, geosite:netflix, geosite:telegram, geosite:category-ads-all…\nThese aren\'t countries but service categories someone already put together for you.\nHardly any countries here (just geolocation-cn and geolocation-!cn), so by-country is really geoip\'s job.\n\n## On PC\nGeo works the same as on the phone. It just needs geoip.dat and geosite.dat sitting next to keqdroid.exe. A release build already has them there. If geo rules look ignored, check those two files first.\n\n## Order\nTop to bottom, as on the screen: blocking, specific apps, all apps. Among all apps, Direct is checked before Via VPN. Your server always goes direct before anything else, or you would get a loop. Whatever matches no route follows the Everything else row.';

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
  String get routePickEmpty => 'No servers the current core can run as a separate outbound. A ready-made config fits only its own core, and chains fit only mihomo.';

  @override
  String settingsRoutingRouteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count routes',
      one: '1 route',
      zero: 'no routes',
    );
    return '$_temp0';
  }

  @override
  String get routesSectionBlock => 'Blocking';

  @override
  String get routesSectionApps => 'Apps';

  @override
  String get routesSectionAllApps => 'All apps';

  @override
  String get routesHint => 'The Direct, Via VPN and Block lists are now routes. Tap a route to change it.';

  @override
  String get routesHintDismiss => 'Got it';

  @override
  String get routeNew => 'New route';

  @override
  String get routeNewSubtitle => 'An app, sites or a ready-made list';

  @override
  String get routeNewSubtitleSites => 'Sites or a ready-made list';

  @override
  String get routeEditorTitle => 'Route';

  @override
  String get routeWho => 'Who';

  @override
  String get routeWhat => 'What';

  @override
  String get routeWhere => 'Where';

  @override
  String get routeWhoAllSubtitle => 'Everything that goes through the VPN';

  @override
  String get routeWhoApps => 'Specific apps';

  @override
  String routeWhoDone(int count) {
    return 'Done · $count';
  }

  @override
  String get routeWhatAll => 'All traffic';

  @override
  String get routeWhatAllSubtitle => 'Everything the app opens';

  @override
  String get routeWhatSites => 'Custom sites';

  @override
  String get routeWhatSitesSubtitle => 'Domains, IPs and links to lists';

  @override
  String routeWhatPresetValue(String name) {
    return 'Ready-made list · $name';
  }

  @override
  String routeWhatSitesValue(String entries) {
    return 'Custom sites · $entries';
  }

  @override
  String get routeWhereVpnSubtitle => 'Through the server the app is connected to';

  @override
  String get routeWhereDirectSubtitle => 'Bypassing the VPN';

  @override
  String get routeWhereBlockSubtitle => 'Connections are not opened';

  @override
  String get routeWhereServers => 'Another server';

  @override
  String get routeToVpn => 'via VPN';

  @override
  String get routeToDirect => 'direct';

  @override
  String get routeToBlock => 'block';

  @override
  String get routeAllTrafficShort => 'all traffic';

  @override
  String get routeDisabledShort => 'off';

  @override
  String get routeEnabled => 'Route enabled';

  @override
  String get routeDeleteConfirm => 'Delete this route?';

  @override
  String get routeServerMissing => 'server is gone, goes via VPN';

  @override
  String get routeServerUnsupported => 'the current core can\'t use this server, goes via VPN';

  @override
  String get routeAppsUnsupported => 'the current core can\'t tell apps apart, the route does nothing';

  @override
  String get routeAppsNeedTun => 'works only in TUN mode';

  @override
  String get routeAppsNeedVpn => 'works only in VPN mode';

  @override
  String get routingProfileMain => 'Main';

  @override
  String get routingIgnoreProviderRules => 'Ignore provider rules';

  @override
  String get routingIgnoreProviderRulesHint => 'Only your routes apply';

  @override
  String get routingProfileScopeAll => 'All subscriptions and your own servers';

  @override
  String get routingProfileScopeRest => 'Other subscriptions and your own servers';

  @override
  String routingProfileRouteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count routes',
      one: '1 route',
      zero: 'no routes',
    );
    return '$_temp0';
  }

  @override
  String routingProfileFinal(String target) {
    return 'everything else → $target';
  }

  @override
  String get routingProfileOff => 'Off: the main profile applies';

  @override
  String get routingProfileNoSubscriptions => 'Not linked to any subscription';

  @override
  String get routingProfileNew => 'New profile';

  @override
  String get routingProfileName => 'Name';

  @override
  String get routingProfileForSubscriptions => 'For subscriptions';

  @override
  String routingProfileSubOnOther(String name) {
    return 'now on profile “$name”';
  }

  @override
  String get routingProfileStartFrom => 'Start from';

  @override
  String get routingProfileStartCopy => 'A copy of the main profile';

  @override
  String get routingProfileStartCopyHint => 'The same routes, then adjust them for the subscription';

  @override
  String get routingProfileStartEmpty => 'An empty profile';

  @override
  String get routingProfileStartEmptyHint => 'Only everything else through the VPN';

  @override
  String get routingProfileCreate => 'Create';

  @override
  String get routingProfileNoSubscriptionsYet => 'No subscriptions yet: a profile applies to the servers of subscriptions';

  @override
  String get routingProfileRenameTitle => 'Rename profile';

  @override
  String get routingProfileSubscriptions => 'Subscriptions';

  @override
  String routingProfileDeleteConfirm(String name) {
    return 'Delete the profile “$name”? Its subscriptions go back to the main profile.';
  }

  @override
  String routeSplitExcluded(String apps) {
    return 'split tunneling sends $apps around the VPN';
  }

  @override
  String get routeRefilterUnmatched => 'Everything else now goes direct';

  @override
  String settingsRoutingLinkDomains(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted domains from links',
      one: '1 domain from links',
    );
    return '$_temp0';
  }

  @override
  String settingsRoutingCountWithLinks(String items, String links) {
    return '$items, $links';
  }

  @override
  String ruleListDomainCount(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted domains',
      one: '1 domain',
    );
    return '$_temp0';
  }

  @override
  String ruleListLoaded(String host, String domains, String when) {
    return '$host — $domains, updated $when';
  }

  @override
  String ruleListLoadedStale(String host, String domains, String when) {
    return '$host — $domains, updated $when; the latest copy did not download';
  }

  @override
  String ruleListLoading(String host) {
    return '$host — downloading…';
  }

  @override
  String ruleListFailedNetwork(String host) {
    return '$host — not downloaded, will retry on the next connection';
  }

  @override
  String ruleListFailedInsecure(String host) {
    return '$host — the link must start with https';
  }

  @override
  String ruleListFailedHttp(String host, int code) {
    return '$host — the server replied $code';
  }

  @override
  String ruleListFailedTooLarge(String host) {
    return '$host — the file is larger than 30 MB';
  }

  @override
  String ruleListFailedEmpty(String host) {
    return '$host — no domains in the file';
  }

  @override
  String ruleListMemoryWarning(String limit) {
    return 'More than $limit domains from links: the core will need much more memory, and the system may close it in the background.';
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
  String get themePaletteHint => 'Light/Dark still switches on its own';

  @override
  String get themeUseSystemColors => 'Use system accent colors';

  @override
  String get themeColorThemesTitle => 'Color themes';

  @override
  String get serversColumnsTitle => 'Multiple columns';

  @override
  String get serversColumnsNoRoom => 'Don\'t fit at this interface size';

  @override
  String serversColumnsOnlyFit(int count) {
    return 'Only $count fit at this interface size';
  }

  @override
  String get appearanceServerIconThemeColors => 'Flagless server icons in theme colours';

  @override
  String get settingsLanProxyTitle => 'LAN Proxy';

  @override
  String get settingsOff => 'Off';

  @override
  String settingsLanSharingOnIp(Object ip) {
    return 'Sharing on $ip';
  }

  @override
  String settingsLanFirewallHint(Object ports) {
    return 'If other devices cannot connect, open ports $ports in the firewall:';
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
  String get settingsLanAuthHint => 'With both fields set, devices sign in to the proxy with them. Left empty, there is no password and anyone on your network can use it.';

  @override
  String get settingsLocalPortsTitle => 'Local proxy ports';

  @override
  String get settingsLocalPortsHint => 'SOCKS5 and HTTP, default 2080 / 2081, must differ. Applied on next connection.';

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
  String get settingsXrayCoreSubtitle => 'DNS, Mux, fragmentation, TUN and logs';

  @override
  String get settingsXrayDnsSection => 'DNS';

  @override
  String get settingsXrayDnsCustom => 'Custom DNS servers';

  @override
  String get settingsXrayDnsCustomHint => 'One address per line (DoH, DoT, or plain)';

  @override
  String get settingsXrayDnsCustomHintXray => 'One address per line (DoH or plain), Xray has no DoT';

  @override
  String get settingsXrayDnsServers => 'DNS servers';

  @override
  String get settingsXrayDnsSplitDirect => 'Split resolver for direct domains';

  @override
  String get settingsXrayDnsSplitDirectHint => 'Uses first server for domains from direct list';

  @override
  String get settingsXrayDnsSplitDirectSystemHint => 'Domains from the direct list are resolved by the system DNS';

  @override
  String get settingsXrayDnsHosts => 'Own addresses for domains';

  @override
  String get settingsXrayDnsPolicy => 'Resolver for specific domains';

  @override
  String get settingsXrayDnsQueryStrategy => 'Query strategy';

  @override
  String get settingsXrayDnsDisableCache => 'Disable DNS cache';

  @override
  String get settingsXrayXmuxSection => 'XMUX (XHTTP)';

  @override
  String get settingsXrayXmuxEnable => 'Custom XMUX values';

  @override
  String get settingsXrayXmuxEnableHint => 'Otherwise Xray keeps up to 3 connections and replaces each after 600-900 requests or 30-50 minutes';

  @override
  String get settingsXrayMuxSection => 'Mux';

  @override
  String get settingsXrayMuxEnable => 'Enable Mux';

  @override
  String get settingsXrayMuxEnableHint => 'Many connections inside one: fewer handshakes, but usually worse on downloads and speed tests.';

  @override
  String get settingsXrayMuxParamsTitle => 'Streams per connection';

  @override
  String get settingsXrayMuxParamsHint => '-1 turns multiplexing off. TCP up to 128, UDP up to 1024.';

  @override
  String get settingsXrayMuxConcurrency => 'TCP streams';

  @override
  String get settingsXrayMuxXudpConcurrency => 'UDP streams (XUDP)';

  @override
  String get settingsXrayMuxUdp443Title => 'QUIC (UDP/443)';

  @override
  String get settingsXrayMuxUdp443Reject => 'Reject';

  @override
  String get settingsXrayMuxUdp443Allow => 'Send through Mux';

  @override
  String get settingsXrayMuxUdp443Skip => 'Bypass Mux';

  @override
  String get settingsXrayGeneralSection => 'General';

  @override
  String get settingsXrayLogLevel => 'Log level';

  @override
  String get settingsXrayDomainStrategy => 'Routing domain strategy';

  @override
  String get settingsXrayConcurrentDial => 'Dial every address at once';

  @override
  String get settingsXrayConcurrentDialHint => 'Helps when some of the server\'s addresses are blocked';

  @override
  String get settingsXraySniffing => 'Detect domains in traffic (sniffing)';

  @override
  String get settingsXraySniffingRouteOnly => 'Sniffed domain for routing only';

  @override
  String get settingsXrayDnsDefaultNote => 'Default: Cloudflare and Google DoH';

  @override
  String get settingsXrayXmuxParamsTitle => 'Tuning';

  @override
  String get settingsXrayXmuxParamsHint => 'Blank uses the Xray default. A number or a range, e.g. 16-32.';

  @override
  String get settingsXraySniffingHint => 'Detect destination protocol and domain from inbound traffic';

  @override
  String get settingsXraySniffingRouteOnlyHint => 'The sniffed domain only picks the routing rule; the connection still goes to the address the app gave.';

  @override
  String get settingsXrayUdpPerAddress => 'Route UDP by each destination address';

  @override
  String get settingsXrayUdpPerAddressHint => 'The exit follows the rules for every destination address, not the first packet of a socket. P2P over STUN (calls, games, torrents) may not connect directly when the rules send the STUN server and the peer to different exits.';

  @override
  String get settingsXrayResetDefaults => 'Reset to defaults';

  @override
  String get settingsXrayResetDone => 'Xray core settings restored';

  @override
  String get settingsXrayXmuxMaxConcurrency => 'Max concurrency';

  @override
  String get settingsXrayXmuxMaxConnections => 'Max connections';

  @override
  String get settingsXrayXmuxOneOfTwo => 'Only one of the two';

  @override
  String get settingsXrayXmuxConnectionsIgnored => 'Ignored while max concurrency is set';

  @override
  String get settingsXrayXmuxCMaxReuseTimes => 'Connection reuse limit';

  @override
  String get settingsXrayXmuxHMaxRequestTimes => 'Max requests per stream';

  @override
  String get settingsXrayXmuxHMaxReusableSecs => 'Stream reuse time (sec)';

  @override
  String get settingsXrayXmuxHKeepAlivePeriod => 'Keep-alive period (sec)';

  @override
  String get settingsXrayFragmentSection => 'Fragmentation';

  @override
  String get settingsXrayFragmentEnable => 'Split the TLS ClientHello';

  @override
  String get settingsXrayFragmentEnableHint => 'The first packet goes out in pieces, so DPI cannot read the SNI.';

  @override
  String get settingsXrayNoiseSection => 'UDP noise';

  @override
  String get settingsXrayNoiseEnable => 'Send noise before UDP';

  @override
  String get settingsXrayNoiseEnableHint => 'A junk packet goes to the server before the first real one. For hysteria and mkcp, where there is no ClientHello to cut.';

  @override
  String get settingsXrayNoiseKindTitle => 'What to send';

  @override
  String get settingsXrayNoiseKindRand => 'Random junk';

  @override
  String get settingsXrayNoiseKindStr => 'Own packet: text';

  @override
  String get settingsXrayNoiseKindHex => 'Own packet: hex';

  @override
  String get settingsXrayNoiseKindBase64 => 'Own packet: base64';

  @override
  String get settingsXrayNoisePacket => 'Packet';

  @override
  String get settingsXrayNoiseRandLength => 'Length, bytes';

  @override
  String get settingsXrayNoiseRandBytes => 'Byte values (0-255)';

  @override
  String get settingsXrayNoiseDelay => 'Delay, ms';

  @override
  String get settingsXrayNoiseReset => 'Repeat, sec';

  @override
  String get settingsXrayNoiseParamsHint => 'A number or a range, e.g. 50-100. Blank leaves it to the core.';

  @override
  String get settingsXrayFragmentPacketsTitle => 'What to split';

  @override
  String get settingsXrayFragmentPacketsTlsHello => 'TLS ClientHello only';

  @override
  String get settingsXrayFragmentPacketsFirst => 'First packets of the stream';

  @override
  String get settingsXrayFragmentParamsTitle => 'Piece size and delay';

  @override
  String get settingsXrayFragmentParamsHint => 'A number or a range, e.g. 100-200.';

  @override
  String get settingsXrayFragmentLength => 'Size, bytes';

  @override
  String get settingsXrayFragmentInterval => 'Delay, ms';

  @override
  String get settingsTunSection => 'TUN mode';

  @override
  String get settingsTunSectionNote => 'Applied on next connection.';

  @override
  String get settingsTunStackTitle => 'Network stack';

  @override
  String get settingsTunStackSystemHint => 'OS stack: the fastest, needs a firewall rule on Windows.';

  @override
  String get settingsTunStackGvisorHint => 'Userspace stack: no listener, no firewall rules, slightly slower. Needs a core built with gVisor.';

  @override
  String get settingsTunStackMixedHint => 'system for TCP, gVisor for UDP. Like system, needs a firewall rule on Windows. Needs a core built with gVisor.';

  @override
  String get settingsTunStackMipsHint => 'Mihomo\'s own userspace stack instead of gVisor: lighter, with selectable TCP congestion control. Only on the mihomo core.';

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
  String get settingsTunAutoRoute => 'Auto route';

  @override
  String get settingsTunAutoRouteHint => 'Adds system routes into the tunnel. Without it nothing reaches TUN.';

  @override
  String get settingsTunIpv6 => 'Keep IPv6 inside the tunnel';

  @override
  String get settingsTunIpv6Hint => 'Gives the TUN interface an IPv6 address; without it all IPv6 bypasses the tunnel.';

  @override
  String get settingsFakeIp => 'Fake IP';

  @override
  String get settingsFakeIpHint => 'Instant resolution via fake addresses. Not used in Proxy mode.';

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
  String get settingsPingKeepAliveTitle => 'How it\'s measured';

  @override
  String get settingsPingKeepAlive => 'Measure on a warm connection';

  @override
  String get settingsPingKeepAliveHint => 'The request goes out twice and the second one counts, so the handshake stays out of the number. Off: a single request with the warm-up, like opening a site for the first time.';

  @override
  String get settingsPingAutoTitle => 'When to ping';

  @override
  String get settingsPingAuto => 'Ping automatically';

  @override
  String get settingsPingAutoHint => 'When the app opens and right after a subscription updates';

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
  String subscriptionsQrSaved(Object path) {
    return 'QR code saved: $path';
  }

  @override
  String subscriptionsQrSaveFailed(Object error) {
    return 'Could not save the QR code: $error';
  }

  @override
  String get subscriptionsQrSaveTitle => 'Save QR code';

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
  String get subscriptionIdentityHwidOff => 'Sharing the device HWID is turned off in Advanced settings, so no HWID is sent, custom or not.';

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
  String get subscriptionIdentitySectionUaAndroid => 'Android clients';

  @override
  String get subscriptionIdentitySectionUaApple => 'iPhone & iPad clients';

  @override
  String get subscriptionIdentitySectionUaDesktop => 'Desktop clients';

  @override
  String get subscriptionIdentitySectionUaCores => 'Cores & plain http';

  @override
  String get subscriptionIdentitySectionOs => 'OS';

  @override
  String get subscriptionIdentitySectionApple => 'iPhone & iPad';

  @override
  String get subscriptionIdentitySectionDesktop => 'Desktop';

  @override
  String get subscriptionIdentitySectionAndroidRelease => 'Android releases';

  @override
  String get subscriptionIdentitySectionAndroidBuild => 'Android builds';

  @override
  String get subscriptionIdentitySectionIosRelease => 'iOS releases';

  @override
  String get subscriptionIdentitySectionIosBuild => 'iOS builds';

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
  String get serversPasteLinksHint => 'Server links or a whole config';

  @override
  String get serversImportFile => 'Import file';

  @override
  String get serversImportFileHint => 'A file with server links or a config';

  @override
  String get serversAddServerTitle => 'Add Server';

  @override
  String get serversPasteVlessHint => 'One link per line, or a whole config: Xray, Clash, sing-box, AmneziaWG';

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
  String get settingsChooseWhatToImport => 'Selected sections replace your current data';

  @override
  String get settingsSplitTunnelingApps => 'Split tunneling apps';

  @override
  String get settingsSubscriptions => 'Subscriptions';

  @override
  String get settingsServersActive => 'Servers (and active server)';

  @override
  String get settingsAppSettings => 'App settings';

  @override
  String get settingsImport => 'Import';

  @override
  String get settingsExport => 'Export';

  @override
  String get settingsCreateFileToSave => 'The file can be moved to another device';

  @override
  String get settingsPickExportedFile => 'You pick what to restore after choosing the file';

  @override
  String get settingsWorking => 'Working...';

  @override
  String settingsImportedSections(int count) {
    return 'Imported: $count section(s)';
  }

  @override
  String get settingsShareHwidTitle => 'Share device HWID';

  @override
  String get settingsShareHwidOn => 'Sent with subscription requests';

  @override
  String get settingsShareHwidOff => 'Not shared';

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
  String get splitAddAppHintLinux => 'Path to the program or its name (e.g. firefox)';

  @override
  String get splitAddAppInvalidLinux => 'Enter a program name or path';

  @override
  String splitAddAppAdded(Object name) {
    return 'Added: $name';
  }

  @override
  String get splitProxyModeWarning => 'Split tunneling is not applied in Proxy mode: all traffic goes through the system proxy. Switch the connection mode to TUN (in the side panel) so per-process rules work.';

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
  String get settingsDesktopTitleLinux => 'Linux';

  @override
  String get settingsDesktopSubtitle => 'Tray, autostart, auto-connect';

  @override
  String get settingsMinimizeToTray => 'Minimize to tray on close';

  @override
  String get settingsLaunchAtStartup => 'Start with Windows';

  @override
  String get settingsLaunchAtLogin => 'Start at login';

  @override
  String get settingsLaunchAtStartupAdmin => 'Start with admin rights';

  @override
  String get settingsAutostartInTray => 'Start in the tray, without a window';

  @override
  String get settingsAutostartAdminFailed => 'Administrator rights were not granted';

  @override
  String get settingsAutoConnectOnAutostart => 'Connect on autostart';

  @override
  String get settingsAutoConnectRequiresAutostart => 'Enable \"Start with Windows\" first';

  @override
  String get settingsAutoConnectRequiresLogin => 'Enable \"Start at login\" first';

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
  String get desktopRailCollapse => 'Collapse panel';

  @override
  String get desktopRailExpand => 'Expand panel';

  @override
  String get serversScrollToEnd => 'Jump to end';

  @override
  String get serversScrollToTop => 'Jump to top';

  @override
  String get serversJumpToActive => 'Show in list';

  @override
  String get exitIpLabel => 'IP that websites see';

  @override
  String get serversAutoSelect => 'Auto';

  @override
  String get serversAutoSelectTooltip => 'The app picks the server in this subscription and switches when it stops working';

  @override
  String get serversManualGroup => 'Manual servers';

  @override
  String get serversEmptyGroupHint => 'No servers in this subscription';

  @override
  String get statsInLabel => 'In';

  @override
  String get statsTimeLabel => 'Time';

  @override
  String get statsDownloadLabel => 'Download speed';

  @override
  String get statsUploadLabel => 'Upload speed';

  @override
  String get statsSplitVpnTag => 'VPN';

  @override
  String get statsSplitDirectTag => 'direct';

  @override
  String get statsSplitVpnLabel => 'Through the VPN';

  @override
  String get statsSplitDirectLabel => 'Bypassing the VPN';

  @override
  String get statsSplitTotalLabel => 'Transferred';

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
  String get tvReceiveTitle => 'Receive from phone';

  @override
  String get tvReceiveSubtitle => 'A subscription from your phone over Wi-Fi';

  @override
  String get tvReceiveHint => 'Scan the code in keqdroid on your phone. The phone and the TV must be on the same Wi-Fi network.';

  @override
  String get tvReceiveWaiting => 'Waiting for a subscription…';

  @override
  String tvReceiveGot(Object name) {
    return 'Received: $name';
  }

  @override
  String tvReceiveFailed(Object error) {
    return 'Couldn\'t add it: $error';
  }

  @override
  String get tvReceiveNoNetwork => 'The TV isn\'t connected to a network';

  @override
  String get tvSendTitle => 'Send to TV';

  @override
  String get tvSendPick => 'Which subscription do you want to send?';

  @override
  String get tvSendAction => 'Send';

  @override
  String get tvSendDone => 'Subscription sent to the TV';

  @override
  String get tvSendNothing => 'There are no subscriptions on this phone to send';

  @override
  String get tvSendUnreachable => 'The TV isn\'t responding. Check that the phone and the TV are on the same Wi-Fi network and the receive screen is open on the TV.';

  @override
  String get tvSendExpired => 'This code has expired. Reopen the receive screen on the TV and scan the new code.';

  @override
  String tvSendRejected(Object error) {
    return 'The TV didn\'t add the subscription: $error';
  }

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
  String get hotkeyActionToggleTun => 'Switch TUN / Proxy';

  @override
  String get hotkeyActionBestPing => 'Switch to the best-ping server';

  @override
  String get hotkeyActionToggleWindow => 'Show / hide window';

  @override
  String get hotkeyNotSet => 'Not set';

  @override
  String get hotkeyPressKeys => 'Press a shortcut…';

  @override
  String get hotkeyRecordingHint => 'Esc cancels, Backspace clears';

  @override
  String get hotkeyNeedsModifier => 'Use a modifier (Ctrl/Alt/Shift/Win) or an F-key';

  @override
  String hotkeyConflictTaken(Object combo) {
    return 'Shortcut $combo is already taken by another app';
  }

  @override
  String get hotkeyClearTooltip => 'Clear shortcut';

  @override
  String get hotkeyNoPingData => 'No ping results yet, run a ping test first';

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
  String get errorTunAdapterRefusedTitle => 'Windows Refused the Adapter';

  @override
  String get errorTunAdapterRefusedMessage => 'Windows refused the TUN adapter three times in a row. The server is fine.';

  @override
  String get errorTunAdapterRefusedAction => 'Connect again in a minute or restart the computer. Proxy mode still works.';

  @override
  String get errorPolkitMissingTitle => 'Polkit Required';

  @override
  String get errorPolkitMissingMessage => 'TUN mode starts the core as root through pkexec, and polkit is not installed.';

  @override
  String get errorPolkitMissingAction => 'Install polkit together with an authentication agent, run the app as root (sudo -E keqdroid), or switch to Proxy mode in settings.';

  @override
  String get errorPolkitNoAgentTitle => 'Polkit Required';

  @override
  String get errorPolkitNoAgentMessage => 'Nothing answered the request for root: no polkit authentication agent is running.';

  @override
  String get errorPolkitNoAgentAction => 'Start a polkit agent for your desktop (polkit-gnome, lxqt-policykit and the like), or switch to Proxy mode in settings.';

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
  String get subInsecureHttpWarning => 'http link, updates are blocked';

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
  String get serverEditorPinnedCert => 'Pinned certificate (SHA-256)';

  @override
  String get serverEditorVerifyCertName => 'Verify certificate name';

  @override
  String get serverEditorPqv => 'Post-quantum key (ML-DSA-65)';

  @override
  String get serverEditorEarlyData => 'Early data, bytes';

  @override
  String get serverEditorPadding => 'Padding, bytes';

  @override
  String get serverEditorExtra => 'Extra (JSON)';

  @override
  String get serverEditorAuthority => 'Authority';

  @override
  String get serverEditorSeed => 'Seed';

  @override
  String get serverEditorHttpMethod => 'HTTP method';

  @override
  String get serverEditorIssueVision => 'Vision only works on TCP with TLS or REALITY.';

  @override
  String get serverEditorIssueFlow => 'The core does not know this flow and will refuse the whole config.';

  @override
  String get serverEditorIssueRealityTransport => 'REALITY does not run over this transport.';

  @override
  String get serverEditorIssueRealityKey => 'REALITY needs the server public key.';

  @override
  String get serverEditorIssueEncryption => 'Encryption must be none or an mlkem768x25519plus key.';

  @override
  String get serverEditorIssueNoSecurity => 'Without TLS, REALITY or Encryption the core only allows private addresses.';

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
  String get serverEditorOverriddenNote => 'Config edited manually, so subscription updates no longer replace it.';

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
  String get appearanceAmoledNeedsDark => 'Available with the dark theme on';

  @override
  String get appearanceHalloween => 'Show holiday decorations';

  @override
  String get appearanceHalloweenUntil => 'Until November 2';

  @override
  String get appearanceHaptics => 'Vibration';

  @override
  String get appearanceShowTraffic => 'Traffic speed and volume';

  @override
  String get appearanceShowTime => 'Connection time';

  @override
  String get appearanceShowTrafficSplit => 'VPN and direct traffic separately';

  @override
  String get appearanceWaveLatencyColor => 'Wave colour by ping';

  @override
  String get appearanceFontTitle => 'Font';

  @override
  String get appearanceFontSystem => 'System';

  @override
  String get settingsResetConfirmTitle => 'Reset settings?';

  @override
  String get settingsResetConfirmAction => 'Reset';

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
  String get settingsPermBatteryTitle => 'Unrestricted background work';

  @override
  String get settingsPermBatteryDesc => 'Without it the system can block starting the VPN from the tile';

  @override
  String get settingsPermAutostartTitle => 'Autostart';

  @override
  String get settingsPermAutostartDesc => 'Firmware setting: without it the VPN may not start from the tile and may shut down in the background';

  @override
  String get settingsPermAutostartHint => 'Find auto-launch and background activity (usually under Battery) and allow them';

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
  String get settingsPermTunHeader => 'TUN mode (Linux)';

  @override
  String get settingsPermTunPasswordlessTitle => 'Passwordless TUN';

  @override
  String get settingsPermTunDisabled => 'Passwordless TUN disabled';

  @override
  String get appearanceNotifSectionTitle => 'Notifications';

  @override
  String get appearanceNotifSpeedTitle => 'Connection speed in notification';

  @override
  String get appearanceNotifUptimeTitle => 'Connection time in notification';

  @override
  String get appearanceNotifSubUpdatesTitle => 'Subscription update notifications';

  @override
  String get tunRememberInstalled => 'Passwordless TUN enabled';

  @override
  String get tunRememberFailed => 'Could not change TUN authorization';

  @override
  String get settingsRoutingPresetRefilterTitle => 'Blocked in Russia (Re-filter)';

  @override
  String get settingsRoutingPresetWhitelistTitle => 'Russian mobile whitelists';

  @override
  String get settingsRoutingGeoUnknownTitle => 'Missing from the geo databases, will be ignored';

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
  String get connectionsRuleHint => 'The core logs domains and the matched rule only at log level Info.';

  @override
  String get connectionsRuleHintAction => 'Set Info';

  @override
  String get connectionsRuleHintApplied => 'Core log level set to Info, reconnect to apply';

  @override
  String get connectionsRuleDefault => 'no rule (default action)';

  @override
  String get connectionsRuleViaCore => 'decided inside the core (needs Info logs)';

  @override
  String get connectionsRuleViaCoreUnseen => 'the core decides, its decision is not in the log';

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
  String get connectionsAppNamesHint => 'App names come from the system, and it knows only live connections, so closed ones stay unnamed.';

  @override
  String get connectionsSplitTunnelNote => 'Apps kept out of the tunnel are not listed here: Android routes them past it. A row with the outside-vpn rule means such an app pushed a connection into the tunnel itself and the core refused it.';

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
    return '\"$name\" expired on $date. The provider has stopped updating the server list. Renew it to keep the servers working.';
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
  String get chainExitNodeHint => 'Exit node, sites see this address';

  @override
  String get chainNodeMissing => 'Server is gone, using the saved copy';

  @override
  String get chainSave => 'Save chain';

  @override
  String get chainNeedsTwoNodes => 'A chain needs at least two nodes';

  @override
  String get chainPickNode => 'Choose a server';

  @override
  String get chainPickSearch => 'Search servers';

  @override
  String chainPickEmpty(String core) {
    return 'No servers here can be a chain node for $core. Another core can be picked in About.';
  }

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
  String get settingsCoreXraySubtitle => 'Default core. Runs links, chains and ready-made Xray configs.';

  @override
  String get settingsCoreMihomoSubtitle => 'Clash-compatible core. Ready-made xray configs stay on Xray.';

  @override
  String get settingsCoreHint => 'Applies on the next connection, the running session is not restarted.';

  @override
  String get settingsProxyAuthTitle => 'Password for the local proxy';

  @override
  String get settingsProxyAuthSubtitle => 'Turn off where there is nowhere to enter it, like the Wi-Fi proxy field';

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
  String get settingsTunnelModeProxySubtitle => 'Local proxy only, no system VPN';

  @override
  String get settingsTunnelModeHint => 'Proxy mode runs SOCKS and HTTP on 127.0.0.1, so point an app or Wi-Fi at them. The proxy is open to every app on the device. Per-app routing and DNS interception need VPN mode.';

  @override
  String get settingsCoreSkipClash => 'The active server is a ready-made Clash config, and only mihomo can run it, no matter which core is selected.';

  @override
  String get settingsCoreSkipCustom => 'The active server is a ready-made Xray JSON config, so it runs on libxray whatever core you pick. mihomo needs a subscription with plain links.';

  @override
  String get settingsCoreSkipChainXrayOnly => 'The active server is a proxy chain with nodes mihomo cannot link, so it runs on Xray no matter which core is selected.';

  @override
  String get settingsCoreSkipChainMihomoOnly => 'The active server is a proxy chain with a node only mihomo can link, such as an AmneziaWG profile, so it runs on mihomo no matter which core is selected.';

  @override
  String get settingsCoreSkipAwg => 'The active server is an AmneziaWG profile, and it runs on mihomo no matter which core is selected.';

  @override
  String get settingsCoreSkipPlatform => 'The mihomo core is not bundled for this platform, so the connection runs on the Xray core instead.';

  @override
  String get settingsCoreSkipLinkXrayOnly => 'The active server\'s link uses a transport mihomo has no fields for in this protocol, so it runs on Xray no matter which core is selected.';

  @override
  String get settingsCoreSkipLinkMihomoOnly => 'The active server\'s link uses a transport Xray 26 removed, so it runs on mihomo no matter which core is selected.';

  @override
  String get settingsInternalsCores => 'Cores';

  @override
  String get settingsInternalsGeo => 'Geo databases';

  @override
  String get settingsInternalsSession => 'Current session';

  @override
  String get settingsInternalsExits => 'Why the app was closed';

  @override
  String get settingsInternalsExitsHint => 'The system keeps these records itself. If the VPN turned off in the background, copy them with the button at the top and send them.';

  @override
  String get settingsInternalsExitSystem => 'Stopped by the system or firmware';

  @override
  String get settingsInternalsExitMemory => 'The system ran out of memory';

  @override
  String get settingsInternalsExitCrash => 'The app crashed';

  @override
  String get settingsInternalsExitUser => 'Closed manually';

  @override
  String get settingsInternalsExitUserOrUpdate => 'Closed manually or by an update';

  @override
  String get settingsInternalsExitUpdate => 'App update or permission change';

  @override
  String get settingsInternalsExitSelf => 'The app exited on its own';

  @override
  String get settingsInternalsExitVpnOn => 'VPN was on';

  @override
  String get appLogTitle => 'App log';

  @override
  String get appLogSubtitle => 'What happened and what failed, by part of the app';

  @override
  String get appLogSourceApp => 'App';

  @override
  String get appLogSourceAppDesc => 'Interface, subscriptions, connecting';

  @override
  String get appLogSourceNative => 'Native part';

  @override
  String get appLogSourceNativeDesc => 'VPN service, Quick Settings tile, connect window';

  @override
  String get appLogSourceExitsDesc => 'System records: when and why the app was closed';

  @override
  String appLogProblems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problems',
      one: '1 problem',
      zero: 'No problems',
    );
    return '$_temp0';
  }

  @override
  String get appLogOnlyProblems => 'Problems only';

  @override
  String get appLogEmpty => 'Nothing here yet';

  @override
  String get appLogCopyAll => 'Copy the whole log';

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
  String settingsInternalsGeoCodes(int count) {
    return 'codes: $count';
  }

  @override
  String get settingsInternalsGeoTrimmed => 'Country database is the trimmed one';

  @override
  String get settingsInternalsGeoTrimmedHint => 'Only the codes the app\'s own presets need; a rule with any other country is dropped.';

  @override
  String get settingsInternalsGeoDownload => 'Download the full database';

  @override
  String settingsInternalsGeoDownloadFailed(String error) {
    return 'Could not download: $error';
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
  String get appearanceCustomColorTitle => 'Custom color';

  @override
  String get appearanceCustomColorSheetTitle => 'Your color';

  @override
  String get appearanceCustomColorHue => 'Hue';

  @override
  String get appearanceCustomColorSaturation => 'Saturation';

  @override
  String get appearanceCustomColorBrightness => 'Brightness';

  @override
  String get appearanceCustomColorHex => 'HEX code';

  @override
  String get appearanceCustomColorInvalid => 'Six hex digits, for example 7B2CBF';

  @override
  String get appearanceCustomColorApply => 'Apply';

  @override
  String get appearanceCustomColorVariant => 'Palette';

  @override
  String get appearanceCustomColorVariantCalm => 'Calm';

  @override
  String get appearanceCustomColorVariantVibrant => 'Vibrant';

  @override
  String get appearanceCustomColorVariantExact => 'Exact';

  @override
  String get appearanceCustomColorVariantHint => 'Saturation and brightness only tell on Exact: the other two pick them for you.';

  @override
  String get appearanceUiScaleTitle => 'Interface size';

  @override
  String get appearanceUiScaleSubtitle => 'The whole interface, on top of the system scale.';

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
  String get subscriptionCardAutoSelect => 'Auto toggle in the server list';

  @override
  String get subscriptionCardAutoSelectHint => 'Adds an «Auto» switch to the group header. With it on, the app picks the server itself and moves to another one when the current stops working.';

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
  String get appearanceSectionServers => 'Server list';

  @override
  String get appearanceSectionUnderButton => 'Under the connect button';

  @override
  String get appearanceSectionConnectPanel => 'Main screen';

  @override
  String get appearanceConnectPanelLegacy => 'Legacy';

  @override
  String get appearanceConnectPanelModern => 'Modern';

  @override
  String get appearanceBarMainland => 'Mainland';

  @override
  String get appearanceBarIslands => 'Islands';

  @override
  String get appearancePartTop => 'Top of the screen';

  @override
  String get appearancePartBottom => 'Bottom bar';

  @override
  String get appearanceSectionFeel => 'Touch feedback';

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
  String get cardImageRejectAspect => 'This image is too tall for a card. Pick a wide one, roughly from 3:2 to 5:1.';

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
