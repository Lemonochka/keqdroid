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
  String get errorProviderConfigTitle => 'تنظیمات پنل لازم است';

  @override
  String get errorProviderNoHostsMessage => 'فروشنده هیچ هاستی به این اشتراک اختصاص نداده است.';

  @override
  String get errorProviderNoHostsAction => 'وارد پنل فروشنده شوید، هاست اضافه یا اختصاص دهید و بعد اشتراک را به‌روزرسانی کنید.';

  @override
  String errorActionLabel(Object action) {
    return 'راه‌حل: $action';
  }

  @override
  String get splitTunnelingTitle => 'پروکسی هر برنامه';

  @override
  String get splitModeAllApps => 'همهٔ برنامه‌ها';

  @override
  String get splitModeSelectedOnly => 'فقط انتخاب‌شده‌ها';

  @override
  String get splitModeAllExceptSelected => 'همه به‌جز انتخاب‌شده‌ها';

  @override
  String get splitSearchHint => 'جستجوی برنامه...';

  @override
  String get splitNoAppsFound => 'برنامه‌ای پیدا نشد';

  @override
  String splitFailedLoadApps(Object error) {
    return 'بارگذاری برنامه‌ها ناموفق بود: $error';
  }

  @override
  String splitSelectedAppsCount(int count) {
    return '$count برنامه انتخاب شد';
  }

  @override
  String get splitHideSystemApps => 'پنهان کردن برنامه‌های سیستمی';

  @override
  String get splitShowSystemApps => 'نمایش برنامه‌های سیستمی';

  @override
  String get splitAddRussianAppsBypass => 'افزودن برنامه‌های روسی به فهرست دور زدن';

  @override
  String get splitClear => 'پاک‌سازی';

  @override
  String get splitNoRussianAppsFound => 'در فهرست برنامه‌های نصب‌شده، برنامهٔ روسی پیدا نشد';

  @override
  String get splitRussianAppsAlreadyAdded => 'همهٔ برنامه‌های روسی از قبل در فهرست دور زدن هستند';

  @override
  String splitAddedRussianApps(int count) {
    return '$count برنامهٔ روسی به فهرست دور زدن اضافه شد';
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
  String get settingsSplitTitle => 'پروکسی هر برنامه';

  @override
  String get settingsRoutingTitle => 'قوانین مسیریابی';

  @override
  String settingsSplitConfigured(int count) {
    return '$count برنامه تنظیم شده';
  }

  @override
  String get settingsRoutingSubtitle => 'قوانین مستقیم / پروکسی / مسدود و قالب‌های آماده';

  @override
  String get settingsResetRoutingTitle => 'بازنشانی مسیریابی به حالت پیش‌فرض';

  @override
  String get settingsRoutingResetDone => 'قوانین مسیریابی بازنشانی شد';

  @override
  String get settingsRoutingHeaderDesc => 'تعیین کنید کدام سایت‌ها مستقیم و بدون VPN بروند، کدام حتماً از VPN رد شوند و کدام مسدود باشند. برای شروع سریع یک قالب آماده بردارید و بعد فهرست‌های پایین را دقیق‌تر کنید.';

  @override
  String get settingsRoutingPresetsTitle => 'قالب‌های آماده';

  @override
  String get settingsRoutingPresetsHint => 'یک فهرست آماده انتخاب کنید تا به فهرست متناظر پایین اضافه شود. بعداً می‌توانید موارد آن را ویرایش یا حذف کنید.';

  @override
  String get settingsRoutingPresetChoose => 'انتخاب قالب…';

  @override
  String get settingsRoutingPresetAdd => 'افزودن';

  @override
  String get settingsRoutingPresetRuTitle => 'سایت‌های روسی — مستقیم';

  @override
  String get settingsRoutingPresetRuDesc => 'همهٔ دامنه‌های ru. و رф. و سرویس‌های بزرگ روسیه بدون VPN باز می‌شوند (به فهرست مستقیم اضافه می‌شود)';

  @override
  String get settingsRoutingPresetRuGeoipTitle => 'آی‌پی‌های روسیه (GeoIP) — مستقیم';

  @override
  String get settingsRoutingPresetRuGeoipDesc => 'همهٔ بازه‌های آی‌پی روسیه از طریق GeoIP بدون VPN می‌روند — در حالت پروکسی هم کار می‌کند';

  @override
  String get settingsRoutingPresetRuGeositeTitle => 'سایت‌های روسیه (GeoSite) — مستقیم';

  @override
  String get settingsRoutingPresetRuGeositeDesc => 'دامنه‌های روسی از پایگاه دادهٔ GeoSite بدون VPN می‌روند';

  @override
  String get settingsRoutingPresetBanksTitle => 'بانک‌ها و دولتی — مستقیم';

  @override
  String get settingsRoutingPresetBanksDesc => 'بانک‌ها، درگاه‌های پرداخت و سامانه‌های دولتی بدون VPN باز می‌شوند';

  @override
  String get settingsRoutingPresetLanIpsTitle => 'شبکهٔ محلی — مستقیم';

  @override
  String get settingsRoutingPresetLanIpsDesc => 'بازه‌های آی‌پی شبکهٔ داخلی (192.168.x، 10.x، …) بدون VPN می‌روند';

  @override
  String get settingsRoutingPresetAdsTitle => 'تبلیغات و ردیاب‌ها — مسدود';

  @override
  String get settingsRoutingPresetAdsDesc => 'هاست‌های رایج تبلیغات و آمارگیری حذف می‌شوند';

  @override
  String get settingsRoutingPresetAdsGeositeTitle => 'تبلیغات (GeoSite) — مسدود';

  @override
  String get settingsRoutingPresetAdsGeositeDesc => 'مسدودسازی فهرست گستردهٔ تبلیغات و ردیاب‌ها از پایگاه دادهٔ GeoSite';

  @override
  String get settingsRoutingPresetStreamingTitle => 'سرویس‌های ویدیویی — پروکسی';

  @override
  String get settingsRoutingPresetStreamingDesc => 'یوتیوب، نتفلیکس و توییچ حتماً از VPN رد می‌شوند';

  @override
  String get settingsRoutingPresetMessengersTitle => 'پیام‌رسان‌ها — پروکسی';

  @override
  String get settingsRoutingPresetMessengersDesc => 'تلگرام، دیسکورد و واتساپ حتماً از VPN رد می‌شوند';

  @override
  String settingsRoutingPresetApplied(String name) {
    return '«$name» اضافه شد';
  }

  @override
  String get settingsRoutingDirectTitle => 'مستقیم (بدون VPN)';

  @override
  String get settingsRoutingDirectDesc => 'دامنه‌ها و آی‌پی‌های این فهرست مستقیم و بدون VPN وصل می‌شوند.';

  @override
  String get settingsRoutingProxyTitle => 'پروکسی (اجبار به VPN)';

  @override
  String get settingsRoutingProxyDesc => 'دامنه‌ها و آی‌پی‌های این فهرست همیشه از VPN رد می‌شوند.';

  @override
  String get settingsRoutingBlockTitle => 'مسدود';

  @override
  String get settingsRoutingBlockDesc => 'دامنه‌ها و آی‌پی‌های این فهرست حذف می‌شوند و اصلاً وصل نمی‌شوند.';

  @override
  String get settingsRoutingSyntaxHint => 'هر فهرست هم دامنه می‌پذیرد هم آی‌پی، جدا شده با ویرگول یا خط جدید:\n• ru — هر هاستی که به ru. ختم شود (کلمهٔ خالی = پسوند دامنه)\n• vk.com — همان دامنه و زیردامنه‌هایش\n• example.com. — فقط زیردامنه‌ها\n• 10.0.0.0/8 یا 1.2.3.4 — آدرس آی‌پی یا بازهٔ CIDR\n• geoip:ru / geosite:refilter — کدهای GeoIP/GeoSite از پایگاه دادهٔ همراه برنامه\nآی‌پی‌های شبکهٔ داخلی و خود سرور شما همیشه خودکار مستقیم می‌مانند.';

  @override
  String get settingsRoutingValuesHint => 'هر مورد در یک خط، یا جدا شده با ویرگول';

  @override
  String get settingsRoutingFinalTitle => 'ترافیک بدون قانون';

  @override
  String get settingsRoutingFinalDesc => 'کاری که با ترافیک خارج از قوانین انجام می‌شود.';

  @override
  String get settingsRoutingFinalProxy => 'پروکسی';

  @override
  String get settingsRoutingFinalDirect => 'دور زدن';

  @override
  String get settingsRoutingFinalBlock => 'مسدود';

  @override
  String get settingsRoutingAdvancedTitle => 'قوانین دلخواه';

  @override
  String get settingsRoutingAdvancedHint => 'قوانین تکی با کلید روشن/خاموش جداگانه. بعد از فهرست‌های بالا اعمال می‌شوند.';

  @override
  String get settingsRoutingAdvancedEmpty => 'هنوز قانون دلخواهی ندارید';

  @override
  String get settingsRoutingAdvancedAdd => 'افزودن قانون';

  @override
  String get settingsRoutingRuleNewTitle => 'قانون جدید';

  @override
  String get settingsRoutingRuleEditTitle => 'ویرایش قانون';

  @override
  String get settingsRoutingRuleName => 'نام';

  @override
  String get settingsRoutingRuleNameHint => 'مثلاً سرویس‌های ویدیویی';

  @override
  String get settingsRoutingRuleValues => 'مقادیر';

  @override
  String get settingsRoutingRuleValuesHint => 'هر مورد در یک خط یا جدا شده با ویرگول';

  @override
  String get settingsRoutingRuleMatchBy => 'تطابق بر اساس';

  @override
  String get settingsRoutingRuleTypeDomain => 'دامنه';

  @override
  String get settingsRoutingRuleTypeIp => 'IP / CIDR';

  @override
  String get settingsRoutingRuleTypeGeoip => 'GeoIP';

  @override
  String get settingsRoutingRuleTypeGeosite => 'GeoSite';

  @override
  String get settingsRoutingRuleAction => 'عملکرد';

  @override
  String get settingsRoutingRuleSave => 'ذخیره';

  @override
  String get settingsRoutingRuleDeleteConfirm => 'این قانون حذف شود؟';

  @override
  String get routingCheatSheetTitle => 'نحوهٔ نوشتن قوانین';

  @override
  String get routingCheatSheetBody => 'قانون‌ها فقط یک فهرست‌اند: چه چیزی از کجا برود. هر خط یک دامنه، یک آی‌پی یا یک برچسب جغرافیایی است و کنارش عملکرد — مستقیم (دور زدن)، از داخل VPN (پروکسی)، یا مسدود.\n\n## دامنه‌ها\nvk.com — خود دامنه و همهٔ زیردامنه‌هایش\nru — هر چیزی که به ru. ختم شود (کلمهٔ خالی، بدون نقطه)\nexample.com. — فقط زیردامنه‌ها، نه خود دامنه\nfull:example.com — دقیقاً همین هاست، بدون زیردامنه\nregexp:… — عبارت منظم، اگر واقعاً لازم شد\n\n## آدرس‌های آی‌پی\n1.2.3.4 — یک آدرس\n10.0.0.0/8 — یک بازهٔ کامل (CIDR)\n\n## GeoIP — بر اساس کشور\ngeoip:ru — همهٔ آی‌پی‌های روسیه. به‌جای ru هر کشوری بگذارید: us، de، cn، ua، kz…\nبستهٔ آمادهٔ دیگری هم هست: geoip:private (شبکهٔ داخلی)، geoip:telegram، geoip:google.\nکشوری لازم دارید؟ همین است — geoip همهٔ کشورها را می‌شناسد.\n\n## GeoSite — فهرست‌های آماده\ngeosite:google، geosite:netflix، geosite:telegram، geosite:category-ads-all…\nاین‌ها کشور نیستند، دسته‌بندی سرویس‌اند که از قبل برایتان جمع شده.\nکشور اینجا تقریباً نیست (فقط geolocation-cn و geolocation-!cn)، پس کار کشوری با geoip است.\n\n## روی کامپیوتر (هستهٔ keqrnel)\nبخش جغرافیایی مثل موبایل کار می‌کند: xray داخل keqrnel تطابق را انجام می‌دهد. فقط باید geoip.dat و geosite.dat کنار keqdroid.exe باشند — در نسخهٔ رسمی از قبل آنجا هستند. اگر قوانین جغرافیایی نادیده گرفته می‌شوند، اول همین دو فایل را ببینید.\n\n## ترتیب\nاز بالا به پایین: اول مسدود، بعد سرور خودتان (همیشه مستقیم، وگرنه حلقه می‌شود)، بعد دور زدن، بعد پروکسی. هرچه ماند، از کلید «ترافیک بدون قانون» در بالا پیروی می‌کند.';

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
  String get themeUseDynamicColorsSubtitle => 'در صورت پشتیبانی، از رنگ‌های پویای اندروید استفاده شود';

  @override
  String get themeDynamicPaletteHint => 'پالت پویای اندروید فعال است. حالت روشن و تیره جداگانه کار می‌کنند.';

  @override
  String get themeSystemPaletteHint => 'پالت رنگ تأکیدی سیستم فعال است. حالت روشن و تیره جداگانه کار می‌کنند.';

  @override
  String get themeUseSystemColors => 'استفاده از رنگ تأکیدی سیستم';

  @override
  String get themeUseSystemColorsSubtitle => 'در صورت پشتیبانی، از رنگ تأکیدی ویندوز یا لینوکس پیروی کن';

  @override
  String get themeCustomPaletteHint => 'پالت دلخواه فعال است. حالت روشن و تیره جداگانه کار می‌کنند.';

  @override
  String get themeColorThemesTitle => 'پوسته‌های رنگی';

  @override
  String get serversTwoColumnsTitle => 'فهرست دوستونی سرورها';

  @override
  String get serversTwoColumnsSubtitle => 'نمایش سرورها در دو ستون تا تعداد بیشتری در صفحه جا شود';

  @override
  String get settingsLanProxyTitle => 'پروکسی شبکهٔ محلی';

  @override
  String get settingsOff => 'خاموش';

  @override
  String settingsLanSharingOnIp(Object ip) {
    return 'در حال اشتراک روی $ip';
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
  String get settingsLocalPortsHint => 'پورت‌های شنود پروکسی محلی SOCKS5 و HTTP (پیش‌فرض 2080 / 2081). از اتصال بعدی اعمال می‌شود. دو پورت باید متفاوت باشند.';

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
  String get settingsXrayCoreSubtitle => 'پورت‌ها، DNS، XMUX، TUN، گزارش و مسیریابی';

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
  String get settingsXrayGeneralSection => 'عمومی';

  @override
  String get settingsXrayLogLevel => 'سطح گزارش‌گیری';

  @override
  String get settingsXrayDomainStrategy => 'استراتژی دامنه در مسیریابی';

  @override
  String get settingsXraySniffing => 'شناسایی ترافیک ورودی';

  @override
  String get settingsXraySniffingRouteOnly => 'شناسایی فقط برای مسیریابی';

  @override
  String get settingsXrayCoreIntro => 'این گزینه‌ها مستقیم داخل کانفیگ ساخته‌شدهٔ Xray می‌روند. فقط وقتی تغییرشان دهید که بدانید چه کار می‌کنند.';

  @override
  String get settingsXrayDnsDefaultNote => 'پیش‌فرض: DoH کلادفلر و گوگل';

  @override
  String get settingsXrayXmuxParamsTitle => 'تنظیم دقیق';

  @override
  String get settingsXrayXmuxParamsHint => 'خالی بگذارید تا مقادیر پیش‌فرض Xray به کار برود. مقدار می‌تواند عدد یا بازه باشد (مثلاً 16-32).';

  @override
  String get settingsXraySniffingHint => 'تشخیص پروتکل و دامنهٔ مقصد از روی ترافیک ورودی';

  @override
  String get settingsXraySniffingRouteOnlyHint => 'خاموش (پیش‌فرض): دامنهٔ شناسایی‌شده مقصد می‌شود و دوباره ترجمه می‌شود — برای مسیر مستقیم به‌صورت محلی و برای مسیر پروکسی روی سرور. روشن: دامنه فقط قاعده را انتخاب می‌کند و اتصال به همان نشانی‌ای می‌رود که برنامه داده — و هر وقت آن نشانی از یک ریزالور آن‌سوی تونل آمده باشد، نادرست است.';

  @override
  String get settingsXrayResetDefaults => 'بازگشت به پیش‌فرض';

  @override
  String get settingsXrayResetDone => 'تنظیمات هستهٔ Xray بازنشانی شد';

  @override
  String get settingsXrayXmuxMaxConcurrency => 'بیشینهٔ هم‌زمانی';

  @override
  String get settingsXrayXmuxMaxConnections => 'بیشینهٔ اتصال‌ها';

  @override
  String get settingsXrayXmuxCMaxReuseTimes => 'حد استفادهٔ مجدد از اتصال';

  @override
  String get settingsXrayXmuxHMaxRequestTimes => 'بیشینهٔ درخواست در هر جریان';

  @override
  String get settingsXrayXmuxHMaxReusableSecs => 'مدت استفادهٔ مجدد جریان (ثانیه)';

  @override
  String get settingsXrayXmuxHKeepAlivePeriod => 'دورهٔ keep-alive (ثانیه)';

  @override
  String get settingsTunSection => 'حالت TUN';

  @override
  String get settingsTunSectionNote => 'گزینه‌های رابط TUN در sing-box (نسخهٔ دسکتاپ). از اتصال بعدی اعمال می‌شود.';

  @override
  String get settingsTunStackTitle => 'پشتهٔ شبکه';

  @override
  String get settingsTunStackSystemHint => 'پشتهٔ TCP/IP هسته — سریع‌ترین، اما در ویندوز TCP را با یک شنونده روی نشانی TUN پایان می‌دهد و به قاعدهٔ Windows Firewall نیاز دارد؛ اگر آن قاعده ثبت نشود، تونل بالا می‌آید ولی هیچ ترافیکی رد نمی‌شود';

  @override
  String get settingsTunStackGvisorHint => 'پشتهٔ فضای کاربر — پیش‌فرض. کاملاً داخل هسته اجرا می‌شود، پس نه شنونده می‌خواهد و نه قاعدهٔ فایروال؛ کمی کندتر. به هسته‌ای با gVisor نیاز دارد (هسته‌های نسخهٔ 0.7.1 و قدیمی‌تر با کد 1 بسته می‌شوند)';

  @override
  String get settingsTunStackMixedHint => 'gVisor برای TCP و system برای UDP. به هسته‌ای با gVisor نیاز دارد (هسته‌های نسخهٔ 0.7.1 و قدیمی‌تر با کد 1 بسته می‌شوند)';

  @override
  String get settingsTunMtu => 'MTU';

  @override
  String get settingsTunMtuHint => '576 تا 65535، پیش‌فرض 9000';

  @override
  String get settingsTunUdpTimeout => 'مهلت UDP (ثانیه)';

  @override
  String get settingsTunUdpTimeoutHint => 'طول عمر NAT برای نشست‌های بیکار UDP، پیش‌فرض 300';

  @override
  String get settingsTunStrictRouteTitle => 'مسیر سخت‌گیرانه';

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
  String get settingsTunEin => 'NAT مستقل از مقصد';

  @override
  String get settingsTunEinHint => 'NAT از نوع full-cone برای UDP — به بازی و P2P کمک می‌کند. فقط با پشتهٔ gVisor یا mixed';

  @override
  String get settingsTunAutoRoute => 'مسیر خودکار';

  @override
  String get settingsTunAutoRouteHint => 'مسیرهای سیستم را خودکار به تونل اضافه می‌کند. فقط اگر مسیرها را خودتان مدیریت می‌کنید خاموش کنید — بدون آن هیچ ترافیکی وارد TUN نمی‌شود';

  @override
  String get settingsTunIpv6 => 'IPv6 را داخل تونل نگه دار';

  @override
  String get settingsTunIpv6Hint => 'رابط TUN که تنها نشانی IPv4 دارد هیچ مسیر IPv6 نمی‌گیرد، پس روی دستگاه دوپشته‌ای تمام ترافیک IPv6 از کنار تونل می‌رود — از کنار قاعده‌های مسیریابی و از کنار پراکسی. با روشن بودن این گزینه رابط نشانی IPv6 هم می‌گیرد و خروج IPv6 بسته می‌شود، پس برنامه‌ها فوراً به IPv4 که از پیش در تونل است بازمی‌گردند. نشانی تنها زمانی افزوده می‌شود که دستگاه واقعاً IPv6 جهانی داشته باشد. فقط هستهٔ xray/keqrnel';

  @override
  String get settingsMihomoSection => 'هسته mihomo';

  @override
  String get settingsMihomoFakeIp => 'Fake IP';

  @override
  String get settingsMihomoFakeIpHint => 'هسته به‌جای نشانی واقعی، نشانی جایگزین به DNS پاسخ می‌دهد: تفکیک نام آنی می‌شود و قاعده‌های دامنه دیگر به sniffing وابسته نیستند. در عوض قاعده‌های IP پیش از تطبیق باید دوباره تفکیک شوند، پس همان فهرست‌های مسیریابی کمی متفاوت از Xray رفتار می‌کنند. فقط جایی اثر دارد که تونل در اختیار خود mihomo است — حالت TUN و اندروید.';

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
  String get settingsPingMethodUrl => 'HTTP از داخل پروکسی';

  @override
  String get settingsPingMethodUrlHint => 'تأخیر درخواست GET را از داخل سرور اندازه می‌گیرد';

  @override
  String get settingsPingKeepAliveTitle => 'روش اندازه‌گیری';

  @override
  String get settingsPingKeepAlive => 'Keep-alive';

  @override
  String get settingsPingKeepAliveHint => 'دو درخواست را روی یک اتصال می‌فرستد و بهترین را برمی‌دارد: نتیجه زمان پاسخ سرور بدون هزینهٔ برقراری اتصال است. با خاموش کردن آن کل درخواست همراه با دست‌دادن اندازه‌گیری می‌شود — عددها بزرگ‌تر و نزدیک‌تر به چیزی که مرورگر منتظرش می‌ماند.';

  @override
  String get settingsPingMethodSpeed => 'تست سرعت';

  @override
  String get settingsPingMethodSpeedHint => 'حجم مشخصی را از داخل سرور دانلود می‌کند و سرعت را برحسب Mbps نشان می‌دهد (بدون VPN هم کار می‌کند)';

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
  String get settingsPingCustomUrlHint => 'آدرس https:// یا http:// برای درخواست GET';

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
  String get subscriptionIdentityTitle => 'شناسه دستگاه';

  @override
  String get subscriptionIdentityHint => 'آنچه پنل می‌بیند: HWID، User-Agent و هدرهای دستگاه. فقط برای همین اشتراک اعمال می‌شود.';

  @override
  String get subscriptionIdentityEnable => 'استفاده از شناسه دلخواه';

  @override
  String get subscriptionIdentityAppDefault => 'پیش‌فرض برنامه';

  @override
  String get subscriptionIdentityAppDefaultHint => 'ارسال مقدار واقعی این دستگاه';

  @override
  String get subscriptionIdentityHwid => 'HWID';

  @override
  String get subscriptionIdentityHwidOff => 'در تنظیمات پیشرفته «اشتراک‌گذاری HWID دستگاه» خاموش است، بنابراین هیچ HWID‌ای ارسال نمی‌شود؛ حتی دلخواه.';

  @override
  String get subscriptionIdentityUserAgent => 'User-Agent';

  @override
  String get subscriptionIdentityDeviceOs => 'سیستم‌عامل دستگاه';

  @override
  String get subscriptionIdentityDeviceModel => 'مدل دستگاه';

  @override
  String get subscriptionIdentityOsVersion => 'نسخه سیستم‌عامل';

  @override
  String get subscriptionIdentitySectionUsed => 'در حال استفاده';

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
  String get serversImportFile => 'وارد کردن از فایل';

  @override
  String get serversAddServerTitle => 'افزودن سرور';

  @override
  String get serversPasteVlessHint => 'لینک vless://، vmess://، trojan://، ss://، hysteria2:// یا hy2:// را بچسبانید (هر کدام در یک خط)، یا یک کانفیگ کامل: JSON برای Xray، YAML برای Clash، ‎.conf برای AmneziaWG';

  @override
  String get serversPasteHint => '…//:vless یا …?hy2://host:port=auth';

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
  String get serverEditorJsonValid => 'پیکربندی معتبر Xray';

  @override
  String get serverEditorJsonFormat => 'قالب‌بندی';

  @override
  String get subscriptionsCardMenu => 'بیشتر';

  @override
  String get subscriptionsAutoUpdateOff => 'به‌روزرسانی خودکار نشود';

  @override
  String get subscriptionsProviderPage => 'صفحه اشتراک';

  @override
  String get subscriptionsSupport => 'پشتیبانی';

  @override
  String get subscriptionsLinkOpenFailed => 'باز کردن پیوند ممکن نشد';

  @override
  String get settingsAdvancedGroupTraffic => 'ترافیک و هسته';

  @override
  String get settingsAdvancedGroupSystem => 'سیستم';

  @override
  String get settingsAdvancedGroupDiagnostics => 'تشخیص';

  @override
  String get settingsBackupRestore => 'پشتیبان‌گیری و بازیابی';

  @override
  String get settingsBackupRestoreSubtitle => 'خروجی و ورودی گرفتن از پروکسی هر برنامه، اشتراک‌ها، سرورها و تنظیمات';

  @override
  String get settingsSelectAtLeastOne => 'برای خروجی گرفتن دست‌کم یک بخش را انتخاب کنید';

  @override
  String get settingsBackupSaved => 'پشتیبان با موفقیت ذخیره شد';

  @override
  String get settingsSelectLocation => 'محل ذخیرهٔ پشتیبان را انتخاب کنید';

  @override
  String get settingsExportFile => 'گرفتن خروجی';

  @override
  String get settingsImportFile => 'وارد کردن از فایل';

  @override
  String get settingsImportBackup => 'وارد کردن پشتیبان';

  @override
  String get settingsChooseWhatToImport => 'انتخاب کنید چه چیزی وارد شود (بخش‌های انتخاب‌شده جای داده‌های فعلی شما را می‌گیرند).';

  @override
  String get settingsSplitTunnelingApps => 'برنامه‌های پروکسی هر برنامه';

  @override
  String get settingsSubscriptions => 'اشتراک‌ها';

  @override
  String get settingsServersActive => 'سرورها (و سرور فعال)';

  @override
  String get settingsAppSettings => 'تنظیمات برنامه';

  @override
  String get settingsAppSettingsHint => 'مسیریابی، DNS، ظاهر، پینگ و زبان. پورت‌ها، اشتراک‌گذاری در شبکه محلی و TUN همان‌گونه که روی این دستگاه هستند باقی می‌مانند.';

  @override
  String get settingsImport => 'وارد کردن';

  @override
  String get settingsExport => 'خروجی';

  @override
  String get settingsCreateFileToSave => 'فایلی بسازید که بتوانید ذخیره کنید و روی دستگاه دیگری وارد کنید.';

  @override
  String get settingsPickExportedFile => 'فایلی که قبلاً خروجی گرفته‌اید انتخاب کنید تا بخش‌های انتخاب‌شده بازیابی شوند.';

  @override
  String get settingsWorking => 'در حال انجام...';

  @override
  String settingsImportedSections(int count) {
    return '$count بخش وارد شد';
  }

  @override
  String get settingsDebugMode => 'حالت اشکال‌زدایی';

  @override
  String get settingsDebugModeOn => 'اطلاعات تشخیصی گسترده فعال است';

  @override
  String get settingsDebugModeOff => 'خاموش';

  @override
  String get settingsOpenXrayLogs => 'گزارش‌های هسته';

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
  String get splitAddAppHint => 'مسیر فایل exe. یا نام آن (مثلاً chrome.exe)';

  @override
  String get splitAddAppPickFile => 'انتخاب فایل…';

  @override
  String get splitAddAppInvalid => 'نام یا مسیر معتبر exe. وارد کنید';

  @override
  String splitAddAppAdded(Object name) {
    return 'اضافه شد: $name';
  }

  @override
  String get splitProxyModeWarning => 'در حالت پروکسی، پروکسی هر برنامه اعمال نمی‌شود — همهٔ ترافیک از پروکسی سیستم رد می‌شود. برای اینکه قوانین هر برنامه کار کنند، حالت اتصال را از پنل کناری روی TUN بگذارید.';

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
  String get settingsDesktopSubtitle => 'سینی سیستم، اجرای خودکار، اتصال خودکار';

  @override
  String get settingsMinimizeToTray => 'هنگام بستن، به سینی سیستم برود';

  @override
  String get settingsMinimizeToTrayHint => 'اگر خاموش باشد، بستن پنجره برنامه را می‌بندد';

  @override
  String get settingsLaunchAtStartup => 'اجرا همراه ویندوز';

  @override
  String get settingsLaunchAtStartupHint => 'برنامه هنگام ورود شما به سیستم اجرا شود';

  @override
  String get settingsAutoConnectOnAutostart => 'اتصال هنگام اجرای خودکار';

  @override
  String get settingsAutoConnectOnAutostartHint => 'به آخرین سرور انتخاب‌شده با حالت انتخابی در پنل کناری وصل می‌شود. اگر TUN به دسترسی مدیر نیاز داشته باشد و در دسترس نباشد، از حالت پروکسی استفاده می‌شود';

  @override
  String get settingsAutoConnectRequiresAutostart => 'اول «اجرا همراه ویندوز» را روشن کنید';

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
  String get trayStatusDisconnected => 'قطع';

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
  String get serversSortName => 'نام (الفبا)';

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
  String get serversScrollToEnd => 'به انتهای فهرست';

  @override
  String get serversScrollToTop => 'به ابتدای فهرست';

  @override
  String get serversJumpToActive => 'نمایش در فهرست';

  @override
  String get serversManualGroup => 'سرورهای دستی';

  @override
  String get serversEmptyGroupHint => 'این اشتراک سروری ندارد';

  @override
  String get statsInLabel => 'ورودی';

  @override
  String get statsTimeLabel => 'زمان';

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
  String get hotkeyActionToggleConnectionDesc => 'تونل سرور فعال را روشن یا خاموش می‌کند';

  @override
  String get hotkeyActionToggleTun => 'تغییر حالت TUN';

  @override
  String get hotkeyActionToggleTunDesc => 'بین پروکسی و TUN جابه‌جا می‌شود و در صورت نیاز دوباره وصل می‌کند';

  @override
  String get hotkeyActionBestPing => 'سرور با بهترین پینگ';

  @override
  String get hotkeyActionBestPingDesc => 'به سروری با کمترین پینگ سوییچ می‌کند';

  @override
  String get hotkeyActionToggleWindow => 'نمایش / پنهان کردن پنجره';

  @override
  String get hotkeyActionToggleWindowDesc => 'پنجره را از سینی سیستم برمی‌گرداند یا پنهان می‌کند';

  @override
  String get hotkeyNotSet => 'تعیین نشده';

  @override
  String get hotkeyPressKeys => 'کلیدها را بزنید…';

  @override
  String get hotkeyRecordingHint => 'Esc — لغو، Backspace — پاک کردن';

  @override
  String get hotkeyNeedsModifier => 'از یک کلید ترکیبی (Ctrl/Alt/Shift/Win) یا کلیدهای F استفاده کنید';

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
  String get errorVpnPermissionMessage => 'دسترسی VPN داده نشد.';

  @override
  String get errorVpnPermissionAction => 'در پنجرهٔ سیستم دسترسی VPN را بدهید و دوباره تلاش کنید.';

  @override
  String get errorHwidBindMessage => 'فروشنده برای این دستگاه اتصال HWID را لازم می‌داند.';

  @override
  String get errorHwidBindAction => 'این دستگاه را در پنل فروشنده ثبت کنید و بعد اشتراک را به‌روزرسانی کنید.';

  @override
  String get errorDeviceLimitMessage => 'فروشنده به دلیل محدودیت تعداد دستگاه، اشتراک را رد کرد.';

  @override
  String get errorDeviceLimitAction => 'در پنل فروشنده دستگاه‌های قدیمی را حذف کنید یا سقف دستگاه‌ها را بالا ببرید.';

  @override
  String get errorConfigInvalidMessage => 'کانفیگ اشتراک یا سرور نامعتبر است.';

  @override
  String get errorConfigInvalidAction => 'قالب آدرس یا کانفیگ را بررسی کنید و یک لینک اشتراک درست وارد کنید.';

  @override
  String get errorAuthDeniedMessage => 'فروشنده دسترسی به اشتراک را رد کرد.';

  @override
  String get errorAuthDeniedAction => 'توکن و مشخصات ورود را بررسی کنید و مطمئن شوید اشتراک منقضی نشده باشد.';

  @override
  String get errorSubUrlInvalidMessage => 'لینک اشتراک وجود ندارد یا منقضی شده است.';

  @override
  String get errorSubUrlInvalidAction => 'از فروشنده لینک تازه بگیرید و در برنامه به‌روزش کنید.';

  @override
  String get errorSubInsecureHttpMessage => 'لینک اشتراک از http ساده استفاده می‌کند، به‌روزرسانی مسدود است.';

  @override
  String get errorSubInsecureHttpAction => 'لینک را با نسخهٔ //:https آن جایگزین کنید.';

  @override
  String get subInsecureHttpWarning => 'لینک http — به‌روزرسانی مسدود است';

  @override
  String get subSwitchToHttps => 'تغییر به https';

  @override
  String get errorNetworkMessage => 'الان نمی‌توان به سرور رسید.';

  @override
  String get errorNetworkAction => 'اینترنت، DNS و در دسترس بودن سرور را بررسی کنید و دوباره تلاش کنید.';

  @override
  String get errorUnknownAction => 'دوباره تلاش کنید. اگر تکرار شد، سرور و تنظیمات برنامه را بررسی کنید.';

  @override
  String get errorTunAdminTitle => 'نیاز به مجوز';

  @override
  String get errorVpnPermissionTitle => 'نیاز به مجوز';

  @override
  String get errorHwidBindTitle => 'نیاز به اتصال دستگاه';

  @override
  String get errorDeviceLimitTitle => 'محدودیت دستگاه‌ها';

  @override
  String get errorProviderNoHostsTitle => 'نیاز به پیکربندی ارائه‌دهنده';

  @override
  String get errorConfigInvalidTitle => 'خطای پیکربندی';

  @override
  String get errorAuthDeniedTitle => 'احراز هویت ناموفق';

  @override
  String get errorSubUrlInvalidTitle => 'نشانی اشتراک نامعتبر';

  @override
  String get errorSubInsecureHttpTitle => 'نشانی اشتراک ناامن';

  @override
  String get errorNetworkTitle => 'خطای شبکه';

  @override
  String get errorUnknownTitle => 'عملیات ناموفق';

  @override
  String get serversPin => 'سنجاق کردن سرور';

  @override
  String get serversUnpin => 'برداشتن سنجاق';

  @override
  String get serversPinDesc => 'سرورهای سنجاق‌شده بالای فهرست می‌مانند';

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
  String get serversEditConfigDesc => 'SNI، اثر انگشت، انتقال و تنظیمات دیگر';

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
  String get appearanceAmoledSubtitle => 'پس‌زمینهٔ کاملاً مشکی در پوستهٔ تیره — روی نمایشگر OLED باتری کمتری می‌برد';

  @override
  String get appearanceAmoledNeedsDark => 'با روشن بودن پوستهٔ تیره در دسترس است';

  @override
  String get appearanceHaptics => 'بازخورد لمسی';

  @override
  String get appearanceHapticsSubtitle => 'لرزش هنگام اتصال و زدن روی تب‌ها و سرورها';

  @override
  String get appearanceShowTraffic => 'نمایش ترافیک';

  @override
  String get appearanceShowTrafficSubtitle => 'نشان دادن سرعت و مصرف داده زیر دکمهٔ اتصال';

  @override
  String get appearanceShowTime => 'نمایش زمان اتصال';

  @override
  String get appearanceShowTimeSubtitle => 'نشان دادن مدت نشست زیر دکمهٔ اتصال';

  @override
  String get appearanceFontTitle => 'قلم';

  @override
  String get appearanceFontSystem => 'سیستم';

  @override
  String get settingsResetConfirmTitle => 'تنظیمات بازنشانی شود؟';

  @override
  String get settingsResetConfirmAction => 'بازنشانی';

  @override
  String get settingsResetRoutingConfirm => 'این کار قوانین مسیریابی پیش‌فرض را برمی‌گرداند و فهرست‌های مستقیم، پروکسی و مسدود شما را پاک می‌کند. برگشت‌پذیر نیست.';

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
  String get settingsPermTunPasswordlessSubtitle => 'اجرای حالت TUN بدون وارد کردن هر بارهٔ رمز polkit';

  @override
  String get settingsPermTunDisabled => 'TUN بدون رمز غیرفعال است';

  @override
  String get appearanceNotifSectionTitle => 'اعلان';

  @override
  String get appearanceNotifSpeedTitle => 'سرعت اتصال در اعلان';

  @override
  String get appearanceNotifSpeedSubtitle => 'نمایش سرعت ↓/↑ در اعلان وضعیت VPN';

  @override
  String get appearanceNotifUptimeTitle => 'زمان اتصال در اعلان';

  @override
  String get appearanceNotifUptimeSubtitle => 'نمایش مدت نشست در اعلان وضعیت VPN';

  @override
  String get appearanceNotifSubUpdatesTitle => 'اعلان به‌روزرسانی اشتراک';

  @override
  String get appearanceNotifSubUpdatesSubtitle => 'وقتی اشتراک‌ها در پس‌زمینه به‌روز می‌شوند خبر بده';

  @override
  String get tunRememberTitle => 'اجازه به خاطر سپرده شود؟';

  @override
  String get tunRememberMessage => 'حالت TUN به دسترسی root نیاز دارد و هر بار رمز شما را می‌پرسد. یک قانون polkit نصب شود تا از این به بعد بدون رمز اجرا شود؟ برای نصب آن یک بار رمزتان پرسیده می‌شود.';

  @override
  String get tunRememberWarning => 'بعد از این، هر برنامه‌ای که با کاربر شما اجرا شود می‌تواند هستهٔ VPN را بدون رمز با دسترسی root اجرا کند. هر وقت خواستید می‌توانید از «پیشرفته ← دسترسی‌ها» برش گردانید.';

  @override
  String get tunRememberEnable => 'فعال کن';

  @override
  String get tunRememberNotNow => 'الان نه';

  @override
  String get tunRememberInstalled => 'TUN بدون رمز فعال شد';

  @override
  String get tunRememberFailed => 'تغییر مجوز TUN ممکن نشد';

  @override
  String get settingsRoutingPresetTelegramGeoTitle => 'تلگرام (GeoIP+GeoSite) — پروکسی';

  @override
  String get settingsRoutingPresetTelegramGeoDesc => 'تلگرام هم بر اساس دامنه و هم بر اساس بازه‌های آی‌پی (MTProto با آی‌پی خام کار می‌کند)';

  @override
  String get settingsRoutingPresetRefilterTitle => 'مسدودشده‌ها در روسیه (Re-filter) — پروکسی';

  @override
  String get settingsRoutingPresetRefilterDesc => 'دامنه‌ها و آی‌پی‌های مسدودشده در روسیه از VPN رد می‌شوند، بقیه مستقیم می‌مانند';

  @override
  String get settingsRoutingGeoUnknownTitle => 'در پایگاه دادهٔ جغرافیایی نیست — نادیده گرفته می‌شود';

  @override
  String get settingsRoutingGeoUnknownHint => 'هسته با یک کد جغرافیایی ناشناس کل کانفیگ را رد می‌کند، برای همین این موارد پیش از اتصال حذف می‌شوند. با دکمهٔ کرهٔ زمین در بالا یک کد موجود انتخاب کنید.';

  @override
  String get settingsRoutingGeoPickerTooltip => 'درج کد جغرافیایی';

  @override
  String get settingsRoutingGeoPickerTitle => 'کدهای جغرافیایی موجود در پایگاه دادهٔ همراه';

  @override
  String get settingsRoutingGeoPickerSearchHint => 'جستجو، مثلاً telegram';

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
  String get connectionsRuleHint => 'هسته فقط در سطح گزارش Info می‌نویسد کدام قانون گرفته است.';

  @override
  String get connectionsRuleHintAction => 'روی Info بگذار';

  @override
  String get connectionsRuleHintApplied => 'سطح گزارش هسته روی Info رفت — برای اعمال دوباره وصل شوید';

  @override
  String get connectionsRuleDefault => 'بدون قانون (عملکرد پیش‌فرض)';

  @override
  String get connectionsRuleViaCore => 'داخل هسته تصمیم گرفته شد (به گزارش Info نیاز دارد)';

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
  String get connectionsAppNamesHint => 'نام برنامه‌ها بعد از اتصال دوباره ظاهر می‌شود: گزارش دقیق تونل همراه با حالت اشکال‌زدایی شروع می‌شود.';

  @override
  String get connectionsSplitTunnelNote => 'برنامه‌هایی که بیرون تونل مانده‌اند اینجا نمی‌آیند: اندروید آن‌ها را از کنار تونل رد می‌کند و ترافیکشان اصلاً به هسته نمی‌رسد.';

  @override
  String subscriptionsExpiredOn(String date) {
    return 'اشتراک در $date منقضی شد';
  }

  @override
  String get subscriptionsExpiredHint => 'فروشنده دیگر فهرست سرورها را به‌روز نمی‌کند. برای ادامهٔ کار اشتراک را تمدید کنید.';

  @override
  String get subscriptionsExpiredNotifTitle => 'اشتراک منقضی شد';

  @override
  String subscriptionsExpiredNotifBody(String name, String date) {
    return '«$name» در $date منقضی شد. فروشنده دیگر فهرست سرورها را به‌روز نمی‌کند — برای اینکه سرورها کار کنند تمدیدش کنید.';
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
  String get settingsInternalsTitle => 'درباره';

  @override
  String get settingsInternalsSubtitle => 'نسخه، هسته‌ها، پایگاه‌های جغرافیایی و نشست جاری';

  @override
  String get settingsCoreXraySubtitle => 'هسته پیش‌فرض. همه انواع سرور را پشتیبانی می‌کند، از جمله زنجیره‌ها و پیکربندی‌های آماده JSON.';

  @override
  String get settingsCoreMihomoSubtitle => 'هسته سازگار با Clash. زنجیره‌ها و پیکربندی‌های آماده xray روی Xray می‌مانند.';

  @override
  String get settingsCoreHint => 'از اتصال بعدی اعمال می‌شود — نشست فعلی راه‌اندازی مجدد نمی‌شود.';

  @override
  String get settingsProxyAuthTitle => 'رمز عبور پروکسی محلی';

  @override
  String get settingsProxyAuthSubtitle => 'برای مواردی که جایی برای وارد کردن آن نیست، مانند تنظیمات پروکسی Wi-Fi، خاموش کنید';

  @override
  String get settingsProxyAuthUser => 'نام کاربری';

  @override
  String get settingsProxyAuthPass => 'رمز عبور';

  @override
  String get settingsTunnelModeSection => 'حالت اتصال';

  @override
  String get settingsTunnelModeVpn => 'VPN';

  @override
  String get settingsTunnelModeVpnSubtitle => 'همه ترافیک دستگاه از تونل عبور می‌کند';

  @override
  String get settingsTunnelModeProxy => 'پروکسی';

  @override
  String get settingsTunnelModeProxySubtitle => 'فقط پروکسی محلی — VPN سیستم روشن نمی‌شود و چیزی خودبه‌خود گرفته نمی‌شود';

  @override
  String get settingsTunnelModeHint => 'در حالت پروکسی، برنامه SOCKS و HTTP را روی 127.0.0.1 باز می‌کند و خودش چیزی را نمی‌گیرد: برنامه یا تنظیمات پروکسی Wi-Fi را به آن اشاره دهید. پورت‌ها در «تنظیمات ← پورت‌های محلی» هستند. مسیریابی هر برنامه و رهگیری DNS فقط در حالت VPN کار می‌کند؛ سرورهای AmneziaWG همیشه به شکل VPN وصل می‌شوند.';

  @override
  String get settingsCoreAuto => 'خودکار';

  @override
  String get settingsCoreAutoSubtitle => 'هسته را قالبِ سرور تعیین می‌کند: لینک‌ها روی Xray و پیکربندی‌های آماده روی همان هسته‌ای که برایش نوشته شده‌اند اجرا می‌شوند.';

  @override
  String get settingsCoreSkipClash => 'سرور فعال یک پیکربندی آمادهٔ Clash است — صرف‌نظر از هستهٔ انتخاب‌شده تنها mihomo آن را اجرا می‌کند.';

  @override
  String get settingsCoreSkipCustom => 'سرور فعال یک پیکربندی آمادهٔ JSON برای Xray است (مسیریابی و DNS آن از سمت ارائه‌دهنده می‌آید)، بنابراین صرف‌نظر از هستهٔ انتخاب‌شده با libxray اجرا می‌شود. برای استفاده از mihomo به اشتراکی نیاز است که لینک‌های ساده vless:// / vmess:// بدهد — هویت کلاینت را در تنظیمات اشتراک عوض کنید.';

  @override
  String get settingsCoreSkipChain => 'سرور فعال یک زنجیره است: گره‌های آن با dialerProxy در Xray به هم وصل شده‌اند، پس صرف‌نظر از هستهٔ انتخاب‌شده با libxray اجرا می‌شود.';

  @override
  String get settingsCoreSkipAwg => 'سرور فعال یک پروفایل AmneziaWG است — صرف‌نظر از هستهٔ انتخاب‌شده با هستهٔ خودش، wg-go، اجرا می‌شود.';

  @override
  String get settingsCoreSkipPlatform => 'هستهٔ mihomo برای این پلتفرم ارائه نمی‌شود — اتصال از هستهٔ Xray انجام می‌شود.';

  @override
  String get settingsInternalsCores => 'هسته‌ها';

  @override
  String get settingsInternalsGeo => 'پایگاه‌های جغرافیایی';

  @override
  String get settingsInternalsSession => 'نشست جاری';

  @override
  String get settingsInternalsBuild => 'برنامه و دستگاه';

  @override
  String get settingsInternalsCopyAll => 'کپی گزارش';

  @override
  String get settingsInternalsCopied => 'گزارش کپی شد';

  @override
  String get settingsInternalsNoCores => 'برای این سکو هسته‌ای ارائه نشده است';

  @override
  String get settingsInternalsCoreMissing => 'یافت نشد';

  @override
  String get settingsInternalsVersionFromEngines => 'ساخته‌شده از کد منبع';

  @override
  String get settingsInternalsRoleCore => 'موتور پراکسی و TUN';

  @override
  String get settingsInternalsRoleProxy => 'موتور پراکسی';

  @override
  String get settingsInternalsRoleTun => 'دستگاه TUN';

  @override
  String get settingsInternalsRoleAwg => 'AmneziaWG';

  @override
  String settingsInternalsGeoCodes(int count) {
    return 'کدها: $count';
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
  String get settingsInternalsPorts => 'درگاه‌های محلی';

  @override
  String get settingsInternalsClashPort => 'درگاه Clash API';

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
  String get settingsInternalsBuildMode => 'ساخت';

  @override
  String get settingsInternalsUnavailable => '—';

  @override
  String get appearanceUiScaleTitle => 'اندازه رابط کاربری';

  @override
  String get appearanceUiScaleSubtitle => 'روی اندازه متن سیستم اعمال می‌شود، پس ۱۰۰٪ یعنی «مانند سیستم». متن و ارتفاع سطرهای فهرست تغییر می‌کند؛ نمادها و فاصله‌ها ثابت می‌مانند.';

  @override
  String get appearanceIconShapeTitle => 'شکل نمادها';

  @override
  String get appearanceIconShapeCircle => 'دایره';

  @override
  String get subscriptionCardThemeTitle => 'پس‌زمینه';

  @override
  String get subscriptionCardThemeNone => 'بدون';

  @override
  String get subscriptionCardThemeInServers => 'نمایش در فهرست سرورها';

  @override
  String get subscriptionCardThemeInServersHint => 'تصویر سربرگ گروه را هم پر می‌کند. رنگ‌های گرفته‌شده از آن در هر حالت باقی می‌مانند.';

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
  String get subscriptionCardVeilHint => 'متن روی سمت چپ تصویر قرار می‌گیرد. بدون تیرگی، روی عکس روشن گم می‌شود.';

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
  String get subscriptionCardElementAnnounce => 'اطلاعیه ارائه‌دهنده';

  @override
  String get subscriptionCardElementUsage => 'ترافیک';

  @override
  String get subscriptionCardElementMeta => 'انقضا و به‌روزرسانی';

  @override
  String get subscriptionCardElementActions => 'دکمه‌ها';

  @override
  String get subscriptionCardContentHint => 'هشدارها همیشه نمایش داده می‌شوند: اشتراک منقضی، پیوند ناامن، به‌روزرسانی ناموفق.';

  @override
  String get appearanceIconShapeSquare => 'مربع';

  @override
  String get appearanceIconShapeArch => 'قوس';

  @override
  String get appearanceSectionServers => 'فهرست سرورها و صفحهٔ اصلی';

  @override
  String get appearanceSectionFeel => 'پوسته و بازخورد';

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
  String get cardImageRejectAspect => 'این تصویر برای کارت بلند است. تصویری عریض انتخاب کن — تقریباً از ۳:۲ تا ۵:۱.';

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
