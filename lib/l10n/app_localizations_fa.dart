// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class AppLocalizationsFa extends AppLocalizations {
  AppLocalizationsFa([String locale = 'fa']) : super(locale);

  @override
  String get appTitle => 'KEQDIS';

  @override
  String vpnConnectedTo(Object serverName) {
    return 'متصل به: $serverName';
  }

  @override
  String get vpnConnecting => 'در حال اتصال...';

  @override
  String get vpnDisconnecting => 'در حال قطع اتصال...';

  @override
  String vpnTapToConnect(Object serverName) {
    return 'برای اتصال به $serverName ضربه بزنید';
  }

  @override
  String get vpnSelectServer => 'یک سرور از پایین انتخاب کنید';

  @override
  String get vpnSelectServerFirst => 'اول یک سرور انتخاب کنید';

  @override
  String get updateTitle => 'نسخهٔ جدید موجود است';

  @override
  String get updateWhatsNew => 'تازه‌ها:';

  @override
  String get updateActionLater => 'بعداً';

  @override
  String get updateActionNow => 'به‌روزرسانی';

  @override
  String get updateApplying => 'در حال اعمال به‌روزرسانی...';

  @override
  String get errorSubscriptionTitle => 'خطای اشتراک';

  @override
  String get errorConnectionPermission => 'اتصال ناموفق: دسترسی';

  @override
  String get errorConnectionNetwork => 'اتصال ناموفق: شبکه';

  @override
  String get errorConnectionConfig => 'اتصال ناموفق: کانفیگ';

  @override
  String get errorConnectionAuth => 'اتصال ناموفق: احراز هویت';

  @override
  String get errorConnectionGeneric => 'خطای اتصال';

  @override
  String get errorProviderConfigTitle => 'تنظیم در پنل سرویس‌دهنده لازم است';

  @override
  String get errorProviderNoHostsMessage => 'سرویس‌دهنده هیچ هاستی به این اشتراک اختصاص نداده است.';

  @override
  String get errorProviderNoHostsAction => 'وارد پنل سرویس‌دهنده شوید، هاست اضافه یا اختصاص دهید و بعد اشتراک را به‌روزرسانی کنید.';

  @override
  String errorActionLabel(Object action) {
    return 'راه‌حل: $action';
  }

  @override
  String get splitTunnelingTitle => 'پروکسی به تفکیک برنامه';

  @override
  String get splitModeAllApps => 'همهٔ برنامه‌ها';

  @override
  String get splitModeSelectedOnly => 'فقط انتخاب‌شده‌ها';

  @override
  String get splitModeAllExceptSelected => 'همه به‌جز انتخاب‌شده‌ها';

  @override
  String get splitSearchHint => 'جست‌وجوی برنامه...';

  @override
  String get splitNoAppsFound => 'برنامه‌ای پیدا نشد';

  @override
  String splitFailedLoadApps(Object error) {
    return 'بارگذاری برنامه‌ها ناموفق بود: $error';
  }

  @override
  String splitSelectedAppsCount(int count) {
    return '$count برنامهٔ انتخاب‌شده';
  }

  @override
  String get splitHideSystemApps => 'پنهان کردن برنامه‌های سیستمی';

  @override
  String get splitShowSystemApps => 'نمایش برنامه‌های سیستمی';

  @override
  String get splitAddRussianAppsBypass => 'افزودن برنامه‌های روسی به فهرست بدون VPN';

  @override
  String get splitClear => 'پاک‌سازی';

  @override
  String get splitNoRussianAppsFound => 'در فهرست برنامه‌های نصب‌شده، برنامهٔ روسی پیدا نشد';

  @override
  String get splitRussianAppsAlreadyAdded => 'همهٔ برنامه‌های روسی از قبل در فهرست بدون VPN هستند';

  @override
  String splitAddedRussianApps(int count) {
    return '$count برنامهٔ روسی به فهرست بدون VPN اضافه شد';
  }

  @override
  String get navServers => 'سرورها';

  @override
  String get navSubscriptions => 'اشتراک‌ها';

  @override
  String get navSettings => 'تنظیمات';

  @override
  String get serversEmptyTitle => 'هنوز سروری ندارید';

  @override
  String get serversEmptyHint => 'از بخش «اشتراک‌ها» یک اشتراک اضافه کنید';

  @override
  String get subscriptionsTitle => 'اشتراک‌ها';

  @override
  String get subscriptionsAddButton => 'افزودن اشتراک';

  @override
  String get subscriptionsEmptyTitle => 'اشتراکی ندارید';

  @override
  String get subscriptionsEmptyHint => 'برای افزودن لینک اشتراک روی + بزنید';

  @override
  String get settingsTitle => 'تنظیمات';

  @override
  String get settingsThemeTitle => 'ظاهر';

  @override
  String get settingsSplitTitle => 'پروکسی به تفکیک برنامه';

  @override
  String get settingsRoutingTitle => 'مسیریابی';

  @override
  String settingsSplitConfigured(int count) {
    return '$count برنامه تنظیم شده';
  }

  @override
  String get settingsRoutingPresetsTitle => 'فهرست‌های آماده';

  @override
  String get settingsRoutingPresetRuTitle => 'سایت‌های روسی';

  @override
  String get settingsRoutingPresetAdsTitle => 'تبلیغات و ردیاب‌ها';

  @override
  String get settingsRoutingDirectTitle => 'مستقیم';

  @override
  String get settingsRoutingProxyTitle => 'پروکسی';

  @override
  String get settingsRoutingBlockTitle => 'مسدود';

  @override
  String get settingsRoutingFinalTitle => 'بقیهٔ ترافیک';

  @override
  String get settingsRoutingReconnect => 'اتصال دوباره';

  @override
  String get routingCheatSheetTitle => 'نحوهٔ نوشتن قوانین';

  @override
  String get routingCheatSheetBody => 'هر مسیر سه بخش دارد: کدام برنامه، چه ترافیکی، به کجا. در «سایت‌های دلخواه» هر خط یک دامنه، آی‌پی، برچسب جغرافیایی یا لینک فهرست است و مقصد را خود مسیر تعیین می‌کند: مستقیم، پروکسی یا مسدود.\n\n## دامنه‌ها\nvk.com — خود دامنه و همهٔ زیردامنه‌هایش\nru — هر چیزی که به ‎.ru‎ ختم شود (یک کلمه، بدون نقطه)\n‎.example.com‎ — فقط زیردامنه‌ها، نه خود دامنه\nfull:example.com — دقیقاً همین هاست، بدون زیردامنه\n‎regexp:…‎ — عبارت منظم، اگر واقعاً لازم شد\n\n## آدرس‌های آی‌پی\n1.2.3.4 — یک آدرس\n10.0.0.0/8 — یک بازهٔ کامل (CIDR)\n\n## GeoIP: بر اساس کشور\ngeoip:ru — همهٔ آی‌پی‌های روسیه. به‌جای ru هر کشوری را بگذارید: ‎us، de، cn، ua، kz…‎\nبه‌علاوه بسته‌های آماده: geoip:private (شبکهٔ محلی)، geoip:telegram، geoip:google.\nتفکیک بر اساس کشور لازم دارید؟ همین است؛ geoip همهٔ کشورها را می‌شناسد.\n\n## GeoSite: فهرست‌های آماده\n‎geosite:google, geosite:netflix, geosite:telegram, geosite:category-ads-all…‎\nاین‌ها کشور نیستند، بلکه دسته‌بندی سرویس‌هایی‌اند که از قبل برایتان جمع شده.\nکشور اینجا تقریباً نیست (فقط geolocation-⁠cn و geolocation-⁠!⁠cn)، پس برای کشورها از geoip استفاده کنید.\n\n## روی کامپیوتر\nقانون‌های جغرافیایی مثل موبایل کار می‌کنند. فقط باید geoip.dat و geosite.dat کنار keqdroid.exe باشند؛ در نسخهٔ رسمی از قبل آنجا هستند. اگر قانون‌های جغرافیایی نادیده گرفته می‌شوند، اول همین دو فایل را بررسی کنید.\n\n## ترتیب\nمثل صفحه، از بالا به پایین: مسدودسازی، برنامه‌های مشخص، همهٔ برنامه‌ها. در همهٔ برنامه‌ها «مستقیم» پیش از «پروکسی» بررسی می‌شود. سرور خودتان همیشه پیش از همه مستقیم می‌رود، وگرنه حلقه ایجاد می‌شود. هرچه با هیچ مسیری جور نشود، از ردیف «بقیهٔ ترافیک» پیروی می‌کند.';

  @override
  String settingsRoutingItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مورد',
      one: '1 مورد',
      zero: 'خالی',
    );
    return '$_temp0';
  }

  @override
  String get routePickEmpty => 'سروری نیست که هستهٔ فعلی بتواند جداگانه از آن استفاده کند. کانفیگ‌های آماده اینجا مناسب نیستند و زنجیره‌ها فقط روی mihomo مناسب‌اند.';

  @override
  String settingsRoutingRouteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مسیر',
      zero: 'بدون مسیر',
    );
    return '$_temp0';
  }

  @override
  String get routesSectionBlock => 'مسدودسازی';

  @override
  String get routesSectionApps => 'برنامه‌ها';

  @override
  String get routesSectionAllApps => 'همهٔ برنامه‌ها';

  @override
  String get routesHint => 'فهرست‌های «مستقیم»، «پروکسی» و «مسدود» اکنون مسیر هستند. برای تغییر، روی مسیر بزنید.';

  @override
  String get routesHintDismiss => 'متوجه شدم';

  @override
  String get routeNew => 'مسیر جدید';

  @override
  String get routeNewSubtitle => 'برنامه، سایت‌ها یا فهرست آماده';

  @override
  String get routeNewSubtitleSites => 'سایت‌ها یا فهرست آماده';

  @override
  String get routeEditorTitle => 'مسیر';

  @override
  String get routeWho => 'کدام برنامه';

  @override
  String get routeWhat => 'چه ترافیکی';

  @override
  String get routeWhere => 'به کجا';

  @override
  String get routeWhoAllSubtitle => 'هر چه از VPN عبور می‌کند';

  @override
  String get routeWhoApps => 'برنامه‌های مشخص';

  @override
  String routeWhoDone(int count) {
    return 'تمام · $count';
  }

  @override
  String get routeWhatAll => 'همهٔ ترافیک';

  @override
  String get routeWhatAllSubtitle => 'هر چه برنامه باز می‌کند';

  @override
  String get routeWhatSites => 'سایت‌های دلخواه';

  @override
  String get routeWhatSitesSubtitle => 'دامنه، IP و لینک فهرست‌ها';

  @override
  String routeWhatPresetValue(String name) {
    return 'فهرست آماده · $name';
  }

  @override
  String routeWhatSitesValue(String entries) {
    return 'سایت‌های دلخواه · $entries';
  }

  @override
  String get routeWhereVpnSubtitle => 'از طریق سروری که برنامه به آن وصل است';

  @override
  String get routeWhereDirectSubtitle => 'بدون VPN';

  @override
  String get routeWhereBlockSubtitle => 'اتصال‌ها باز نمی‌شوند';

  @override
  String get routeWhereServers => 'سرور دیگر';

  @override
  String get routeToVpn => 'پروکسی';

  @override
  String get routeToDirect => 'مستقیم';

  @override
  String get routeToBlock => 'مسدود';

  @override
  String get routeAllTrafficShort => 'همهٔ ترافیک';

  @override
  String get routeDisabledShort => 'خاموش';

  @override
  String get routeEnabled => 'مسیر فعال';

  @override
  String get routeDeleteConfirm => 'این مسیر حذف شود؟';

  @override
  String get routeServerMissing => 'سرور دیگر نیست، از پروکسی می‌رود';

  @override
  String get routeServerUnsupported => 'هستهٔ فعلی این سرور را نمی‌پذیرد، از پروکسی می‌رود';

  @override
  String get routeAppsUnsupported => 'هستهٔ فعلی برنامه‌ها را تشخیص نمی‌دهد، مسیر کار نمی‌کند';

  @override
  String get routeAppsNeedTun => 'فقط در حالت TUN کار می‌کند';

  @override
  String get routeAppsNeedVpn => 'فقط در حالت VPN کار می‌کند';

  @override
  String get routingProfileMain => 'اصلی';

  @override
  String get routingIgnoreProviderRules => 'نادیده گرفتن قوانین ارائه‌دهنده';

  @override
  String get routingIgnoreProviderRulesHint => 'فقط مسیرهای خودتان اعمال می‌شود';

  @override
  String get routingProfileScopeAll => 'همهٔ اشتراک‌ها و سرورهای خودتان';

  @override
  String get routingProfileScopeRest => 'بقیهٔ اشتراک‌ها و سرورهای خودتان';

  @override
  String routingProfileRouteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مسیر',
      zero: 'بدون مسیر',
    );
    return '$_temp0';
  }

  @override
  String routingProfileFinal(String target) {
    return 'بقیهٔ ترافیک → $target';
  }

  @override
  String get routingProfileOff => 'خاموش: پروفایل اصلی اعمال می‌شود';

  @override
  String get routingProfileNoSubscriptions => 'به هیچ اشتراکی متصل نیست';

  @override
  String get routingProfileNew => 'پروفایل جدید';

  @override
  String get routingProfileName => 'نام';

  @override
  String get routingProfileForSubscriptions => 'برای اشتراک‌ها';

  @override
  String routingProfileSubOnOther(String name) {
    return 'اکنون با پروفایل «$name»';
  }

  @override
  String get routingProfileStartFrom => 'شروع از';

  @override
  String get routingProfileStartCopy => 'رونوشت پروفایل اصلی';

  @override
  String get routingProfileStartCopyHint => 'همان مسیرها، سپس برای اشتراک تنظیمشان کنید';

  @override
  String get routingProfileStartEmpty => 'پروفایل خالی';

  @override
  String get routingProfileStartEmptyHint => 'فقط بقیهٔ ترافیک از طریق VPN';

  @override
  String get routingProfileCreate => 'ایجاد';

  @override
  String get routingProfileNoSubscriptionsYet => 'هنوز اشتراکی نیست: پروفایل روی سرورهای اشتراک‌ها اعمال می‌شود';

  @override
  String get routingProfileRenameTitle => 'تغییر نام پروفایل';

  @override
  String get routingProfileSubscriptions => 'اشتراک‌ها';

  @override
  String routingProfileDeleteConfirm(String name) {
    return 'پروفایل «$name» حذف شود؟ اشتراک‌هایش به پروفایل اصلی برمی‌گردند.';
  }

  @override
  String routeSplitExcluded(String apps) {
    return '$apps با پروکسی به تفکیک برنامه از VPN عبور نمی‌کند';
  }

  @override
  String get routeRefilterUnmatched => '«بقیهٔ ترافیک» اکنون مستقیم می‌رود';

  @override
  String settingsRoutingLinkDomains(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted دامنه از لینک‌ها',
    );
    return '$_temp0';
  }

  @override
  String settingsRoutingCountWithLinks(String items, String links) {
    return '$items، $links';
  }

  @override
  String ruleListDomainCount(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted دامنه',
    );
    return '$_temp0';
  }

  @override
  String ruleListLoaded(String host, String domains, String when) {
    return '$host — $domains، به‌روز شده $when';
  }

  @override
  String ruleListLoadedStale(String host, String domains, String when) {
    return '$host — $domains، به‌روز شده $when؛ نسخهٔ تازه دریافت نشد';
  }

  @override
  String ruleListLoading(String host) {
    return '$host — در حال دریافت…';
  }

  @override
  String ruleListFailedNetwork(String host) {
    return '$host — دریافت نشد، در اتصال بعدی دوباره تلاش می‌شود';
  }

  @override
  String ruleListFailedInsecure(String host) {
    return '$host — لینک باید با https شروع شود';
  }

  @override
  String ruleListFailedHttp(String host, int code) {
    return '$host — سرور با کد $code پاسخ داد';
  }

  @override
  String ruleListFailedTooLarge(String host) {
    return '$host — فایل بزرگ‌تر از 30 مگابایت است';
  }

  @override
  String ruleListFailedEmpty(String host) {
    return '$host — در فایل دامنه‌ای نیست';
  }

  @override
  String ruleListMemoryWarning(String limit) {
    return 'بیش از $limit دامنه از لینک‌ها: هسته حافظهٔ خیلی بیشتری لازم دارد و سیستم ممکن است آن را در پس‌زمینه ببندد.';
  }

  @override
  String settingsAndroidColorsSubtitle(Object mode) {
    return 'رنگ‌های اندروید · $mode';
  }

  @override
  String settingsSystemColorsSubtitle(Object mode) {
    return 'رنگ‌های سیستم · $mode';
  }

  @override
  String get themeModeDark => 'تیره';

  @override
  String get themeModeLight => 'روشن';

  @override
  String get themeCustomizationTitle => 'ظاهر';

  @override
  String get themeUseDynamicColors => 'استفاده از رنگ‌های پویای اندروید';

  @override
  String get themePaletteHint => 'روشن/تیره جداگانه عوض می‌شود';

  @override
  String get themeUseSystemColors => 'استفاده از رنگ تأکیدی سیستم';

  @override
  String get themeColorThemesTitle => 'پوسته‌های رنگی';

  @override
  String get serversColumnsTitle => 'چند ستونه';

  @override
  String get serversColumnsNoRoom => 'در این اندازهٔ رابط کاربری جا نمی‌شوند';

  @override
  String serversColumnsOnlyFit(int count) {
    return 'در این اندازهٔ رابط کاربری فقط $count ستون جا می‌شود';
  }

  @override
  String get appearanceServerIconThemeColors => 'آیکون سرورهای بدون پرچم به رنگ پوسته';

  @override
  String get settingsLanProxyTitle => 'پروکسی شبکهٔ محلی';

  @override
  String get settingsOff => 'خاموش';

  @override
  String settingsLanSharingOnIp(Object ip) {
    return 'در حال اشتراک روی $ip';
  }

  @override
  String settingsLanFirewallHint(Object ports) {
    return 'اگر دستگاه‌های دیگر وصل نمی‌شوند، پورت‌های $ports را در فایروال باز کنید:';
  }

  @override
  String get settingsDeviceIpListTitle => 'آدرس‌های آی‌پی دستگاه در شبکه:';

  @override
  String get settingsIpCopied => 'آی‌پی کپی شد';

  @override
  String get settingsSetupAnotherDeviceTitle => 'تنظیم روی دستگاه دیگر:';

  @override
  String get settingsSocks5PortLabel => 'پورت SOCKS5';

  @override
  String get settingsHttpPortLabel => 'پورت HTTP';

  @override
  String get settingsLanUsernameLabel => 'نام کاربری';

  @override
  String get settingsLanPasswordLabel => 'رمز عبور';

  @override
  String get settingsLanAuthHint => 'اگر هر دو پر باشند، دستگاه‌ها با همین‌ها به پروکسی وارد می‌شوند. اگر خالی باشند، رمزی در کار نیست و هر کسی در شبکهٔ شما می‌تواند از آن استفاده کند.';

  @override
  String get settingsLocalPortsTitle => 'پورت‌های پروکسی محلی';

  @override
  String get settingsLocalPortsHint => 'SOCKS5 و HTTP، پیش‌فرض 2080 / 2081 و باید متفاوت باشند. از اتصال بعدی اعمال می‌شود.';

  @override
  String get settingsPortInvalid => 'پورتی بین 1 تا 65535 وارد کنید';

  @override
  String get settingsPortsMustDiffer => 'پورت SOCKS و HTTP باید متفاوت باشند';

  @override
  String get settingsTurnOffToChange => 'برای تغییر، ابتدا خاموش کنید';

  @override
  String settingsProxyCopied(Object label, Object address) {
    return '$label $address کپی شد';
  }

  @override
  String get settingsXrayCoreTitle => 'تنظیمات هسته';

  @override
  String get settingsXrayCoreSubtitle => 'DNS، Mux، فرگمنت، TUN و گزارش‌ها';

  @override
  String get settingsXrayDnsSection => 'DNS';

  @override
  String get settingsXrayDnsCustom => 'سرورهای DNS دلخواه';

  @override
  String get settingsXrayDnsCustomHint => 'هر آدرس در یک خط (DoH، DoT یا ساده)';

  @override
  String get settingsXrayDnsServers => 'سرورهای DNS';

  @override
  String get settingsXrayDnsSplitDirect => 'DNS جدا برای دامنه‌های مستقیم';

  @override
  String get settingsXrayDnsSplitDirectHint => 'برای دامنه‌های فهرست مستقیم از سرور اول استفاده می‌کند';

  @override
  String get settingsXrayDnsHosts => 'آدرس دلخواه برای دامنه‌ها';

  @override
  String get settingsXrayDnsPolicy => 'DNS جداگانه برای دامنه‌های خاص';

  @override
  String get settingsXrayDnsQueryStrategy => 'استراتژی پرس‌وجو';

  @override
  String get settingsXrayDnsDisableCache => 'غیرفعال کردن کش DNS';

  @override
  String get settingsXrayXmuxSection => 'XMUX (XHTTP)';

  @override
  String get settingsXrayXmuxEnable => 'فعال‌سازی XMUX';

  @override
  String get settingsXrayXmuxEnableHint => 'مالتی‌پلکسینگ برای انتقال XHTTP (سمت کلاینت)';

  @override
  String get settingsXrayMuxSection => 'Mux';

  @override
  String get settingsXrayMuxEnable => 'فعال‌سازی Mux';

  @override
  String get settingsXrayMuxEnableHint => 'چند اتصال درون یک اتصال: دست‌دادن کمتر، اما معمولاً در دانلود و تست سرعت بدتر است.';

  @override
  String get settingsXrayMuxParamsTitle => 'تعداد جریان در هر اتصال';

  @override
  String get settingsXrayMuxParamsHint => '‎-1‎ یعنی بدون مالتی‌پلکس. TCP تا 128، UDP تا 1024.';

  @override
  String get settingsXrayMuxConcurrency => 'جریان‌های TCP';

  @override
  String get settingsXrayMuxXudpConcurrency => 'جریان‌های UDP (XUDP)';

  @override
  String get settingsXrayMuxUdp443Title => 'QUIC (UDP/443)';

  @override
  String get settingsXrayMuxUdp443Reject => 'رد کردن';

  @override
  String get settingsXrayMuxUdp443Allow => 'از مسیر Mux';

  @override
  String get settingsXrayMuxUdp443Skip => 'بدون Mux';

  @override
  String get settingsXrayGeneralSection => 'عمومی';

  @override
  String get settingsXrayLogLevel => 'سطح گزارش‌گیری';

  @override
  String get settingsXrayDomainStrategy => 'استراتژی دامنه در مسیریابی';

  @override
  String get settingsXrayConcurrentDial => 'اتصال هم‌زمان به همهٔ آدرس‌ها';

  @override
  String get settingsXrayConcurrentDialHint => 'وقتی بخشی از آدرس‌های سرور مسدود است کمک می‌کند';

  @override
  String get settingsXraySniffing => 'شناسایی دامنه در ترافیک (sniffing)';

  @override
  String get settingsXraySniffingRouteOnly => 'دامنهٔ شناسایی‌شده فقط برای مسیریابی';

  @override
  String get settingsXrayDnsDefaultNote => 'پیش‌فرض: DoH کلادفلر و گوگل';

  @override
  String get settingsXrayXmuxParamsTitle => 'تنظیم دقیق';

  @override
  String get settingsXrayXmuxParamsHint => 'خالی یعنی پیش‌فرض Xray. یک عدد یا یک بازه، مثلاً 16-32.';

  @override
  String get settingsXraySniffingHint => 'تشخیص پروتکل و دامنهٔ مقصد از روی ترافیک ورودی';

  @override
  String get settingsXraySniffingRouteOnlyHint => 'دامنهٔ شناسایی‌شده فقط قانون را انتخاب می‌کند؛ اتصال به آدرس برنامه می‌رود.';

  @override
  String get settingsXrayUdpPerAddress => 'مسیریابی UDP برای هر آدرس مقصد';

  @override
  String get settingsXrayUdpPerAddressHint => 'خروجی برای هر آدرس مقصد طبق قوانین انتخاب می‌شود، نه بر اساس نخستین بستهٔ سوکت. اگر قوانین سرور STUN و طرف مقابل را به خروجی‌های مختلف بفرستند، P2P بر پایهٔ STUN (تماس، بازی، تورنت) ممکن است مستقیم برقرار نشود.';

  @override
  String get settingsXrayResetDefaults => 'بازگشت به پیش‌فرض';

  @override
  String get settingsXrayResetDone => 'تنظیمات هستهٔ Xray بازنشانی شد';

  @override
  String get settingsXrayXmuxMaxConcurrency => 'بیشینهٔ هم‌زمانی';

  @override
  String get settingsXrayXmuxMaxConnections => 'بیشینهٔ اتصال‌ها';

  @override
  String get settingsXrayXmuxOneOfTwo => 'فقط یکی از این دو';

  @override
  String get settingsXrayXmuxConnectionsIgnored => 'تا وقتی بیشینهٔ هم‌زمانی پر است، نادیده گرفته می‌شود';

  @override
  String get settingsXrayXmuxCMaxReuseTimes => 'حد استفادهٔ مجدد از اتصال';

  @override
  String get settingsXrayXmuxHMaxRequestTimes => 'بیشینهٔ درخواست در هر جریان';

  @override
  String get settingsXrayXmuxHMaxReusableSecs => 'مدت استفادهٔ مجدد جریان (ثانیه)';

  @override
  String get settingsXrayXmuxHKeepAlivePeriod => 'دورهٔ keep-alive (ثانیه)';

  @override
  String get settingsXrayFragmentSection => 'فرگمنت';

  @override
  String get settingsXrayFragmentEnable => 'تکه‌تکه کردن TLS ClientHello';

  @override
  String get settingsXrayFragmentEnableHint => 'بستهٔ نخست تکه‌تکه می‌رود و DPI نمی‌تواند SNI را بخواند.';

  @override
  String get settingsXrayNoiseSection => 'نویز پیش از UDP';

  @override
  String get settingsXrayNoiseEnable => 'ارسال نویز پیش از UDP';

  @override
  String get settingsXrayNoiseEnableHint => 'پیش از نخستین بستهٔ واقعی، بستهٔ بی‌معنا به سرور فرستاده می‌شود. برای hysteria و mkcp که ClientHello برای تکه‌کردن ندارند.';

  @override
  String get settingsXrayNoiseKindTitle => 'چه چیزی فرستاده شود';

  @override
  String get settingsXrayNoiseKindRand => 'دادهٔ تصادفی';

  @override
  String get settingsXrayNoiseKindStr => 'بستهٔ دلخواه: متن';

  @override
  String get settingsXrayNoiseKindHex => 'بستهٔ دلخواه: hex';

  @override
  String get settingsXrayNoiseKindBase64 => 'بستهٔ دلخواه: base64';

  @override
  String get settingsXrayNoisePacket => 'بسته';

  @override
  String get settingsXrayNoiseRandLength => 'طول، بایت';

  @override
  String get settingsXrayNoiseRandBytes => 'مقدار بایت‌ها (0-255)';

  @override
  String get settingsXrayNoiseDelay => 'تأخیر، میلی‌ثانیه';

  @override
  String get settingsXrayNoiseReset => 'تکرار، ثانیه';

  @override
  String get settingsXrayNoiseParamsHint => 'یک عدد یا یک بازه، مثلاً 50-100. خالی یعنی تصمیم با هسته.';

  @override
  String get settingsXrayFragmentPacketsTitle => 'چه چیزی تکه شود';

  @override
  String get settingsXrayFragmentPacketsTlsHello => 'فقط TLS ClientHello';

  @override
  String get settingsXrayFragmentPacketsFirst => 'بسته‌های نخست جریان';

  @override
  String get settingsXrayFragmentParamsTitle => 'اندازهٔ تکه و مکث';

  @override
  String get settingsXrayFragmentParamsHint => 'یک عدد یا یک بازه، مثلاً 100-200.';

  @override
  String get settingsXrayFragmentLength => 'اندازه، بایت';

  @override
  String get settingsXrayFragmentInterval => 'مکث، میلی‌ثانیه';

  @override
  String get settingsTunSection => 'حالت TUN';

  @override
  String get settingsTunSectionNote => 'از اتصال بعدی اعمال می‌شود.';

  @override
  String get settingsTunStackTitle => 'پشتهٔ شبکه';

  @override
  String get settingsTunStackSystemHint => 'پشتهٔ سیستم‌عامل: سریع‌ترین، در ویندوز به قانون فایروال نیاز دارد.';

  @override
  String get settingsTunStackGvisorHint => 'پشتهٔ فضای کاربر: بدون listener و قانون فایروال، کمی کندتر. به هسته‌ای نیاز دارد که با gVisor ساخته شده باشد.';

  @override
  String get settingsTunStackMixedHint => 'system برای TCP، gVisor برای UDP. مانند system، در ویندوز به قانون فایروال نیاز دارد. به هسته‌ای نیاز دارد که با gVisor ساخته شده باشد.';

  @override
  String get settingsTunStackMipsHint => 'پشتهٔ فضای کاربر خود mihomo به‌جای gVisor: سبک‌تر، با کنترل ازدحام TCP قابل انتخاب. فقط روی هستهٔ mihomo.';

  @override
  String get settingsTunMtu => 'MTU';

  @override
  String get settingsTunMtuHint => '576 تا 65535، پیش‌فرض 9000';

  @override
  String get settingsTunUdpTimeout => 'مهلت UDP (ثانیه)';

  @override
  String get settingsTunUdpTimeoutHint => 'طول عمر NAT برای نشست‌های بیکار UDP، پیش‌فرض 300';

  @override
  String get settingsTunStrictRouteTitle => 'مسیریابی سخت‌گیرانه (strict route)';

  @override
  String get settingsTunStrictRouteHint => 'جلوی نشت ترافیک از کنار TUN را می‌گیرد. در ویندوز اگر VPN دیگری (مثلاً Tailscale) فعال باشد می‌تواند مسیریابی را خراب کند';

  @override
  String get settingsTunStrictRouteAuto => 'خودکار';

  @override
  String get settingsTunStrictRouteAutoHint => 'لینوکس: روشن، ویندوز: خاموش';

  @override
  String get settingsTunStrictRouteOn => 'فعال';

  @override
  String get settingsTunStrictRouteOff => 'غیرفعال';

  @override
  String get settingsTunAutoRoute => 'مسیریابی خودکار (auto route)';

  @override
  String get settingsTunAutoRouteHint => 'مسیرهای سیستم را به تونل می‌افزاید. بدون آن چیزی به TUN نمی‌رسد.';

  @override
  String get settingsTunIpv6 => 'نگه‌داشتن IPv6 داخل تونل';

  @override
  String get settingsTunIpv6Hint => 'به رابط TUN آدرس IPv6 می‌دهد؛ بدون آن همهٔ IPv6 از تونل بیرون می‌ماند.';

  @override
  String get settingsFakeIp => 'Fake IP';

  @override
  String get settingsFakeIpHint => 'پاسخ فوری DNS با آدرس‌های ساختگی. در حالت پروکسی کار نمی‌کند.';

  @override
  String get settingsPingTitle => 'پینگ سرور';

  @override
  String get settingsPingMethodTitle => 'روش پینگ';

  @override
  String get settingsPingMethodTcp => 'پینگ TCP';

  @override
  String get settingsPingMethodTcpHint => 'بررسی سریع در دسترس بودن';

  @override
  String get settingsPingMethodIcmp => 'پینگ ICMP';

  @override
  String get settingsPingMethodIcmpHint => 'اکو به آی‌پی سرور (بعضی سرورها مسدودش می‌کنند)';

  @override
  String get settingsPingMethodUrl => 'HTTP از طریق پروکسی';

  @override
  String get settingsPingMethodUrlHint => 'تأخیر درخواست GET را از طریق سرور اندازه می‌گیرد';

  @override
  String get settingsPingKeepAliveTitle => 'روش اندازه‌گیری';

  @override
  String get settingsPingKeepAlive => 'اندازه‌گیری روی اتصال گرم';

  @override
  String get settingsPingKeepAliveHint => 'درخواست دو بار می‌رود و دومی شمرده می‌شود — بدون دست‌دادن. خاموش: یک درخواست همراه گرم‌شدن، مثل اولین باز کردن یک سایت.';

  @override
  String get settingsPingAutoTitle => 'زمان پینگ';

  @override
  String get settingsPingAuto => 'پینگ خودکار';

  @override
  String get settingsPingAutoHint => 'هنگام باز شدن برنامه و درست پس از به‌روزرسانی اشتراک';

  @override
  String get settingsPingMethodSpeed => 'تست سرعت';

  @override
  String get settingsPingMethodSpeedHint => 'حجم مشخصی را از طریق سرور دانلود می‌کند و سرعت را برحسب Mbps نشان می‌دهد (بدون VPN هم کار می‌کند)';

  @override
  String get settingsPingTargetTitle => 'آدرس تست HTTP';

  @override
  String get settingsPingTargetGstatic => 'گوگل (generate_204)';

  @override
  String get settingsPingTargetCloudflare => 'کلادفلر (trace)';

  @override
  String get settingsPingTargetMicrosoft => 'مایکروسافت (تست اتصال)';

  @override
  String get settingsPingTargetCustom => 'آدرس دلخواه';

  @override
  String get settingsPingCustomUrl => 'آدرس';

  @override
  String get settingsPingCustomUrlHint => 'آدرس ‎https://‎ یا ‎http://‎ برای درخواست GET';

  @override
  String get settingsPingCustomUrlInvalid => 'آدرس نامعتبر یا ناامن (localhost و شبکه‌های داخلی مجاز نیستند)';

  @override
  String get subscriptionNameLabel => 'نام';

  @override
  String get subscriptionNameHint => 'اشتراک من';

  @override
  String get subscriptionUrlLabel => 'آدرس';

  @override
  String get subscriptionUrlHint => 'https://example.com/sub?token=...';

  @override
  String get subscriptionsAddSubscription => 'افزودن اشتراک';

  @override
  String get subscriptionsAddAndFetch => 'افزودن و دریافت';

  @override
  String get subscriptionsEditSubscription => 'ویرایش اشتراک';

  @override
  String get subscriptionsCopyUrl => 'کپی آدرس';

  @override
  String get subscriptionsUrlCopied => 'آدرس کپی شد';

  @override
  String get subscriptionsShareButton => 'اشتراک‌گذاری (QR + لینک)';

  @override
  String get subscriptionsShareAction => 'اشتراک‌گذاری';

  @override
  String subscriptionsShareFailed(Object error) {
    return 'اشتراک‌گذاری نشد: $error';
  }

  @override
  String subscriptionsQrSaved(Object path) {
    return 'کد QR ذخیره شد: $path';
  }

  @override
  String subscriptionsQrSaveFailed(Object error) {
    return 'ذخیره کد QR انجام نشد: $error';
  }

  @override
  String get subscriptionsQrSaveTitle => 'ذخیره کد QR';

  @override
  String get subscriptionIdentityTitle => 'مشخصات دستگاه';

  @override
  String get subscriptionIdentityHint => 'آنچه پنل می‌بیند: HWID، User-Agent و هدرهای دستگاه. فقط برای همین اشتراک اعمال می‌شود.';

  @override
  String get subscriptionIdentityEnable => 'استفاده از مشخصات دلخواه';

  @override
  String get subscriptionIdentityAppDefault => 'پیش‌فرض برنامه';

  @override
  String get subscriptionIdentityAppDefaultHint => 'ارسال مقدار واقعی این دستگاه';

  @override
  String get subscriptionIdentityHwid => 'HWID';

  @override
  String get subscriptionIdentityHwidOff => 'در تنظیمات پیشرفته «ارسال HWID دستگاه» خاموش است، بنابراین هیچ HWID‌ای ارسال نمی‌شود؛ حتی مقدار دلخواه.';

  @override
  String get subscriptionIdentityUserAgent => 'User-Agent';

  @override
  String get subscriptionIdentityDeviceOs => 'سیستم‌عامل دستگاه';

  @override
  String get subscriptionIdentityDeviceModel => 'مدل دستگاه';

  @override
  String get subscriptionIdentityOsVersion => 'نسخهٔ سیستم‌عامل';

  @override
  String get subscriptionIdentitySectionUsed => 'در حال استفاده';

  @override
  String get subscriptionIdentitySectionUaAndroid => 'کلاینت‌های اندروید';

  @override
  String get subscriptionIdentitySectionUaApple => 'کلاینت‌های آیفون و آی‌پد';

  @override
  String get subscriptionIdentitySectionUaDesktop => 'کلاینت‌های دسکتاپ';

  @override
  String get subscriptionIdentitySectionUaCores => 'هسته‌ها و http ساده';

  @override
  String get subscriptionIdentitySectionOs => 'سیستم‌عامل‌ها';

  @override
  String get subscriptionIdentitySectionApple => 'آیفون و آی‌پد';

  @override
  String get subscriptionIdentitySectionDesktop => 'دسکتاپ';

  @override
  String get subscriptionIdentitySectionAndroidRelease => 'اندروید — نسخه';

  @override
  String get subscriptionIdentitySectionAndroidBuild => 'اندروید — بیلد';

  @override
  String get subscriptionIdentitySectionIosRelease => 'iOS — نسخه';

  @override
  String get subscriptionIdentitySectionIosBuild => 'iOS — بیلد';

  @override
  String get subscriptionIdentitySearchOrEnter => 'جست‌وجو یا وارد کردن مقدار دلخواه';

  @override
  String get subscriptionIdentityUseTyped => 'استفاده از این مقدار';

  @override
  String get subscriptionIdentityReset => 'بازنشانی';

  @override
  String get subscriptionIdentityApply => 'اعمال';

  @override
  String get subscriptionsDeleteSubscription => 'حذف اشتراک';

  @override
  String subscriptionsDeleteConfirm(Object name) {
    return 'مطمئنید که «$name» حذف شود؟\n\nهمهٔ سرورهای مربوط به آن هم پاک می‌شوند.';
  }

  @override
  String get subscriptionsRetry => 'تلاش دوباره';

  @override
  String get subscriptionsCancel => 'لغو';

  @override
  String get subscriptionsDelete => 'حذف';

  @override
  String get subscriptionsSave => 'ذخیره';

  @override
  String get subscriptionsOff => 'خاموش';

  @override
  String get subscriptionsExpired => 'منقضی شده';

  @override
  String get subscriptionsEveryHour => 'هر ساعت';

  @override
  String subscriptionsEveryHours(int hours) {
    return 'هر $hours ساعت';
  }

  @override
  String get subscriptionsEveryDay => 'هر روز';

  @override
  String subscriptionsEveryDays(int days) {
    return 'هر $days روز';
  }

  @override
  String get subscriptionsAutoUpdateInterval => 'بازهٔ به‌روزرسانی خودکار';

  @override
  String subscriptionsCurrentInterval(int hours) {
    return 'هر $hours ساعت';
  }

  @override
  String subscriptionsIntervalShort(int hours) {
    return '$hours ساعت';
  }

  @override
  String get subscriptionsJustNow => 'همین الان';

  @override
  String subscriptionsMinutesAgo(int minutes) {
    return '$minutes دقیقه پیش';
  }

  @override
  String subscriptionsHoursAgo(int hours) {
    return '$hours ساعت پیش';
  }

  @override
  String subscriptionsDaysAgo(int days) {
    return '$days روز پیش';
  }

  @override
  String subscriptionsInDays(int days) {
    return '$days روز دیگر';
  }

  @override
  String subscriptionsInHours(int hours) {
    return '$hours ساعت دیگر';
  }

  @override
  String get subscriptionsSoon => 'به‌زودی';

  @override
  String get serversAddServer => 'افزودن سرور';

  @override
  String get serversPasteLinks => 'چسباندن لینک';

  @override
  String get serversPasteLinksHint => 'لینک‌های سرور یا کانفیگ کامل';

  @override
  String get serversImportFile => 'وارد کردن از فایل';

  @override
  String get serversAddServerTitle => 'افزودن سرور';

  @override
  String get serversPasteVlessHint => 'در هر خط یک لینک، یا یک کانفیگ کامل: Xray، Clash، sing-box، AmneziaWG';

  @override
  String get serversPasteHint => '‎vless://…‎ یا ‎hy2://host:port?auth=…‎';

  @override
  String get serversAdd => 'افزودن';

  @override
  String get serversManualServers => 'سرورهای دستی';

  @override
  String get serversRefreshSubscription => 'به‌روزرسانی اشتراک';

  @override
  String get serversPingAll => 'پینگ همه';

  @override
  String get settingsAdvanced => 'پیشرفته';

  @override
  String get settingsAdvancedSubtitle => 'تنظیمات هسته، پینگ، مسیریابی، HWID و اشکال‌زدایی';

  @override
  String get serverEditorJsonValid => 'کانفیگ معتبر Xray';

  @override
  String get serverEditorJsonFormat => 'قالب‌بندی';

  @override
  String get subscriptionsCardMenu => 'بیشتر';

  @override
  String get subscriptionsAutoUpdateOff => 'به‌روزرسانی خودکار نشود';

  @override
  String get subscriptionsProviderPage => 'صفحهٔ اشتراک';

  @override
  String get subscriptionsSupport => 'پشتیبانی';

  @override
  String get subscriptionsLinkOpenFailed => 'باز کردن لینک ممکن نشد';

  @override
  String get settingsAdvancedGroupTraffic => 'ترافیک و هسته';

  @override
  String get settingsAdvancedGroupSystem => 'سیستم';

  @override
  String get settingsAdvancedGroupDiagnostics => 'عیب‌یابی';

  @override
  String get settingsBackupRestore => 'پشتیبان‌گیری و بازیابی';

  @override
  String get settingsBackupRestoreSubtitle => 'خروجی گرفتن و وارد کردن اشتراک‌ها، سرورها، تنظیمات و پروکسی به تفکیک برنامه';

  @override
  String get settingsSelectAtLeastOne => 'برای خروجی گرفتن دست‌کم یک بخش را انتخاب کنید';

  @override
  String get settingsBackupSaved => 'پشتیبان با موفقیت ذخیره شد';

  @override
  String get settingsSelectLocation => 'محل ذخیرهٔ پشتیبان را انتخاب کنید';

  @override
  String get settingsExportFile => 'خروجی گرفتن در فایل';

  @override
  String get settingsImportFile => 'وارد کردن از فایل';

  @override
  String get settingsImportBackup => 'وارد کردن پشتیبان';

  @override
  String get settingsChooseWhatToImport => 'بخش‌های انتخاب‌شده جای داده‌های فعلی را می‌گیرند';

  @override
  String get settingsSplitTunnelingApps => 'پروکسی به تفکیک برنامه';

  @override
  String get settingsSubscriptions => 'اشتراک‌ها';

  @override
  String get settingsServersActive => 'سرورها (و سرور فعال)';

  @override
  String get settingsAppSettings => 'تنظیمات برنامه';

  @override
  String get settingsImport => 'وارد کردن';

  @override
  String get settingsExport => 'خروجی گرفتن';

  @override
  String get settingsCreateFileToSave => 'فایل را می‌توان به دستگاه دیگری برد';

  @override
  String get settingsPickExportedFile => 'بعد از انتخاب فایل، بخش‌ها را انتخاب می‌کنید';

  @override
  String get settingsWorking => 'در حال انجام...';

  @override
  String settingsImportedSections(int count) {
    return '$count بخش وارد شد';
  }

  @override
  String get settingsShareHwidTitle => 'ارسال HWID دستگاه';

  @override
  String get settingsShareHwidOn => 'همراه درخواست‌های اشتراک ارسال می‌شود';

  @override
  String get settingsShareHwidOff => 'ارسال نمی‌شود';

  @override
  String get settingsDebugMode => 'حالت اشکال‌زدایی';

  @override
  String get settingsDebugModeOn => 'اطلاعات تشخیصی گسترده فعال است';

  @override
  String get settingsDebugModeOff => 'خاموش';

  @override
  String get settingsOpenXrayLogs => 'باز کردن گزارش‌های هسته';

  @override
  String get settingsXrayCoreLogs => 'گزارش‌های هسته';

  @override
  String get settingsRefresh => 'تازه‌سازی';

  @override
  String get settingsCopyLogs => 'کپی گزارش‌ها';

  @override
  String get settingsAppVersion => 'نسخهٔ برنامه';

  @override
  String get settingsChecking => 'در حال بررسی...';

  @override
  String get settingsCheckFailed => 'بررسی ناموفق بود';

  @override
  String get settingsUpdateAvailable => 'نسخهٔ جدید موجود است';

  @override
  String get settingsUpToDate => 'به‌روز است';

  @override
  String get settingsNewVersionAvailable => 'نسخهٔ جدید موجود است';

  @override
  String get settingsDownloading => 'در حال دانلود...';

  @override
  String get settingsCheckForUpdates => 'بررسی به‌روزرسانی';

  @override
  String settingsExportFailed(Object error) {
    return 'خروجی گرفتن ناموفق بود: $error';
  }

  @override
  String settingsImportFailed(Object error) {
    return 'وارد کردن ناموفق بود: $error';
  }

  @override
  String settingsDownloadFailed(Object error) {
    return 'دانلود ناموفق بود: $error';
  }

  @override
  String settingsCheckFailedError(Object error) {
    return 'بررسی ناموفق بود: $error';
  }

  @override
  String get settingsLanguageTitle => 'زبان';

  @override
  String settingsLanguageSubtitle(Object language) {
    return '$language';
  }

  @override
  String get settingsLanguageSystem => 'پیش‌فرض سیستم';

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
  String get settingsLanguageSheetTitle => 'انتخاب زبان';

  @override
  String get splitAddApp => 'افزودن برنامه';

  @override
  String get splitAddAppTitle => 'افزودن برنامه';

  @override
  String get splitAddAppHint => 'مسیر فایل ‎.exe‎ یا نام آن (مثلاً chrome.exe)';

  @override
  String get splitAddAppPickFile => 'انتخاب فایل…';

  @override
  String get splitAddAppInvalid => 'نام یا مسیر معتبر فایل ‎.exe‎ را وارد کنید';

  @override
  String get splitAddAppHintLinux => 'مسیر برنامه یا نام آن (مثلاً ‎firefox‎)';

  @override
  String get splitAddAppInvalidLinux => 'نام یا مسیر برنامه را وارد کنید';

  @override
  String splitAddAppAdded(Object name) {
    return 'اضافه شد: $name';
  }

  @override
  String get splitProxyModeWarning => 'در حالت پروکسی، پروکسی به تفکیک برنامه اعمال نمی‌شود: همهٔ ترافیک از پروکسی سیستم عبور می‌کند. برای اینکه قوانین برنامه‌ها کار کنند، حالت اتصال را در پنل کناری روی TUN بگذارید.';

  @override
  String get settingsLatestVersionInstalled => 'آخرین نسخه را دارید';

  @override
  String get serversPingServer => 'پینگ سرور';

  @override
  String get serversCopyAddress => 'کپی آدرس سرور';

  @override
  String get serversCopiedToClipboard => 'در کلیپ‌بورد کپی شد';

  @override
  String get serversCopyConfig => 'کپی کانفیگ';

  @override
  String get serversConfigCopied => 'کانفیگ کپی شد';

  @override
  String get serversDeleteServer => 'حذف سرور';

  @override
  String get settingsDebugHintDesktop => 'گزارش‌های نشست هسته را نشان می‌دهد. آمار زندهٔ VPN زیر دکمهٔ اتصال دیده می‌شود.';

  @override
  String get settingsDebugHintMobile => 'آمار زندهٔ VPN را روی کارت سرورها و گزارش‌های هسته را نشان می‌دهد.';

  @override
  String get desktopConnectionMode => 'حالت اتصال';

  @override
  String get desktopModeShort => 'حالت';

  @override
  String get settingsDesktopTitle => 'ویندوز';

  @override
  String get settingsDesktopTitleLinux => 'Linux';

  @override
  String get settingsDesktopSubtitle => 'سینی سیستم، اجرای خودکار، اتصال خودکار';

  @override
  String get settingsMinimizeToTray => 'هنگام بستن، به سینی سیستم برود';

  @override
  String get settingsLaunchAtStartup => 'اجرا همراه ویندوز';

  @override
  String get settingsLaunchAtLogin => 'اجرا هنگام ورود به سیستم';

  @override
  String get settingsLaunchAtStartupAdmin => 'اجرا با دسترسی مدیر';

  @override
  String get settingsAutostartInTray => 'اجرا در سینی سیستم، بدون پنجره';

  @override
  String get settingsAutostartAdminFailed => 'دسترسی مدیر داده نشد';

  @override
  String get settingsAutoConnectOnAutostart => 'اتصال هنگام اجرای خودکار';

  @override
  String get settingsAutoConnectRequiresAutostart => 'اول «اجرا همراه ویندوز» را روشن کنید';

  @override
  String get settingsAutoConnectRequiresLogin => 'اول «اجرا هنگام ورود به سیستم» را روشن کنید';

  @override
  String get desktopTunAdminTitle => 'دسترسی مدیر لازم است';

  @override
  String get desktopTunAdminMessage => 'حالت TUN به دسترسی مدیر نیاز دارد. برای استفاده از TUN برنامه را با دسترسی مدیر دوباره اجرا کنید. حالت فعلی در پنل کناری حفظ می‌شود.';

  @override
  String get desktopTunAdminRestart => 'اجرای دوباره با دسترسی مدیر';

  @override
  String get desktopTunAdminCancel => 'لغو';

  @override
  String get desktopTunAdminRestartFailed => 'اجرای دوباره با دسترسی مدیر ممکن نشد';

  @override
  String get trayConnect => 'اتصال';

  @override
  String get trayDisconnect => 'قطع اتصال';

  @override
  String get trayOpenApp => 'باز کردن برنامه';

  @override
  String get trayExit => 'خروج';

  @override
  String get trayPickServer => 'انتخاب سرور…';

  @override
  String get trayModeProxy => 'پروکسی';

  @override
  String get trayModeTun => 'TUN';

  @override
  String get trayStatusConnected => 'متصل';

  @override
  String get trayStatusDisconnected => 'قطع شده';

  @override
  String get trayStatusError => 'خطا';

  @override
  String get serversSortTitle => 'مرتب‌سازی سرورها';

  @override
  String get serversSortDefault => 'ترتیب پیش‌فرض';

  @override
  String get serversSortPing => 'پینگ (کم → زیاد)';

  @override
  String get serversSortSpeed => 'سرعت (زیاد → کم)';

  @override
  String get serversSortName => 'نام (الف تا ی)';

  @override
  String get updateActionSkip => 'رد کردن این نسخه';

  @override
  String updateSizeLabel(Object size) {
    return 'حجم: $size';
  }

  @override
  String get updateOpenDownload => 'باز کردن صفحهٔ دانلود';

  @override
  String get vpnConnectedGeneric => 'VPN متصل شد';

  @override
  String serversImportedSummary(Object added, Object total) {
    return '$added سرور از $total اضافه شد';
  }

  @override
  String get sidebarJumpTitle => 'پرش سریع';

  @override
  String get desktopRailCollapse => 'جمع کردن نوار';

  @override
  String get desktopRailExpand => 'باز کردن نوار';

  @override
  String get serversScrollToEnd => 'به انتهای فهرست';

  @override
  String get serversScrollToTop => 'به ابتدای فهرست';

  @override
  String get serversJumpToActive => 'نمایش در فهرست';

  @override
  String get exitIpLabel => 'آی‌پی که سایت‌ها می‌بینند';

  @override
  String get serversAutoSelect => 'خودکار';

  @override
  String get serversAutoSelectTooltip => 'برنامه سرور این اشتراک را خودش انتخاب می‌کند و وقتی از کار بیفتد، سرور دیگری را جایگزین می‌کند';

  @override
  String get serversManualGroup => 'سرورهای دستی';

  @override
  String get serversEmptyGroupHint => 'این اشتراک سروری ندارد';

  @override
  String get statsInLabel => 'ورودی';

  @override
  String get statsTimeLabel => 'زمان';

  @override
  String get statsDownloadLabel => 'سرعت دریافت';

  @override
  String get statsUploadLabel => 'سرعت ارسال';

  @override
  String get statsSplitVpnTag => 'VPN';

  @override
  String get statsSplitDirectTag => 'مستقیم';

  @override
  String get statsSplitVpnLabel => 'از طریق VPN';

  @override
  String get statsSplitDirectLabel => 'بدون VPN';

  @override
  String get statsSplitTotalLabel => 'منتقل‌شده';

  @override
  String get qrScanTitle => 'اسکن کد QR';

  @override
  String get qrScanHint => 'دوربین را روی کد QR بگیرید';

  @override
  String get qrScanCameraError => 'دوربین در دسترس نیست';

  @override
  String get serversScanQrHint => 'لینک سرور یا لینک اشتراک';

  @override
  String qrSubscriptionAdded(Object name) {
    return 'اشتراک اضافه شد: $name';
  }

  @override
  String get qrNotSubscriptionLink => 'این کد QR لینک اشتراک ندارد';

  @override
  String get tvReceiveTitle => 'دریافت از گوشی';

  @override
  String get tvReceiveSubtitle => 'اشتراک از گوشی از طریق Wi-Fi';

  @override
  String get tvReceiveHint => 'این کد را در keqdroid روی گوشی اسکن کنید. گوشی و تلویزیون باید به یک شبکهٔ Wi-Fi وصل باشند.';

  @override
  String get tvReceiveWaiting => 'در انتظار اشتراک…';

  @override
  String tvReceiveGot(Object name) {
    return 'دریافت شد: $name';
  }

  @override
  String tvReceiveFailed(Object error) {
    return 'افزوده نشد: $error';
  }

  @override
  String get tvReceiveNoNetwork => 'تلویزیون به شبکه وصل نیست';

  @override
  String get tvSendTitle => 'ارسال به تلویزیون';

  @override
  String get tvSendPick => 'کدام اشتراک ارسال شود؟';

  @override
  String get tvSendAction => 'ارسال';

  @override
  String get tvSendDone => 'اشتراک به تلویزیون ارسال شد';

  @override
  String get tvSendNothing => 'روی این گوشی اشتراکی برای ارسال وجود ندارد';

  @override
  String get tvSendUnreachable => 'تلویزیون پاسخ نمی‌دهد. بررسی کنید گوشی و تلویزیون به یک شبکهٔ Wi-Fi وصل باشند و صفحهٔ دریافت روی تلویزیون باز باشد.';

  @override
  String get tvSendExpired => 'این کد منقضی شده است. صفحهٔ دریافت را روی تلویزیون دوباره باز کنید و کد جدید را اسکن کنید.';

  @override
  String tvSendRejected(Object error) {
    return 'تلویزیون اشتراک را اضافه نکرد: $error';
  }

  @override
  String get settingsHotkeysTitle => 'کلیدهای میانبر';

  @override
  String get settingsHotkeysSubtitle => 'میانبر برای اتصال، حالت و سرورها';

  @override
  String get hotkeysHintGlobal => 'میانبرها در کل سیستم کار می‌کنند، حتی وقتی پنجره در سینی سیستم پنهان است. تا وقتی میانبری تعیین نکنید، همه غیرفعال‌اند.';

  @override
  String get hotkeysHintInApp => 'در لینوکس میانبرها وقتی کار می‌کنند که پنجرهٔ برنامه فوکوس داشته باشد. تا وقتی میانبری تعیین نکنید، همه غیرفعال‌اند.';

  @override
  String get hotkeyActionToggleConnection => 'اتصال / قطع اتصال';

  @override
  String get hotkeyActionToggleTun => 'تغییر بین TUN و پروکسی';

  @override
  String get hotkeyActionBestPing => 'رفتن به سرور با بهترین پینگ';

  @override
  String get hotkeyActionToggleWindow => 'نمایش / پنهان کردن پنجره';

  @override
  String get hotkeyNotSet => 'تعیین نشده';

  @override
  String get hotkeyPressKeys => 'کلیدها را بزنید…';

  @override
  String get hotkeyRecordingHint => 'Esc — لغو، Backspace — پاک کردن';

  @override
  String get hotkeyNeedsModifier => 'از یک کلید کمکی (Ctrl/Alt/Shift/Win) یا کلیدهای F استفاده کنید';

  @override
  String hotkeyConflictTaken(Object combo) {
    return 'میانبر $combo را برنامهٔ دیگری گرفته است';
  }

  @override
  String get hotkeyClearTooltip => 'پاک کردن میانبر';

  @override
  String get hotkeyNoPingData => 'هنوز نتیجهٔ پینگی نیست — اول یک بار پینگ بگیرید';

  @override
  String get clipboardNoSubscriptionLink => 'در کلیپ‌بورد لینک اشتراکی (http/https) نیست';

  @override
  String get splitTunnelingReconnectHint => 'تغییرات بعد از اتصال دوبارهٔ VPN اعمال می‌شوند';

  @override
  String serversDeleteConfirm(Object name) {
    return 'مطمئنید که «$name» حذف شود؟';
  }

  @override
  String get errorTunAdminMessage => 'حالت TUN در ویندوز به دسترسی مدیر نیاز دارد.';

  @override
  String get errorTunAdminAction => 'برنامه را با دسترسی مدیر اجرا کنید یا در تنظیمات به حالت پروکسی بروید.';

  @override
  String get errorTunAdapterRefusedTitle => 'ویندوز آداپتور را نساخت';

  @override
  String get errorTunAdapterRefusedMessage => 'ویندوز سه بار پشت سر هم آداپتور TUN را نپذیرفت. مشکل از سرور نیست.';

  @override
  String get errorTunAdapterRefusedAction => 'یک دقیقه بعد دوباره وصل شوید یا کامپیوتر را دوباره راه‌اندازی کنید. حالت پروکسی کار می‌کند.';

  @override
  String get errorPolkitMissingTitle => 'polkit لازم است';

  @override
  String get errorPolkitMissingMessage => 'حالت TUN هسته را با pkexec به‌صورت root اجرا می‌کند و polkit نصب نیست.';

  @override
  String get errorPolkitMissingAction => 'polkit را همراه با یک عامل احراز هویت نصب کنید، برنامه را با root اجرا کنید (sudo -E keqdroid) یا در تنظیمات به حالت پروکسی بروید.';

  @override
  String get errorPolkitNoAgentTitle => 'polkit لازم است';

  @override
  String get errorPolkitNoAgentMessage => 'درخواست دسترسی root بی‌پاسخ ماند: هیچ عامل احراز هویت polkit در حال اجرا نیست.';

  @override
  String get errorPolkitNoAgentAction => 'یک عامل polkit برای میزکار خود اجرا کنید (polkit-gnome، lxqt-policykit و مانند آن) یا در تنظیمات به حالت پروکسی بروید.';

  @override
  String get errorVpnPermissionMessage => 'دسترسی VPN داده نشد.';

  @override
  String get errorVpnPermissionAction => 'در پنجرهٔ سیستم دسترسی VPN را بدهید و دوباره تلاش کنید.';

  @override
  String get errorHwidBindMessage => 'سرویس‌دهنده برای این دستگاه ثبت HWID را الزامی کرده است.';

  @override
  String get errorHwidBindAction => 'این دستگاه را در پنل سرویس‌دهنده ثبت کنید و بعد اشتراک را به‌روزرسانی کنید.';

  @override
  String get errorDeviceLimitMessage => 'سرویس‌دهنده به دلیل محدودیت تعداد دستگاه، اشتراک را رد کرد.';

  @override
  String get errorDeviceLimitAction => 'در پنل سرویس‌دهنده دستگاه‌های قدیمی را حذف کنید یا سقف دستگاه‌ها را بالا ببرید.';

  @override
  String get errorConfigInvalidMessage => 'کانفیگ اشتراک یا سرور نامعتبر است.';

  @override
  String get errorConfigInvalidAction => 'قالب آدرس یا کانفیگ را بررسی کنید و یک لینک اشتراک درست وارد کنید.';

  @override
  String get errorAuthDeniedMessage => 'سرویس‌دهنده دسترسی به اشتراک را رد کرد.';

  @override
  String get errorAuthDeniedAction => 'توکن و مشخصات ورود را بررسی کنید و مطمئن شوید اشتراک منقضی نشده باشد.';

  @override
  String get errorSubUrlInvalidMessage => 'لینک اشتراک وجود ندارد یا منقضی شده است.';

  @override
  String get errorSubUrlInvalidAction => 'از سرویس‌دهنده لینک تازه بگیرید و در برنامه به‌روزش کنید.';

  @override
  String get errorSubInsecureHttpMessage => 'لینک اشتراک از http ساده استفاده می‌کند، به‌روزرسانی مسدود است.';

  @override
  String get errorSubInsecureHttpAction => 'لینک را با نسخهٔ ‎https://‎ آن جایگزین کنید.';

  @override
  String get subInsecureHttpWarning => 'لینک http — به‌روزرسانی مسدود است';

  @override
  String get subSwitchToHttps => 'تغییر به https';

  @override
  String get errorNetworkMessage => 'در حال حاضر سرور در دسترس نیست.';

  @override
  String get errorNetworkAction => 'اینترنت، DNS و در دسترس بودن سرور را بررسی کنید و دوباره تلاش کنید.';

  @override
  String get errorUnknownAction => 'دوباره تلاش کنید. اگر تکرار شد، سرور و تنظیمات برنامه را بررسی کنید.';

  @override
  String get errorFileDialogMessage => 'این نشست دسکتاپ هیچ انتخابگر فایلی ندارد: نه backend پرتال XDG و نه zenity/kdialog.';

  @override
  String get errorFileDialogAction => 'بستهٔ xdg-desktop-portal-gtk (یا zenity) را نصب کنید، یا به‌جای انتخاب فایل متن کانفیگ را بچسبانید.';

  @override
  String get errorTunAdminTitle => 'مجوز لازم است';

  @override
  String get errorVpnPermissionTitle => 'مجوز لازم است';

  @override
  String get errorHwidBindTitle => 'ثبت دستگاه لازم است';

  @override
  String get errorDeviceLimitTitle => 'سقف تعداد دستگاه‌ها پر شده است';

  @override
  String get errorProviderNoHostsTitle => 'تنظیم در پنل سرویس‌دهنده لازم است';

  @override
  String get errorConfigInvalidTitle => 'خطای کانفیگ';

  @override
  String get errorAuthDeniedTitle => 'احراز هویت ناموفق بود';

  @override
  String get errorSubUrlInvalidTitle => 'لینک اشتراک نامعتبر است';

  @override
  String get errorSubInsecureHttpTitle => 'لینک اشتراک ناامن است';

  @override
  String get errorNetworkTitle => 'خطای شبکه';

  @override
  String get errorUnknownTitle => 'عملیات ناموفق بود';

  @override
  String get errorFileDialogTitle => 'پنجرهٔ انتخاب فایل در دسترس نیست';

  @override
  String get serversPin => 'سنجاق کردن سرور';

  @override
  String get serversUnpin => 'برداشتن سنجاق';

  @override
  String get serversRename => 'تغییر نام';

  @override
  String get serversRenameTitle => 'تغییر نام سرور';

  @override
  String get serversRenameHint => 'نام سرور';

  @override
  String get serversRenameReset => 'بازنشانی';

  @override
  String serversRenameOriginal(Object name) {
    return 'نام اصلی: $name';
  }

  @override
  String get serversEditConfig => 'ویرایش کانفیگ';

  @override
  String get serverEditorTitle => 'کانفیگ سرور';

  @override
  String get serverEditorSectionGeneral => 'سرور';

  @override
  String get serverEditorSectionSecurity => 'امنیت';

  @override
  String get serverEditorSectionTransport => 'انتقال';

  @override
  String get serverEditorSectionProtocol => 'تنظیمات پروتکل';

  @override
  String get serverEditorAddress => 'آدرس';

  @override
  String get serverEditorPort => 'پورت';

  @override
  String get serverEditorPassword => 'رمز عبور';

  @override
  String get serverEditorMethod => 'روش رمزنگاری';

  @override
  String get serverEditorEncryption => 'رمزنگاری';

  @override
  String get serverEditorSecurityMode => 'حالت امنیت';

  @override
  String get serverEditorFingerprint => 'اثر انگشت (uTLS)';

  @override
  String get serverEditorAlpn => 'ALPN (جدا شده با ویرگول)';

  @override
  String get serverEditorAllowInsecure => 'پذیرش گواهی نامعتبر (insecure)';

  @override
  String get serverEditorPbk => 'کلید عمومی (pbk)';

  @override
  String get serverEditorSid => 'شناسهٔ کوتاه (sid)';

  @override
  String get serverEditorSpx => 'SpiderX (spx)';

  @override
  String get serverEditorPinnedCert => 'گواهی پین‌شده (SHA-256)';

  @override
  String get serverEditorVerifyCertName => 'بررسی نام گواهی';

  @override
  String get serverEditorPqv => 'کلید پساکوانتومی (ML-DSA-65)';

  @override
  String get serverEditorEarlyData => 'داده زودهنگام، بایت';

  @override
  String get serverEditorPadding => 'پدینگ، بایت';

  @override
  String get serverEditorExtra => 'Extra (JSON)';

  @override
  String get serverEditorAuthority => 'Authority';

  @override
  String get serverEditorSeed => 'Seed';

  @override
  String get serverEditorHttpMethod => 'روش HTTP';

  @override
  String get serverEditorIssueVision => 'Vision فقط روی TCP با TLS یا REALITY کار می‌کند.';

  @override
  String get serverEditorIssueFlow => 'هسته این flow را نمی‌شناسد و کل کانفیگ را رد می‌کند.';

  @override
  String get serverEditorIssueRealityTransport => 'REALITY روی این انتقال کار نمی‌کند.';

  @override
  String get serverEditorIssueRealityKey => 'REALITY به کلید عمومی سرور نیاز دارد.';

  @override
  String get serverEditorIssueEncryption => 'Encryption باید none یا کلید mlkem768x25519plus باشد.';

  @override
  String get serverEditorIssueNoSecurity => 'بدون TLS، REALITY یا Encryption، هسته فقط به آدرس‌های شبکهٔ خصوصی وصل می‌شود.';

  @override
  String get serverEditorTransportType => 'نوع';

  @override
  String get serverEditorPath => 'مسیر';

  @override
  String get serverEditorServiceName => 'نام سرویس gRPC';

  @override
  String get serverEditorMode => 'حالت';

  @override
  String get serverEditorHeaderType => 'نوع هدر';

  @override
  String get serverEditorAuth => 'رمز احراز هویت';

  @override
  String get serverEditorObfs => 'مبهم‌سازی (obfs)';

  @override
  String get serverEditorObfsPassword => 'رمز مبهم‌سازی';

  @override
  String get serverEditorUp => 'آپلود، Mbps';

  @override
  String get serverEditorDown => 'دانلود، Mbps';

  @override
  String get serverEditorMport => 'پرش پورت (mport)';

  @override
  String get serverEditorHopInterval => 'فاصلهٔ پرش، ثانیه';

  @override
  String get serverEditorPinSha256 => 'پین کردن گواهی (SHA-256)';

  @override
  String get serverEditorRawConfig => 'کانفیگ خام';

  @override
  String get serverEditorRawToggle => 'ویرایش به‌صورت متن';

  @override
  String get serverEditorRawOnlyNote => 'این قالب فقط به‌صورت متن خام ویرایش می‌شود';

  @override
  String get serverEditorPreview => 'لینک نهایی';

  @override
  String get serverEditorSubscriptionNote => 'این سرور از یک اشتراک آمده: تغییرات شما بعد از به‌روزرسانی هم می‌ماند.';

  @override
  String get serverEditorOverriddenNote => 'کانفیگ دستی ویرایش شده — به‌روزرسانی اشتراک دیگر آن را جایگزین نمی‌کند.';

  @override
  String get serverEditorRevert => 'بازگشت به کانفیگ اشتراک';

  @override
  String get serverEditorSaved => 'کانفیگ ذخیره شد';

  @override
  String get serverEditorReconnecting => 'کانفیگ ذخیره شد، در حال اتصال دوباره…';

  @override
  String get serverEditorInvalidPort => 'پورت نامعتبر';

  @override
  String get serverEditorServerMissing => 'این سرور دیگر وجود ندارد';

  @override
  String get appearanceTabGeneral => 'عمومی';

  @override
  String get appearanceTabThemes => 'پوسته‌ها';

  @override
  String get appearanceAmoled => 'مشکی کامل (AMOLED)';

  @override
  String get appearanceAmoledNeedsDark => 'با روشن بودن پوستهٔ تیره در دسترس است';

  @override
  String get appearanceHalloween => 'نمایش تزئینات جشن';

  @override
  String get appearanceHalloweenUntil => 'تا ۲ نوامبر';

  @override
  String get appearanceHaptics => 'لرزش';

  @override
  String get appearanceShowTraffic => 'سرعت و حجم ترافیک';

  @override
  String get appearanceShowTime => 'زمان اتصال';

  @override
  String get appearanceShowTrafficSplit => 'ترافیک VPN و مستقیم جداگانه';

  @override
  String get appearanceWaveLatencyColor => 'رنگ موج بر پایهٔ پینگ';

  @override
  String get appearanceFontTitle => 'فونت';

  @override
  String get appearanceFontSystem => 'سیستم';

  @override
  String get settingsResetConfirmTitle => 'تنظیمات بازنشانی شود؟';

  @override
  String get settingsResetConfirmAction => 'بازنشانی';

  @override
  String get settingsXrayResetConfirm => 'این کار تنظیمات پیش‌فرض هستهٔ Xray، TUN و پورت‌های محلی را برمی‌گرداند. برگشت‌پذیر نیست.';

  @override
  String get settingsPermissionsTitle => 'دسترسی‌ها';

  @override
  String get settingsPermissionsSubtitle => 'دسترسی‌های برنامه که می‌توانید ببینید و پس بگیرید';

  @override
  String get settingsPermNotifTitle => 'اعلان‌ها';

  @override
  String get settingsPermNotifDesc => 'نوار وضعیت VPN و اطلاع‌رسانی به‌روزرسانی اشتراک';

  @override
  String get settingsPermBatteryTitle => 'اجرای بدون محدودیت در پس‌زمینه';

  @override
  String get settingsPermBatteryDesc => 'بدون آن، سیستم ممکن است اجازهٔ روشن کردن VPN از کاشی تنظیمات سریع را ندهد';

  @override
  String get settingsPermAutostartTitle => 'اجرای خودکار';

  @override
  String get settingsPermAutostartDesc => 'تنظیم رام سازنده: بدون آن ممکن است VPN از کاشی تنظیمات سریع روشن نشود و در پس‌زمینه خاموش شود';

  @override
  String get settingsPermAutostartHint => 'اجرای خودکار و فعالیت در پس‌زمینه را (معمولاً در بخش باتری) پیدا و مجاز کنید';

  @override
  String get settingsPermStatusGranted => 'داده شده';

  @override
  String get settingsPermStatusDenied => 'داده نشده';

  @override
  String get settingsPermCameraTitle => 'دوربین';

  @override
  String get settingsPermCameraDesc => 'اسکن کد QR کانفیگ';

  @override
  String get settingsPermInstallTitle => 'نصب برنامه';

  @override
  String get settingsPermInstallDesc => 'نصب به‌روزرسانی‌های برنامه';

  @override
  String get settingsPermOpenAppSettings => 'باز کردن تنظیمات برنامه';

  @override
  String get settingsPermRevokeHint => 'هر دسترسی را می‌توانید در تنظیمات برنامه در سیستم پس بگیرید.';

  @override
  String get settingsPermTunHeader => 'حالت TUN (لینوکس)';

  @override
  String get settingsPermTunPasswordlessTitle => 'TUN بدون رمز';

  @override
  String get settingsPermTunDisabled => 'TUN بدون رمز غیرفعال است';

  @override
  String get appearanceNotifSectionTitle => 'اعلان‌ها';

  @override
  String get appearanceNotifSpeedTitle => 'سرعت اتصال در اعلان';

  @override
  String get appearanceNotifUptimeTitle => 'زمان اتصال در اعلان';

  @override
  String get appearanceNotifSubUpdatesTitle => 'اعلان به‌روزرسانی اشتراک';

  @override
  String get tunRememberTitle => 'اجازه به خاطر سپرده شود؟';

  @override
  String get tunRememberMessage => 'حالت TUN به دسترسی root نیاز دارد و هر بار رمز شما را می‌پرسد. یک قانون polkit نصب شود تا از این به بعد بدون رمز اجرا شود؟ برای نصب آن یک بار رمزتان پرسیده می‌شود.';

  @override
  String get tunRememberWarning => 'بعد از این، هر برنامه‌ای که با کاربر شما اجرا شود می‌تواند هستهٔ VPN را بدون رمز با دسترسی root اجرا کند. هر وقت خواستید می‌توانید از «پیشرفته ← دسترسی‌ها» برش گردانید.';

  @override
  String get tunRememberEnable => 'فعال‌سازی';

  @override
  String get tunRememberNotNow => 'فعلاً نه';

  @override
  String get tunRememberInstalled => 'TUN بدون رمز فعال شد';

  @override
  String get tunRememberFailed => 'تغییر مجوز TUN ممکن نشد';

  @override
  String get settingsRoutingPresetRefilterTitle => 'مسدودشده‌ها در روسیه (Re-filter)';

  @override
  String get settingsRoutingPresetWhitelistTitle => 'لیست سفید اینترنت موبایل روسیه';

  @override
  String get settingsRoutingGeoUnknownTitle => 'در پایگاه دادهٔ جغرافیایی نیست — نادیده گرفته می‌شود';

  @override
  String get settingsRoutingGeoUnknownHint => 'هسته با یک کد جغرافیایی ناشناس کل کانفیگ را رد می‌کند، برای همین این موارد پیش از اتصال حذف می‌شوند. با دکمهٔ کرهٔ زمین در بالا یک کد موجود انتخاب کنید.';

  @override
  String get settingsRoutingGeoPickerTooltip => 'درج کد جغرافیایی';

  @override
  String get settingsRoutingGeoPickerTitle => 'کدهای جغرافیایی موجود در پایگاه دادهٔ همراه';

  @override
  String get settingsRoutingGeoPickerSearchHint => 'جست‌وجو، مثلاً telegram';

  @override
  String get settingsRoutingGeoPickerEmpty => 'کدی پیدا نشد';

  @override
  String get settingsRoutingGeoPickerGeosite => 'دامنه‌ها (geosite)';

  @override
  String get settingsRoutingGeoPickerGeoip => 'بازه‌های آی‌پی (geoip)';

  @override
  String get settingsOpenConnections => 'اتصال‌ها';

  @override
  String get settingsConnectionsTitle => 'اتصال‌ها';

  @override
  String get connectionsEmpty => 'هنوز اتصالی ثبت نشده است.';

  @override
  String get connectionsUnavailable => 'فهرست اتصال‌ها در دسترس نیست.';

  @override
  String get connectionsFilterHint => 'فیلتر بر اساس دامنه، آی‌پی، برنامه یا قانون';

  @override
  String connectionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count اتصال',
      one: '1 اتصال',
      zero: 'بدون اتصال',
    );
    return '$_temp0';
  }

  @override
  String get connectionsPause => 'توقف به‌روزرسانی';

  @override
  String get connectionsResume => 'ادامهٔ به‌روزرسانی';

  @override
  String get connectionsPaused => 'متوقف';

  @override
  String get connectionsSourceApi => 'زنده از هسته';

  @override
  String get connectionsSourceLog => 'از گزارش هسته';

  @override
  String get connectionsSourceUnavailable => 'بدون منبع';

  @override
  String get connectionsRuleHint => 'هسته دامنه‌ها و قانونی را که گرفته است فقط در سطح گزارش Info می‌نویسد.';

  @override
  String get connectionsRuleHintAction => 'تنظیم روی Info';

  @override
  String get connectionsRuleHintApplied => 'سطح گزارش هسته روی Info تنظیم شد؛ برای اعمال، دوباره وصل شوید';

  @override
  String get connectionsRuleDefault => 'بدون قانون (عملکرد پیش‌فرض)';

  @override
  String get connectionsRuleViaCore => 'داخل هسته تصمیم گرفته شد (به گزارش Info نیاز دارد)';

  @override
  String get connectionsRuleViaCoreUnseen => 'هسته تصمیم می‌گیرد، تصمیمش در گزارش نیست';

  @override
  String get connectionsVerdictCore => 'هسته';

  @override
  String get connectionsVerdictProxy => 'پروکسی';

  @override
  String get connectionsVerdictDirect => 'مستقیم';

  @override
  String get connectionsVerdictBlock => 'مسدود';

  @override
  String get connectionsClosed => 'بسته شد';

  @override
  String get connectionsAppNamesHint => 'نام برنامه را سیستم می‌دهد و فقط اتصال‌های زنده را می‌شناسد؛ اتصال‌های بسته نامی ندارند.';

  @override
  String get connectionsSplitTunnelNote => 'برنامه‌هایی که بیرون تونل مانده‌اند اینجا نمی‌آیند: اندروید آن‌ها را از کنار تونل رد می‌کند. ردیفی با قانون outside-vpn یعنی چنین برنامه‌ای خودش اتصالی را به تونل فرستاده و هسته آن را رد کرده است.';

  @override
  String subscriptionsExpiredOn(String date) {
    return 'اشتراک در $date منقضی شد';
  }

  @override
  String get subscriptionsExpiredHint => 'سرویس‌دهنده دیگر فهرست سرورها را به‌روز نمی‌کند. برای ادامهٔ کار اشتراک را تمدید کنید.';

  @override
  String get subscriptionsExpiredNotifTitle => 'اشتراک منقضی شد';

  @override
  String subscriptionsExpiredNotifBody(String name, String date) {
    return '«$name» در $date منقضی شد. سرویس‌دهنده دیگر فهرست سرورها را به‌روز نمی‌کند — برای اینکه سرورها کار کنند تمدیدش کنید.';
  }

  @override
  String get chainTitle => 'زنجیرهٔ پروکسی';

  @override
  String get chainNew => 'زنجیرهٔ جدید';

  @override
  String get chainCreate => 'ساخت زنجیره';

  @override
  String get chainCreateDesc => 'عبور ترافیک از چند سرور پشت سر هم';

  @override
  String get chainGroupTitle => 'زنجیره‌ها';

  @override
  String get chainNameLabel => 'نام زنجیره';

  @override
  String get chainNameHint => 'خالی بگذارید تا بر اساس مسیر نام‌گذاری شود';

  @override
  String get chainHint => 'ترافیک از بالا به پایین می‌رود: این دستگاه به گرهٔ اول وصل می‌شود و سایت‌ها آدرس گرهٔ آخر را می‌بینند.';

  @override
  String get chainDeviceNode => 'این دستگاه';

  @override
  String get chainInternetNode => 'اینترنت';

  @override
  String get chainAddNode => 'افزودن گره';

  @override
  String get chainRemoveNode => 'حذف گره';

  @override
  String get chainExitNodeHint => 'گرهٔ خروجی؛ سایت‌ها آدرس آن را می‌بینند';

  @override
  String get chainNodeMissing => 'این سرور دیگر وجود ندارد؛ از نسخهٔ ذخیره‌شده استفاده می‌شود';

  @override
  String get chainSave => 'ذخیرهٔ زنجیره';

  @override
  String get chainNeedsTwoNodes => 'زنجیره دست‌کم به دو گره نیاز دارد';

  @override
  String get chainPickNode => 'انتخاب سرور';

  @override
  String get chainPickSearch => 'جست‌وجوی سرورها';

  @override
  String chainPickEmpty(String core) {
    return 'هیچ سروری نیست که $core بتواند گرهٔ زنجیره کند. هستهٔ دیگر را در «درباره» انتخاب کنید.';
  }

  @override
  String get chainEdit => 'ویرایش زنجیره';

  @override
  String get chainDelete => 'حذف زنجیره';

  @override
  String get chainRouteLabel => 'مسیر';

  @override
  String chainMaxNodes(int max) {
    return 'زنجیره حداکثر $max گره دارد';
  }

  @override
  String chainDeleteConfirm(String name) {
    return 'زنجیرهٔ «$name» حذف شود؟ سرورهای آن در فهرست باقی می‌مانند.';
  }

  @override
  String chainNodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count گره',
      one: '1 گره',
      zero: 'بدون گره',
    );
    return '$_temp0';
  }

  @override
  String get settingsInternalsTitle => 'درباره';

  @override
  String get settingsInternalsSubtitle => 'نسخه، هسته‌ها، پایگاه‌های جغرافیایی و نشست جاری';

  @override
  String get settingsCoreXraySubtitle => 'هستهٔ پیش‌فرض. لینک‌ها، زنجیره‌ها و کانفیگ‌های آمادهٔ Xray را اجرا می‌کند.';

  @override
  String get settingsCoreMihomoSubtitle => 'هستهٔ سازگار با Clash. کانفیگ‌های آمادهٔ xray روی Xray می‌مانند.';

  @override
  String get settingsCoreHint => 'از اتصال بعدی اعمال می‌شود — نشست فعلی راه‌اندازی مجدد نمی‌شود.';

  @override
  String get settingsProxyAuthTitle => 'رمز عبور پروکسی محلی';

  @override
  String get settingsProxyAuthSubtitle => 'جایی که جای وارد کردن آن نیست خاموش کنید — مثلاً فیلد پروکسی وای‌فای';

  @override
  String get settingsProxyAuthUser => 'نام کاربری';

  @override
  String get settingsProxyAuthPass => 'رمز عبور';

  @override
  String get settingsTunnelModeSection => 'حالت اتصال';

  @override
  String get settingsTunnelModeVpn => 'VPN';

  @override
  String get settingsTunnelModeVpnSubtitle => 'همهٔ ترافیک دستگاه از تونل عبور می‌کند';

  @override
  String get settingsTunnelModeProxy => 'پروکسی';

  @override
  String get settingsTunnelModeProxySubtitle => 'فقط پروکسی محلی، بدون VPN سیستمی';

  @override
  String get settingsTunnelModeHint => 'حالت پروکسی، SOCKS و HTTP را روی 127.0.0.1 راه‌اندازی می‌کند؛ برنامه یا وای‌فای را روی آن‌ها تنظیم کنید. این پروکسی برای همهٔ برنامه‌های دستگاه باز است. مسیریابی به تفکیک برنامه و رهگیری DNS فقط در حالت VPN کار می‌کنند.';

  @override
  String get settingsCoreSkipClash => 'سرور فعال یک کانفیگ آمادهٔ Clash است — صرف‌نظر از هستهٔ انتخاب‌شده تنها mihomo آن را اجرا می‌کند.';

  @override
  String get settingsCoreSkipCustom => 'سرور فعال یک کانفیگ آمادهٔ JSON برای Xray است، پس صرف‌نظر از هستهٔ انتخابی با libxray اجرا می‌شود. mihomo به اشتراکی با لینک‌های معمولی نیاز دارد.';

  @override
  String get settingsCoreSkipChainXrayOnly => 'سرور فعال یک زنجیره است که mihomo نمی‌تواند برخی گره‌های آن را به هم وصل کند — صرف‌نظر از هستهٔ انتخاب‌شده با Xray اجرا می‌شود.';

  @override
  String get settingsCoreSkipChainMihomoOnly => 'در زنجیرهٔ سرور فعال گره‌ای هست که فقط mihomo می‌تواند وصلش کند، مثلاً پروفایل AmneziaWG — صرف‌نظر از هستهٔ انتخاب‌شده با mihomo اجرا می‌شود.';

  @override
  String get settingsCoreSkipAwg => 'سرور فعال یک پروفایل AmneziaWG است — صرف‌نظر از هستهٔ انتخاب‌شده با mihomo اجرا می‌شود.';

  @override
  String get settingsCoreSkipPlatform => 'هستهٔ mihomo برای این پلتفرم ارائه نمی‌شود — اتصال از هستهٔ Xray انجام می‌شود.';

  @override
  String get settingsCoreSkipLinkXrayOnly => 'لینک سرور فعال از انتقالی استفاده می‌کند که mihomo برای این پروتکل ندارد — صرف‌نظر از هستهٔ انتخاب‌شده با Xray اجرا می‌شود.';

  @override
  String get settingsCoreSkipLinkMihomoOnly => 'لینک سرور فعال از انتقالی استفاده می‌کند که Xray 26 حذف کرده است — صرف‌نظر از هستهٔ انتخاب‌شده با mihomo اجرا می‌شود.';

  @override
  String get settingsInternalsCores => 'هسته‌ها';

  @override
  String get settingsInternalsGeo => 'پایگاه‌های جغرافیایی';

  @override
  String get settingsInternalsSession => 'نشست جاری';

  @override
  String get settingsInternalsExits => 'چرا برنامه بسته شد';

  @override
  String get settingsInternalsExitsHint => 'این سوابق را خود سیستم نگه می‌دارد. اگر VPN در پس‌زمینه قطع شد، آن‌ها را با دکمهٔ بالا کپی و ارسال کنید.';

  @override
  String get settingsInternalsExitSystem => 'توسط سیستم یا رام سازنده متوقف شد';

  @override
  String get settingsInternalsExitMemory => 'حافظهٔ سیستم کم آمد';

  @override
  String get settingsInternalsExitCrash => 'برنامه از کار افتاد';

  @override
  String get settingsInternalsExitUser => 'به‌صورت دستی بسته شد';

  @override
  String get settingsInternalsExitUserOrUpdate => 'به‌صورت دستی یا با به‌روزرسانی بسته شد';

  @override
  String get settingsInternalsExitUpdate => 'به‌روزرسانی برنامه یا تغییر دسترسی‌ها';

  @override
  String get settingsInternalsExitSelf => 'برنامه خودش بسته شد';

  @override
  String get settingsInternalsExitVpnOn => 'VPN روشن بود';

  @override
  String get appLogTitle => 'گزارش برنامه';

  @override
  String get appLogSubtitle => 'چه اتفاقی افتاد و چه چیزی خطا داد — به تفکیک بخش‌های برنامه';

  @override
  String get appLogSourceApp => 'برنامه';

  @override
  String get appLogSourceAppDesc => 'رابط کاربری، اشتراک‌ها، اتصال';

  @override
  String get appLogSourceNative => 'بخش نیتیو';

  @override
  String get appLogSourceNativeDesc => 'سرویس VPN، کاشی تنظیمات سریع، پنجرهٔ اتصال';

  @override
  String get appLogSourceExitsDesc => 'سوابق سیستم: برنامه کی و چرا بسته شد';

  @override
  String appLogProblems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مشکل',
      zero: 'بدون مشکل',
    );
    return '$_temp0';
  }

  @override
  String get appLogOnlyProblems => 'فقط مشکل‌ها';

  @override
  String get appLogEmpty => 'هنوز چیزی نیست';

  @override
  String get appLogCopyAll => 'کپی کل گزارش';

  @override
  String get settingsInternalsBuild => 'برنامه و دستگاه';

  @override
  String get settingsInternalsCopyAll => 'کپی گزارش';

  @override
  String get settingsInternalsCopied => 'گزارش کپی شد';

  @override
  String get settingsInternalsNoCores => 'برای این پلتفرم هسته‌ای ارائه نشده است';

  @override
  String get settingsInternalsCoreMissing => 'یافت نشد';

  @override
  String get settingsInternalsVersionFromEngines => 'ساخته‌شده از کد منبع';

  @override
  String get settingsInternalsRoleCore => 'موتور پروکسی و TUN';

  @override
  String get settingsInternalsRoleProxy => 'موتور پروکسی';

  @override
  String get settingsInternalsRoleTun => 'دستگاه TUN';

  @override
  String settingsInternalsGeoCodes(int count) {
    return 'کدها: $count';
  }

  @override
  String get settingsInternalsGeoTrimmed => 'پایگاه دادهٔ کشورها نسخهٔ کوتاه‌شده است';

  @override
  String get settingsInternalsGeoTrimmedHint => 'فقط کدهایی که قالب‌های آمادهٔ برنامه لازم دارند؛ قانونی که کشور دیگری داشته باشد کنار گذاشته می‌شود.';

  @override
  String get settingsInternalsGeoDownload => 'دریافت پایگاه دادهٔ کامل';

  @override
  String settingsInternalsGeoDownloadFailed(String error) {
    return 'دریافت ناموفق بود: $error';
  }

  @override
  String get settingsInternalsStatus => 'وضعیت';

  @override
  String get settingsInternalsStatusError => 'خطا';

  @override
  String get settingsInternalsEngine => 'موتور';

  @override
  String get settingsInternalsMode => 'حالت';

  @override
  String get settingsInternalsPorts => 'پورت‌های محلی';

  @override
  String get settingsInternalsClashPort => 'پورت Clash API';

  @override
  String get settingsInternalsUptime => 'مدت نشست';

  @override
  String get settingsInternalsCorePids => 'فرایندهای هسته';

  @override
  String get settingsInternalsElevated => 'دسترسی مدیر';

  @override
  String get settingsInternalsYes => 'بله';

  @override
  String get settingsInternalsNo => 'خیر';

  @override
  String get settingsInternalsAppVersion => 'نسخهٔ برنامه';

  @override
  String get settingsInternalsPackage => 'بسته';

  @override
  String get settingsInternalsOs => 'سیستم';

  @override
  String get settingsInternalsAbi => 'معماری';

  @override
  String get settingsInternalsDart => 'Dart';

  @override
  String get settingsInternalsBuildMode => 'نوع ساخت';

  @override
  String get settingsInternalsUnavailable => '—';

  @override
  String get appearanceCustomColorTitle => 'رنگ دلخواه';

  @override
  String get appearanceCustomColorSheetTitle => 'رنگ دلخواه';

  @override
  String get appearanceCustomColorHue => 'ته‌رنگ';

  @override
  String get appearanceCustomColorSaturation => 'اشباع';

  @override
  String get appearanceCustomColorBrightness => 'روشنایی';

  @override
  String get appearanceCustomColorHex => 'کد HEX';

  @override
  String get appearanceCustomColorInvalid => 'شش رقم هگزادسیمال، برای مثال 7B2CBF';

  @override
  String get appearanceCustomColorApply => 'اعمال';

  @override
  String get appearanceCustomColorVariant => 'پالت';

  @override
  String get appearanceCustomColorVariantCalm => 'آرام';

  @override
  String get appearanceCustomColorVariantVibrant => 'پرمایه';

  @override
  String get appearanceCustomColorVariantExact => 'دقیق';

  @override
  String get appearanceCustomColorVariantHint => 'اشباع و روشنایی فقط در حالت «دقیق» اثر دارند؛ دو حالت دیگر خودشان آن‌ها را انتخاب می‌کنند.';

  @override
  String get appearanceUiScaleTitle => 'اندازهٔ رابط کاربری';

  @override
  String get appearanceUiScaleSubtitle => 'کل رابط کاربری، روی مقیاس سیستم.';

  @override
  String get appearanceIconShapeTitle => 'شکل آیکون‌ها';

  @override
  String get appearanceIconShapeCircle => 'دایره';

  @override
  String get subscriptionCardThemeTitle => 'پس‌زمینه';

  @override
  String get subscriptionCardThemeNone => 'بدون';

  @override
  String get subscriptionCardThemeInServers => 'نمایش در فهرست سرورها';

  @override
  String get subscriptionCardLookTitle => 'ظاهر کارت';

  @override
  String get subscriptionCardVeilTitle => 'تیرگی تصویر';

  @override
  String get subscriptionCardVeilNone => 'خاموش';

  @override
  String get subscriptionCardVeilLight => 'کم';

  @override
  String get subscriptionCardVeilMedium => 'متوسط';

  @override
  String get subscriptionCardVeilStrong => 'زیاد';

  @override
  String get subscriptionCardAutoSelect => 'کلید «خودکار» در فهرست سرورها';

  @override
  String get subscriptionCardAutoSelectHint => 'کلید «خودکار» را به سرتیتر گروه اضافه می‌کند. وقتی روشن باشد، برنامه خودش سرور را انتخاب می‌کند و وقتی سرور فعلی از کار بیفتد، به سرور دیگری می‌رود.';

  @override
  String get subscriptionCardContentTitle => 'چه چیزی نمایش داده شود';

  @override
  String get subscriptionCardPresetFull => 'کامل';

  @override
  String get subscriptionCardPresetCompact => 'فشرده';

  @override
  String get subscriptionCardPresetMinimal => 'کمینه';

  @override
  String get subscriptionCardPresetCustom => 'دلخواه';

  @override
  String get subscriptionCardElementAnnounce => 'اطلاعیهٔ سرویس‌دهنده';

  @override
  String get subscriptionCardElementUsage => 'ترافیک';

  @override
  String get subscriptionCardElementMeta => 'انقضا و به‌روزرسانی';

  @override
  String get subscriptionCardElementActions => 'دکمه‌ها';

  @override
  String get subscriptionCardContentHint => 'هشدارها همیشه نمایش داده می‌شوند: اشتراک منقضی، لینک ناامن، به‌روزرسانی ناموفق.';

  @override
  String get appearanceIconShapeSquare => 'مربع';

  @override
  String get appearanceIconShapeArch => 'قوس';

  @override
  String get appearanceSectionServers => 'فهرست سرورها';

  @override
  String get appearanceSectionUnderButton => 'زیر دکمهٔ اتصال';

  @override
  String get appearanceSectionConnectPanel => 'صفحهٔ اصلی';

  @override
  String get appearanceConnectPanelLegacy => 'کلاسیک';

  @override
  String get appearanceConnectPanelModern => 'مدرن';

  @override
  String get appearanceBarStrip => 'نوار';

  @override
  String get appearanceBarBrightPlus => 'بعلاوهٔ روشن';

  @override
  String get appearanceBarIslands => 'جزیره‌ها';

  @override
  String get appearancePartTop => 'بالای صفحه';

  @override
  String get appearancePartBottom => 'نوار پایین';

  @override
  String get appearanceSectionFeel => 'بازخورد لمسی';

  @override
  String get appearanceIconShapeClover => 'شبدر';

  @override
  String get appearanceIconShapeCookie => 'کوکی';

  @override
  String get appearanceIconShapeFlower => 'گل';

  @override
  String get appearanceIconShapeSlanted => 'مورب';

  @override
  String get appearanceIconShapePill => 'کپسول';

  @override
  String get appearanceIconShapeGem => 'نگین';

  @override
  String get appearanceIconShapeSunny => 'خورشید';

  @override
  String get appearanceIconShapePuffy => 'ابر';

  @override
  String get appearanceIconShapePebble => 'سنگریزه';

  @override
  String get cardImageRejectAspect => 'این تصویر برای کارت بیش از حد بلند است. تصویری عریض انتخاب کنید، تقریباً از 3:2 تا 5:1.';

  @override
  String cardImageRejectSmall(int width) {
    return 'تصویر کوچک است: حداقل $width پیکسل عرض.';
  }

  @override
  String cardImageRejectLarge(int width) {
    return 'تصویر بزرگ است: حداکثر $width پیکسل عرض.';
  }

  @override
  String get cardImageRejectUnreadable => 'خواندن این تصویر ممکن نشد.';
}
