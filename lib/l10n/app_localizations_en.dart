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
  String get errorProviderNoHostsMessage =>
      'Provider has no hosts assigned to this subscription.';

  @override
  String get errorProviderNoHostsAction =>
      'Open provider panel, add or assign hosts, then refresh subscription.';

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
  String get splitNoRussianAppsFound =>
      'No Russian apps found in the installed apps list';

  @override
  String get splitRussianAppsAlreadyAdded =>
      'All Russian apps already in bypass list';

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
  String get settingsThemeTitle => 'Theme';

  @override
  String get settingsSplitTitle => 'Split Tunneling';

  @override
  String get settingsRoutingTitle => 'Routing Rules';

  @override
  String settingsSplitConfigured(int count) {
    return '$count apps configured';
  }

  @override
  String get settingsRoutingSubtitle =>
      'Direct / proxy / block rules and presets';

  @override
  String get settingsResetRoutingTitle => 'Reset routing to defaults';

  @override
  String get settingsResetRoutingSubtitle => 'Restore built-in routing rules';

  @override
  String get settingsRoutingResetDone => 'Routing rules reset';

  @override
  String get settingsRoutingHeaderDesc =>
      'Decide which sites go directly past the VPN, which are forced through it, and which are blocked. Use a preset for a quick start, then fine-tune each list below.';

  @override
  String get settingsRoutingPresetsTitle => 'Quick presets';

  @override
  String get settingsRoutingPresetsHint =>
      'Tap to add a curated list. You can edit or remove entries afterwards.';

  @override
  String get settingsRoutingPresetRuTitle => 'Russian sites — Direct';

  @override
  String get settingsRoutingPresetRuDesc =>
      'All .ru / .рф and major RU services bypass the VPN';

  @override
  String get settingsRoutingPresetBanksTitle => 'Banks & gov — Direct';

  @override
  String get settingsRoutingPresetBanksDesc =>
      'Banking, payments and state portals bypass the VPN';

  @override
  String get settingsRoutingPresetAdsTitle => 'Ads & trackers — Block';

  @override
  String get settingsRoutingPresetAdsDesc => 'Drop common ad / analytics hosts';

  @override
  String get settingsRoutingPresetStreamingTitle => 'Streaming — Proxy';

  @override
  String get settingsRoutingPresetStreamingDesc =>
      'Force YouTube, Netflix, Twitch through the VPN';

  @override
  String get settingsRoutingPresetMessengersTitle => 'Messengers — Proxy';

  @override
  String get settingsRoutingPresetMessengersDesc =>
      'Force Telegram, Discord, WhatsApp through the VPN';

  @override
  String settingsRoutingPresetApplied(String name) {
    return 'Added \"$name\"';
  }

  @override
  String get settingsRoutingDirectTitle => 'Direct domains (bypass VPN)';

  @override
  String get settingsRoutingDirectDesc =>
      'These hosts connect directly, without the VPN.';

  @override
  String get settingsRoutingProxyTitle => 'Proxy domains (force VPN)';

  @override
  String get settingsRoutingProxyDesc =>
      'These hosts always go through the VPN.';

  @override
  String get settingsRoutingBlockTitle => 'Blocked domains';

  @override
  String get settingsRoutingBlockDesc =>
      'These hosts are dropped and never connect.';

  @override
  String get settingsRoutingDirectIpsTitle =>
      'Direct IPs / subnets (bypass VPN)';

  @override
  String get settingsRoutingDirectIpsDesc =>
      'IPv4/IPv6 addresses or CIDR ranges that bypass the VPN.';

  @override
  String get settingsRoutingValuesHint => 'One per line, or comma separated';

  @override
  String get settingsRoutingSavedToast => 'Routing updated';

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
  String get themeCustomizationTitle => 'Theme customization';

  @override
  String get themeUseDynamicColors => 'Use Android dynamic colors';

  @override
  String get themeUseDynamicColorsSubtitle =>
      'Use Android dynamic colors when available';

  @override
  String get themeDynamicPaletteHint =>
      'Dynamic Android palette is active. Light/Dark works independently.';

  @override
  String get themeSystemPaletteHint =>
      'System accent palette is active. Light/Dark works independently.';

  @override
  String get themeUseSystemColors => 'Use system accent colors';

  @override
  String get themeUseSystemColorsSubtitle =>
      'Follow Windows or Linux accent colors when available';

  @override
  String get themeCustomPaletteHint =>
      'Custom palette is active. Light/Dark works independently.';

  @override
  String get themeColorThemesTitle => 'Color themes';

  @override
  String get settingsLanProxyTitle => 'LAN Proxy';

  @override
  String get settingsOff => 'Off';

  @override
  String settingsLanSharingOnIp(Object ip) {
    return 'Sharing on $ip';
  }

  @override
  String get settingsHwidTitle => 'Send device HWID';

  @override
  String get settingsHwidEnabledRecommended => 'Enabled (recommended)';

  @override
  String get settingsHwidDisabled => 'Disabled';

  @override
  String get settingsHwidEnabledHint =>
      'Some providers require HWID for subscription updates and device limits.';

  @override
  String get settingsHwidDisabledHint =>
      'HWID headers are not sent. Some subscriptions may fail if provider requires device binding.';

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
  String get settingsTurnOffToChange => 'Turn off to change setting';

  @override
  String settingsProxyCopied(Object label, Object address) {
    return '$label $address copied';
  }

  @override
  String get settingsXrayCoreTitle => 'Xray core';

  @override
  String get settingsXrayCoreSubtitle => 'DNS, XMUX, log and routing';

  @override
  String get settingsXrayDnsSection => 'DNS';

  @override
  String get settingsXrayDnsCustom => 'Custom DNS servers';

  @override
  String get settingsXrayDnsCustomHint =>
      'One address per line (DoH, DoT, or plain)';

  @override
  String get settingsXrayDnsServers => 'DNS servers';

  @override
  String get settingsXrayDnsSplitDirect => 'Split resolver for direct domains';

  @override
  String get settingsXrayDnsSplitDirectHint =>
      'Uses first server for domains from direct list';

  @override
  String get settingsXrayDnsQueryStrategy => 'Query strategy';

  @override
  String get settingsXrayDnsDisableCache => 'Disable DNS cache';

  @override
  String get settingsXrayXmuxSection => 'XMUX (XHTTP)';

  @override
  String get settingsXrayXmuxEnable => 'Enable XMUX';

  @override
  String get settingsXrayXmuxEnableHint =>
      'Multiplexing for XHTTP transport (client-side)';

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
  String get settingsXrayCoreIntro =>
      'These options are injected into the generated Xray config. Change only if you know what they do.';

  @override
  String get settingsXrayDnsDefaultNote => 'Default: Cloudflare and Google DoH';

  @override
  String get settingsXrayXmuxParamsTitle => 'Tuning';

  @override
  String get settingsXrayXmuxParamsHint =>
      'Leave empty to use Xray defaults. Values can be a number or range (e.g. 16-32).';

  @override
  String get settingsXraySniffingHint =>
      'Detect destination protocol and domain from inbound traffic';

  @override
  String get settingsXraySniffingRouteOnlyHint =>
      'Use sniffing for routing only, without overriding the destination';

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
  String get settingsPingTitle => 'Server ping';

  @override
  String get settingsPingMethodTitle => 'Ping method';

  @override
  String get settingsPingMethodTcp => 'TCP ping';

  @override
  String get settingsPingMethodTcpHint => 'Fast reachability check';

  @override
  String get settingsPingMethodUrl => 'HTTP via proxy';

  @override
  String get settingsPingMethodUrlHint =>
      'Measures GET latency through the server';

  @override
  String get settingsPingMethodSpeed => 'Speed test';

  @override
  String get settingsPingMethodSpeedHint =>
      'Downloads a fixed payload through the server and shows throughput in Mbps (works without VPN)';

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
  String get settingsPingCustomUrlHint =>
      'https:// or http:// address for GET request';

  @override
  String get settingsPingCustomUrlInvalid =>
      'Invalid or unsafe URL (no localhost or private networks)';

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
  String get subscriptionsMoveUp => 'Move up';

  @override
  String get subscriptionsMoveDown => 'Move down';

  @override
  String get subscriptionsAutoUpdate => 'Auto-update';

  @override
  String get subscriptionsOn => 'ON';

  @override
  String get subscriptionsOff => 'OFF';

  @override
  String get subscriptionsExpired => 'Expired';

  @override
  String get subscriptionsRefreshFailed => 'Refresh failed';

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
  String get serversNotSupported => 'Not supported in this build';

  @override
  String get serversAddServerTitle => 'Add Server';

  @override
  String get serversPasteVlessHint =>
      'Paste vless://, vmess://, trojan://, ss://, hysteria2:// or hy2:// (one per line)';

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
  String get settingsAdvancedSubtitle =>
      'Core settings, ping, routing, HWID and debug';

  @override
  String get settingsBackupRestore => 'Backup & restore';

  @override
  String get settingsBackupRestoreSubtitle =>
      'Export/import split tunneling, subscriptions and servers';

  @override
  String get settingsSelectAtLeastOne =>
      'Select at least one section to export';

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
  String get settingsChooseWhatToImport =>
      'Choose what to import (selected sections will replace your current data).';

  @override
  String get settingsSplitTunnelingApps => 'Split tunneling apps';

  @override
  String get settingsSubscriptions => 'Subscriptions';

  @override
  String get settingsServersActive => 'Servers (and active server)';

  @override
  String get settingsImport => 'Import';

  @override
  String get settingsExport => 'Export';

  @override
  String get settingsCreateFileToSave =>
      'Create a file you can save and import on another device.';

  @override
  String get settingsPickExportedFile =>
      'Pick a previously exported file and restore selected sections.';

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
  String get settingsDebugModeHint =>
      'Shows live VPN metrics in server cards and allows viewing Xray core logs.';

  @override
  String get settingsOpenXrayLogs => 'Open Xray logs';

  @override
  String get settingsXrayCoreLogs => 'Xray core logs';

  @override
  String get settingsRefresh => 'Refresh';

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
  String settingsSize(Object size) {
    return 'Size: $size';
  }

  @override
  String get settingsDownloading => 'Downloading...';

  @override
  String get settingsCheckForUpdates => 'Check for updates';

  @override
  String get settingsShareDeviceHwid => 'Share device HWID';

  @override
  String get settingsHwidWillBeSent =>
      'HWID will be sent with subscription requests';

  @override
  String get settingsHwidNotShared => 'HWID not shared';

  @override
  String get settingsHwidHint =>
      'When enabled, your device\'s unique ID (HWID) is sent to subscription servers. Required by some providers for HWID binding. Disable to increase privacy.';

  @override
  String get settingsRoutingRules => 'Routing Rules';

  @override
  String get settingsNoRules => 'No rules';

  @override
  String get settingsAddCustomRule => 'Add custom rule';

  @override
  String get settingsAddRule => 'Add rule';

  @override
  String get settingsEditRule => 'Edit routing rule';

  @override
  String get settingsRuleName => 'Rule name';

  @override
  String get settingsType => 'Type';

  @override
  String get settingsAction => 'Action';

  @override
  String get settingsValues => 'Values (what to match)';

  @override
  String get settingsOrder => 'Order (rule priority)';

  @override
  String get settingsEnabled => 'Enabled';

  @override
  String get settingsNameAndValuesRequired => 'Name and values are required';

  @override
  String get settingsUseOnePerLine =>
      'Use one value per line, or separate with commas.';

  @override
  String get settingsSmallerOrderFirst =>
      'Smaller number = checked earlier (e.g. 1 before 50)';

  @override
  String get settingsSmallerOrderWins =>
      'If two rules can match the same traffic, the rule with smaller order wins.';

  @override
  String get settingsSaveChanges => 'Save changes';

  @override
  String get settingsDeleteRule => 'Delete rule';

  @override
  String get settingsAddRuleTooltip => 'Add rule';

  @override
  String get settingsDomain => 'Domain';

  @override
  String get settingsIpCidr => 'IP CIDR';

  @override
  String get settingsGeoIp => 'GeoIP';

  @override
  String get settingsGeosite => 'Geosite';

  @override
  String get settingsProcess => 'Process';

  @override
  String get settingsProxy => 'Proxy';

  @override
  String get settingsDirect => 'Direct';

  @override
  String get settingsBlock => 'Block';

  @override
  String get settingsEgDomain => 'e.g. youtube.com, +google';

  @override
  String get settingsEgIpCidr => 'e.g. 1.1.1.1/32, 192.168.0.0/16';

  @override
  String get settingsEgGeoip => 'e.g. RU, US, DE';

  @override
  String get settingsEgGeosite => 'e.g. category-ads-all';

  @override
  String get settingsEgProcess => 'e.g. com.telegram.messenger';

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
  String get settingsNoXrayLogsYet => 'No Xray logs yet';

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
  String get splitRunningApps => 'Running';

  @override
  String get splitInstalledApps => 'Installed';

  @override
  String get splitCustomApps => 'Manual entries';

  @override
  String get splitClearAll => 'Clear all';

  @override
  String get splitProxyModeWarning =>
      'Split tunneling is not applied in Proxy mode — all traffic goes through the system proxy. Switch the connection mode to TUN (in the side panel) so per-process rules work.';

  @override
  String get settingsLatestVersionInstalled => 'You have the latest version';

  @override
  String get serversPingServer => 'Ping server';

  @override
  String get serversHealthCheck => 'Health check';

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
  String get serversHealthCheckDesc => 'DNS, TCP and config validation';

  @override
  String get settingsDebugHintDesktop =>
      'Shows Xray session logs. Live VPN metrics are shown under the connect button.';

  @override
  String get settingsDebugHintMobile =>
      'Shows live VPN metrics in server cards and Xray logs.';

  @override
  String serversErrorLoadingApps(Object error) {
    return 'Error loading apps: $error';
  }

  @override
  String get desktopConnectionMode => 'Connection mode';

  @override
  String get desktopModeShort => 'Mode';

  @override
  String get desktopDisconnectBeforeModeChange =>
      'Disconnect before changing connection mode';

  @override
  String get settingsDesktopTitle => 'Windows';

  @override
  String get settingsDesktopSubtitle => 'Tray, autostart, auto-connect';

  @override
  String get settingsMinimizeToTray => 'Minimize to tray on close';

  @override
  String get settingsMinimizeToTrayHint =>
      'When off, closing the window exits the app';

  @override
  String get settingsLaunchAtStartup => 'Start with Windows';

  @override
  String get settingsLaunchAtStartupHint => 'Launch the app when you sign in';

  @override
  String get settingsAutoConnectOnAutostart => 'Connect on autostart';

  @override
  String get settingsAutoConnectOnAutostartHint =>
      'Connect to the last selected server using the mode from the sidebar. If TUN needs admin rights and they are unavailable, Proxy is used';

  @override
  String get settingsAutoConnectRequiresAutostart =>
      'Enable \"Start with Windows\" first';

  @override
  String get desktopTunAdminTitle => 'Administrator rights required';

  @override
  String get desktopTunAdminMessage =>
      'TUN mode needs administrator rights. Restart the app as administrator to use TUN. The current mode in the sidebar will be kept.';

  @override
  String get desktopTunAdminRestart => 'Restart as administrator';

  @override
  String get desktopTunAdminCancel => 'Cancel';

  @override
  String get desktopTunAdminRestartFailed =>
      'Could not restart as administrator';
}
