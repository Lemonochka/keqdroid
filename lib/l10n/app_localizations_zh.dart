// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'KEQDIS';

  @override
  String vpnConnectedTo(Object serverName) {
    return '已连接到：$serverName';
  }

  @override
  String get vpnConnecting => '正在连接...';

  @override
  String get vpnDisconnecting => '正在断开...';

  @override
  String vpnTapToConnect(Object serverName) {
    return '点按以连接到 $serverName';
  }

  @override
  String get vpnSelectServer => '请在下方选择服务器';

  @override
  String get vpnSelectServerFirst => '请先选择服务器';

  @override
  String get updateTitle => '有可用更新';

  @override
  String get updateWhatsNew => '更新内容：';

  @override
  String get updateActionLater => '稍后';

  @override
  String get updateActionNow => '更新';

  @override
  String get errorSubscriptionTitle => '订阅错误';

  @override
  String get errorConnectionPermission => '连接失败：权限';

  @override
  String get errorConnectionNetwork => '连接失败：网络';

  @override
  String get errorConnectionConfig => '连接失败：配置';

  @override
  String get errorConnectionAuth => '连接失败：认证';

  @override
  String get errorConnectionGeneric => '连接错误';

  @override
  String get errorProviderConfigTitle => '需要配置提供商';

  @override
  String get errorProviderNoHostsMessage => '提供商未为此订阅分配主机。';

  @override
  String get errorProviderNoHostsAction => '打开提供商面板，添加或分配主机，然后刷新订阅。';

  @override
  String errorActionLabel(Object action) {
    return '操作：$action';
  }

  @override
  String get splitTunnelingTitle => '分应用代理';

  @override
  String get splitModeAllApps => '所有应用';

  @override
  String get splitModeSelectedOnly => '仅所选';

  @override
  String get splitModeAllExceptSelected => '除所选之外的全部';

  @override
  String get splitSearchHint => '搜索应用...';

  @override
  String get splitNoAppsFound => '未找到应用';

  @override
  String splitFailedLoadApps(Object error) {
    return '加载应用失败：$error';
  }

  @override
  String splitSelectedAppsCount(int count) {
    return '已选择 $count 个应用';
  }

  @override
  String get splitHideSystemApps => '隐藏系统应用';

  @override
  String get splitShowSystemApps => '显示系统应用';

  @override
  String get splitAddRussianAppsBypass => '将俄罗斯应用加入绕过列表';

  @override
  String get splitClear => '清除';

  @override
  String get splitNoRussianAppsFound => '在已安装应用列表中未找到俄罗斯应用';

  @override
  String get splitRussianAppsAlreadyAdded => '所有俄罗斯应用都已在绕过列表中';

  @override
  String splitAddedRussianApps(int count) {
    return '已将 $count 个俄罗斯应用加入绕过列表';
  }

  @override
  String get navServers => '服务器';

  @override
  String get navSubscriptions => '订阅';

  @override
  String get navSettings => '设置';

  @override
  String get serversEmptyTitle => '暂无服务器';

  @override
  String get serversEmptyHint => '在“订阅”标签页中添加订阅';

  @override
  String get subscriptionsTitle => '订阅';

  @override
  String get subscriptionsAddButton => '添加订阅';

  @override
  String get subscriptionsEmptyTitle => '暂无订阅';

  @override
  String get subscriptionsEmptyHint => '点按 + 以添加订阅 URL';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsThemeTitle => '主题';

  @override
  String get settingsSplitTitle => '分应用代理';

  @override
  String get settingsRoutingTitle => '路由规则';

  @override
  String settingsSplitConfigured(int count) {
    return '已配置 $count 个应用';
  }

  @override
  String get settingsRoutingSubtitle => '直连 / 代理 / 阻止规则及预设';

  @override
  String get settingsResetRoutingTitle => '重置路由为默认值';

  @override
  String get settingsResetRoutingSubtitle => '恢复内置路由规则';

  @override
  String get settingsRoutingResetDone => '路由规则已重置';

  @override
  String get settingsRoutingHeaderDesc =>
      '决定哪些站点直接绕过 VPN、哪些强制经过 VPN、哪些被阻止。可先使用预设快速开始，然后再微调下方的每个列表。';

  @override
  String get settingsRoutingPresetsTitle => '快速预设';

  @override
  String get settingsRoutingPresetsHint => '点按以添加精选列表。之后可以编辑或删除条目。';

  @override
  String get settingsRoutingPresetRuTitle => '俄罗斯站点 — 直连';

  @override
  String get settingsRoutingPresetRuDesc => '所有 .ru / .рф 及主要俄罗斯服务绕过 VPN';

  @override
  String get settingsRoutingPresetBanksTitle => '银行和政务 — 直连';

  @override
  String get settingsRoutingPresetBanksDesc => '银行、支付和政务门户绕过 VPN';

  @override
  String get settingsRoutingPresetAdsTitle => '广告和跟踪器 — 阻止';

  @override
  String get settingsRoutingPresetAdsDesc => '丢弃常见的广告 / 分析主机';

  @override
  String get settingsRoutingPresetStreamingTitle => '流媒体 — 代理';

  @override
  String get settingsRoutingPresetStreamingDesc =>
      '强制 YouTube、Netflix、Twitch 经过 VPN';

  @override
  String get settingsRoutingPresetMessengersTitle => '即时通讯 — 代理';

  @override
  String get settingsRoutingPresetMessengersDesc =>
      '强制 Telegram、Discord、WhatsApp 经过 VPN';

  @override
  String settingsRoutingPresetApplied(String name) {
    return '已添加“$name”';
  }

  @override
  String get settingsRoutingDirectTitle => '直连域名（绕过 VPN）';

  @override
  String get settingsRoutingDirectDesc => '这些主机将直接连接，不经过 VPN。';

  @override
  String get settingsRoutingProxyTitle => '代理域名（强制 VPN）';

  @override
  String get settingsRoutingProxyDesc => '这些主机始终经过 VPN。';

  @override
  String get settingsRoutingBlockTitle => '已阻止的域名';

  @override
  String get settingsRoutingBlockDesc => '这些主机将被丢弃且永不连接。';

  @override
  String get settingsRoutingDirectIpsTitle => '直连 IP / 子网（绕过 VPN）';

  @override
  String get settingsRoutingDirectIpsDesc => '绕过 VPN 的 IPv4/IPv6 地址或 CIDR 范围。';

  @override
  String get settingsRoutingValuesHint => '每行一个，或用逗号分隔';

  @override
  String get settingsRoutingSavedToast => '路由已更新';

  @override
  String settingsRoutingItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个条目',
      one: '1 个条目',
      zero: '空',
    );
    return '$_temp0';
  }

  @override
  String settingsAndroidColorsSubtitle(Object mode) {
    return 'Android 颜色 · $mode';
  }

  @override
  String settingsSystemColorsSubtitle(Object mode) {
    return '系统颜色 · $mode';
  }

  @override
  String get themeModeDark => '深色';

  @override
  String get themeModeLight => '浅色';

  @override
  String get themeCustomizationTitle => '主题自定义';

  @override
  String get themeUseDynamicColors => '使用 Android 动态颜色';

  @override
  String get themeUseDynamicColorsSubtitle => '在可用时使用 Android 动态颜色';

  @override
  String get themeDynamicPaletteHint => 'Android 动态调色板已启用。浅色/深色可独立工作。';

  @override
  String get themeSystemPaletteHint => '系统强调色调色板已启用。浅色/深色可独立工作。';

  @override
  String get themeUseSystemColors => '使用系统强调色';

  @override
  String get themeUseSystemColorsSubtitle => '在可用时跟随 Windows 或 Linux 的强调色';

  @override
  String get themeCustomPaletteHint => '自定义调色板已启用。浅色/深色可独立工作。';

  @override
  String get themeColorThemesTitle => '颜色主题';

  @override
  String get settingsLanProxyTitle => 'LAN 代理';

  @override
  String get settingsOff => '关闭';

  @override
  String settingsLanSharingOnIp(Object ip) {
    return '正在 $ip 上共享';
  }

  @override
  String get settingsHwidTitle => '发送设备 HWID';

  @override
  String get settingsHwidEnabledRecommended => '已启用（推荐）';

  @override
  String get settingsHwidDisabled => '已禁用';

  @override
  String get settingsHwidEnabledHint => '部分提供商需要 HWID 来进行订阅更新和设备数量限制。';

  @override
  String get settingsHwidDisabledHint => '不发送 HWID 头。如果提供商要求设备绑定，部分订阅可能会失败。';

  @override
  String get settingsDeviceIpListTitle => '设备在网络中的 IP 地址：';

  @override
  String get settingsIpCopied => 'IP 已复制';

  @override
  String get settingsSetupAnotherDeviceTitle => '在其他设备上设置：';

  @override
  String get settingsSocks5PortLabel => 'SOCKS5 端口';

  @override
  String get settingsHttpPortLabel => 'HTTP 端口';

  @override
  String get settingsTurnOffToChange => '关闭后才能更改此设置';

  @override
  String settingsProxyCopied(Object label, Object address) {
    return '已复制 $label $address';
  }

  @override
  String get settingsXrayCoreTitle => 'Xray 内核';

  @override
  String get settingsXrayCoreSubtitle => 'DNS、XMUX、日志与路由';

  @override
  String get settingsXrayDnsSection => 'DNS';

  @override
  String get settingsXrayDnsCustom => '自定义 DNS 服务器';

  @override
  String get settingsXrayDnsCustomHint => '每行一个地址（DoH、DoT 或普通）';

  @override
  String get settingsXrayDnsServers => 'DNS 服务器';

  @override
  String get settingsXrayDnsSplitDirect => '为直连域名使用独立解析器';

  @override
  String get settingsXrayDnsSplitDirectHint => '对直连列表中的域名使用第一个服务器';

  @override
  String get settingsXrayDnsQueryStrategy => '查询策略';

  @override
  String get settingsXrayDnsDisableCache => '禁用 DNS 缓存';

  @override
  String get settingsXrayXmuxSection => 'XMUX (XHTTP)';

  @override
  String get settingsXrayXmuxEnable => '启用 XMUX';

  @override
  String get settingsXrayXmuxEnableHint => '用于 XHTTP 传输的多路复用（客户端侧）';

  @override
  String get settingsXrayGeneralSection => '常规';

  @override
  String get settingsXrayLogLevel => '日志级别';

  @override
  String get settingsXrayDomainStrategy => '路由域名策略';

  @override
  String get settingsXraySniffing => '入站嗅探';

  @override
  String get settingsXraySniffingRouteOnly => '仅用于路由的嗅探';

  @override
  String get settingsXrayCoreIntro => '这些选项会被注入到生成的 Xray 配置中。仅在你了解其作用时才更改。';

  @override
  String get settingsXrayDnsDefaultNote => '默认：Cloudflare 和 Google DoH';

  @override
  String get settingsXrayXmuxParamsTitle => '微调';

  @override
  String get settingsXrayXmuxParamsHint => '留空以使用 Xray 默认值。可以是数字或范围（例如 16-32）。';

  @override
  String get settingsXraySniffingHint => '从入站流量中检测目标协议和域名';

  @override
  String get settingsXraySniffingRouteOnlyHint => '仅将嗅探用于路由，不覆盖目标地址';

  @override
  String get settingsXrayResetDefaults => '重置为默认值';

  @override
  String get settingsXrayResetDone => '已恢复 Xray 内核设置';

  @override
  String get settingsXrayXmuxMaxConcurrency => '最大并发数';

  @override
  String get settingsXrayXmuxMaxConnections => '最大连接数';

  @override
  String get settingsXrayXmuxCMaxReuseTimes => '连接复用上限';

  @override
  String get settingsXrayXmuxHMaxRequestTimes => '每个流的最大请求数';

  @override
  String get settingsXrayXmuxHMaxReusableSecs => '流复用时间（秒）';

  @override
  String get settingsXrayXmuxHKeepAlivePeriod => '保活周期（秒）';

  @override
  String get settingsPingTitle => '服务器 Ping';

  @override
  String get settingsPingMethodTitle => 'Ping 方式';

  @override
  String get settingsPingMethodTcp => 'TCP Ping';

  @override
  String get settingsPingMethodTcpHint => '快速可达性检查';

  @override
  String get settingsPingMethodUrl => '通过代理的 HTTP';

  @override
  String get settingsPingMethodUrlHint => '测量通过服务器的 GET 延迟';

  @override
  String get settingsPingMethodSpeed => '速度测试';

  @override
  String get settingsPingMethodSpeedHint =>
      '通过服务器下载固定大小的数据并以 Mbps 显示吞吐量（无需 VPN 即可工作）';

  @override
  String get settingsPingTargetTitle => 'HTTP 测试 URL';

  @override
  String get settingsPingTargetGstatic => 'Google (generate_204)';

  @override
  String get settingsPingTargetCloudflare => 'Cloudflare (trace)';

  @override
  String get settingsPingTargetMicrosoft => 'Microsoft (connect test)';

  @override
  String get settingsPingTargetCustom => '自定义 URL';

  @override
  String get settingsPingCustomUrl => 'URL';

  @override
  String get settingsPingCustomUrlHint => '用于 GET 请求的 https:// 或 http:// 地址';

  @override
  String get settingsPingCustomUrlInvalid => '无效或不安全的 URL（不允许 localhost 或私有网络）';

  @override
  String get subscriptionNameLabel => '名称';

  @override
  String get subscriptionNameHint => '我的订阅';

  @override
  String get subscriptionUrlLabel => 'URL';

  @override
  String get subscriptionUrlHint => 'https://example.com/sub?token=...';

  @override
  String get subscriptionsAddSubscription => '添加订阅';

  @override
  String get subscriptionsAddAndFetch => '添加并获取';

  @override
  String get subscriptionsEditSubscription => '编辑订阅';

  @override
  String get subscriptionsCopyUrl => '复制 URL';

  @override
  String get subscriptionsUrlCopied => 'URL 已复制';

  @override
  String get subscriptionsDeleteSubscription => '删除订阅';

  @override
  String subscriptionsDeleteConfirm(Object name) {
    return '确定要删除“$name”吗？\n\n这还会移除所有关联的服务器。';
  }

  @override
  String get subscriptionsRetry => '重试';

  @override
  String get subscriptionsCancel => '取消';

  @override
  String get subscriptionsDelete => '删除';

  @override
  String get subscriptionsSave => '保存';

  @override
  String get subscriptionsMoveUp => '上移';

  @override
  String get subscriptionsMoveDown => '下移';

  @override
  String get subscriptionsAutoUpdate => '自动更新';

  @override
  String get subscriptionsOn => '开';

  @override
  String get subscriptionsOff => '关';

  @override
  String get subscriptionsExpired => '已过期';

  @override
  String get subscriptionsRefreshFailed => '刷新失败';

  @override
  String get subscriptionsEveryHour => '每小时';

  @override
  String subscriptionsEveryHours(int hours) {
    return '每 $hours 小时';
  }

  @override
  String get subscriptionsEveryDay => '每天';

  @override
  String subscriptionsEveryDays(int days) {
    return '每 $days 天';
  }

  @override
  String get subscriptionsAutoUpdateInterval => '自动更新间隔';

  @override
  String subscriptionsCurrentInterval(int hours) {
    return '每 $hours 小时';
  }

  @override
  String get subscriptionsJustNow => '刚刚';

  @override
  String subscriptionsMinutesAgo(int minutes) {
    return '$minutes 分钟前';
  }

  @override
  String subscriptionsHoursAgo(int hours) {
    return '$hours 小时前';
  }

  @override
  String subscriptionsDaysAgo(int days) {
    return '$days 天前';
  }

  @override
  String subscriptionsInDays(int days) {
    return '$days 天后';
  }

  @override
  String subscriptionsInHours(int hours) {
    return '$hours 小时后';
  }

  @override
  String get subscriptionsSoon => '即将';

  @override
  String get serversAddServer => '添加服务器';

  @override
  String get serversPasteLinks => '粘贴链接';

  @override
  String get serversImportFile => '导入文件';

  @override
  String get serversNotSupported => '此版本不支持';

  @override
  String get serversAddServerTitle => '添加服务器';

  @override
  String get serversPasteVlessHint =>
      '粘贴 vless://、vmess://、trojan://、ss://、hysteria2:// 或 hy2://（每行一个）';

  @override
  String get serversPasteHint => 'vless://… 或 hy2://host:port?auth=…';

  @override
  String get serversAdd => '添加';

  @override
  String get serversManualServers => '手动服务器';

  @override
  String get serversRefreshSubscription => '刷新订阅';

  @override
  String get serversPingAll => '全部 Ping';

  @override
  String get settingsAdvanced => '高级';

  @override
  String get settingsAdvancedSubtitle => '内核设置、Ping、路由、HWID 和调试';

  @override
  String get settingsBackupRestore => '备份与恢复';

  @override
  String get settingsBackupRestoreSubtitle => '导出/导入分应用代理、订阅和服务器';

  @override
  String get settingsSelectAtLeastOne => '请至少选择一个要导出的部分';

  @override
  String get settingsBackupSaved => '备份保存成功';

  @override
  String get settingsSelectLocation => '选择备份的保存位置';

  @override
  String get settingsExportFile => '导出文件';

  @override
  String get settingsImportFile => '从文件导入';

  @override
  String get settingsImportBackup => '导入备份';

  @override
  String get settingsChooseWhatToImport => '选择要导入的内容（所选部分将替换你当前的数据）。';

  @override
  String get settingsSplitTunnelingApps => '分应用代理的应用';

  @override
  String get settingsSubscriptions => '订阅';

  @override
  String get settingsServersActive => '服务器（及当前活动服务器）';

  @override
  String get settingsImport => '导入';

  @override
  String get settingsExport => '导出';

  @override
  String get settingsCreateFileToSave => '创建一个可以保存并在其他设备上导入的文件。';

  @override
  String get settingsPickExportedFile => '选择先前导出的文件并恢复所选部分。';

  @override
  String get settingsWorking => '处理中...';

  @override
  String settingsImportedSections(int count) {
    return '已导入：$count 个部分';
  }

  @override
  String get settingsDebugMode => '调试模式';

  @override
  String get settingsDebugModeOn => '已启用扩展诊断';

  @override
  String get settingsDebugModeOff => '关闭';

  @override
  String get settingsDebugModeHint => '在服务器卡片中显示实时 VPN 指标，并允许查看 Xray 内核日志。';

  @override
  String get settingsOpenXrayLogs => '打开 Xray 日志';

  @override
  String get settingsXrayCoreLogs => 'Xray 内核日志';

  @override
  String get settingsRefresh => '刷新';

  @override
  String get settingsAppVersion => '应用版本';

  @override
  String get settingsChecking => '正在检查...';

  @override
  String get settingsCheckFailed => '检查失败';

  @override
  String get settingsUpdateAvailable => '有可用更新';

  @override
  String get settingsUpToDate => '已是最新';

  @override
  String get settingsNewVersionAvailable => '有新版本可用';

  @override
  String settingsSize(Object size) {
    return '大小：$size';
  }

  @override
  String get settingsDownloading => '正在下载...';

  @override
  String get settingsCheckForUpdates => '检查更新';

  @override
  String get settingsShareDeviceHwid => '共享设备 HWID';

  @override
  String get settingsHwidWillBeSent => 'HWID 将随订阅请求一起发送';

  @override
  String get settingsHwidNotShared => '不共享 HWID';

  @override
  String get settingsHwidHint =>
      '启用后，你设备的唯一 ID（HWID）会被发送到订阅服务器。部分提供商需要它进行 HWID 绑定。禁用可提升隐私。';

  @override
  String get settingsRoutingRules => '路由规则';

  @override
  String get settingsNoRules => '无规则';

  @override
  String get settingsAddCustomRule => '添加自定义规则';

  @override
  String get settingsAddRule => '添加规则';

  @override
  String get settingsEditRule => '编辑路由规则';

  @override
  String get settingsRuleName => '规则名称';

  @override
  String get settingsType => '类型';

  @override
  String get settingsAction => '操作';

  @override
  String get settingsValues => '值（要匹配的内容）';

  @override
  String get settingsOrder => '顺序（规则优先级）';

  @override
  String get settingsEnabled => '已启用';

  @override
  String get settingsNameAndValuesRequired => '名称和值为必填项';

  @override
  String get settingsUseOnePerLine => '每行使用一个值，或用逗号分隔。';

  @override
  String get settingsSmallerOrderFirst => '数字越小 = 越早检查（例如 1 在 50 之前）';

  @override
  String get settingsSmallerOrderWins => '如果两条规则可匹配相同流量，则顺序较小的规则优先。';

  @override
  String get settingsSaveChanges => '保存更改';

  @override
  String get settingsDeleteRule => '删除规则';

  @override
  String get settingsAddRuleTooltip => '添加规则';

  @override
  String get settingsDomain => '域名';

  @override
  String get settingsIpCidr => 'IP CIDR';

  @override
  String get settingsGeoIp => 'GeoIP';

  @override
  String get settingsGeosite => 'Geosite';

  @override
  String get settingsProcess => '进程';

  @override
  String get settingsProxy => '代理';

  @override
  String get settingsDirect => '直连';

  @override
  String get settingsBlock => '阻止';

  @override
  String get settingsEgDomain => '例如 youtube.com, +google';

  @override
  String get settingsEgIpCidr => '例如 1.1.1.1/32, 192.168.0.0/16';

  @override
  String get settingsEgGeoip => '例如 RU, US, DE';

  @override
  String get settingsEgGeosite => '例如 category-ads-all';

  @override
  String get settingsEgProcess => '例如 com.telegram.messenger';

  @override
  String settingsExportFailed(Object error) {
    return '导出失败：$error';
  }

  @override
  String settingsImportFailed(Object error) {
    return '导入失败：$error';
  }

  @override
  String settingsDownloadFailed(Object error) {
    return '下载失败：$error';
  }

  @override
  String settingsCheckFailedError(Object error) {
    return '检查失败：$error';
  }

  @override
  String get settingsNoXrayLogsYet => '暂无 Xray 日志';

  @override
  String get settingsLanguageTitle => '语言';

  @override
  String settingsLanguageSubtitle(Object language) {
    return '$language';
  }

  @override
  String get settingsLanguageSystem => '系统默认';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageGerman => 'Deutsch';

  @override
  String get settingsLanguageChinese => '中文';

  @override
  String get settingsLanguageSheetTitle => '选择语言';

  @override
  String get splitAddApp => '添加应用';

  @override
  String get splitAddAppTitle => '添加应用程序';

  @override
  String get splitAddAppHint => '.exe 路径或名称（例如 chrome.exe）';

  @override
  String get splitAddAppPickFile => '浏览…';

  @override
  String get splitAddAppInvalid => '请输入有效的 .exe 名称或路径';

  @override
  String splitAddAppAdded(Object name) {
    return '已添加：$name';
  }

  @override
  String get splitRunningApps => '运行中';

  @override
  String get splitInstalledApps => '已安装';

  @override
  String get splitCustomApps => '手动条目';

  @override
  String get splitClearAll => '全部清除';

  @override
  String get splitProxyModeWarning =>
      '在 Proxy 模式下不会应用分应用代理 — 所有流量都经过系统代理。请将连接模式切换为 TUN（在侧边栏中），这样按进程的规则才会生效。';

  @override
  String get settingsLatestVersionInstalled => '你已是最新版本';

  @override
  String get serversPingServer => 'Ping 服务器';

  @override
  String get serversHealthCheck => '健康检查';

  @override
  String get serversCopyAddress => '复制服务器地址';

  @override
  String get serversCopiedToClipboard => '已复制到剪贴板';

  @override
  String get serversCopyConfig => '复制配置';

  @override
  String get serversConfigCopied => '配置已复制';

  @override
  String get serversDeleteServer => '删除服务器';

  @override
  String get serversHealthCheckDesc => 'DNS、TCP 和配置校验';

  @override
  String get settingsDebugHintDesktop => '显示 Xray 会话日志。实时 VPN 指标显示在连接按钮下方。';

  @override
  String get settingsDebugHintMobile => '在服务器卡片中显示实时 VPN 指标和 Xray 日志。';

  @override
  String serversErrorLoadingApps(Object error) {
    return '加载应用出错：$error';
  }

  @override
  String get desktopConnectionMode => '连接模式';

  @override
  String get desktopModeShort => '模式';

  @override
  String get desktopDisconnectBeforeModeChange => '更改连接模式前请先断开连接';

  @override
  String get settingsDesktopTitle => 'Windows';

  @override
  String get settingsDesktopSubtitle => '托盘、开机启动、自动连接';

  @override
  String get settingsMinimizeToTray => '关闭时最小化到托盘';

  @override
  String get settingsMinimizeToTrayHint => '关闭后应用不会退出';

  @override
  String get settingsLaunchAtStartup => '随 Windows 启动';

  @override
  String get settingsLaunchAtStartupHint => '登录系统时启动应用';

  @override
  String get settingsAutoConnectOnAutostart => '启动时自动连接';

  @override
  String get settingsAutoConnectOnAutostartHint =>
      '连接上次选择的服务器，使用侧栏中的模式。TUN 需要管理员权限，否则使用 Proxy';

  @override
  String get settingsAutoConnectRequiresAutostart => '请先启用「随 Windows 启动」';

  @override
  String get desktopTunAdminTitle => '需要管理员权限';

  @override
  String get desktopTunAdminMessage =>
      'TUN 模式需要以管理员身份运行。请以管理员身份重启应用，侧栏中选择的模式会保留。';

  @override
  String get desktopTunAdminRestart => '以管理员身份重启';

  @override
  String get desktopTunAdminCancel => '取消';

  @override
  String get desktopTunAdminRestartFailed => '无法以管理员身份重启';
}
