import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fa.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('fa'),
    Locale('ru'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'KEQDIS'**
  String get appTitle;

  /// No description provided for @vpnConnectedTo.
  ///
  /// In en, this message translates to:
  /// **'Connected to: {serverName}'**
  String vpnConnectedTo(Object serverName);

  /// No description provided for @vpnConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get vpnConnecting;

  /// No description provided for @vpnDisconnecting.
  ///
  /// In en, this message translates to:
  /// **'Disconnecting...'**
  String get vpnDisconnecting;

  /// No description provided for @vpnTapToConnect.
  ///
  /// In en, this message translates to:
  /// **'Tap to connect to {serverName}'**
  String vpnTapToConnect(Object serverName);

  /// No description provided for @vpnSelectServer.
  ///
  /// In en, this message translates to:
  /// **'Select a server below'**
  String get vpnSelectServer;

  /// No description provided for @vpnSelectServerFirst.
  ///
  /// In en, this message translates to:
  /// **'Select a server first'**
  String get vpnSelectServerFirst;

  /// No description provided for @updateTitle.
  ///
  /// In en, this message translates to:
  /// **'Update Available'**
  String get updateTitle;

  /// No description provided for @updateWhatsNew.
  ///
  /// In en, this message translates to:
  /// **'What\'s new:'**
  String get updateWhatsNew;

  /// No description provided for @updateActionLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateActionLater;

  /// No description provided for @updateActionNow.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateActionNow;

  /// No description provided for @updateApplying.
  ///
  /// In en, this message translates to:
  /// **'Applying update...'**
  String get updateApplying;

  /// No description provided for @errorSubscriptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription error'**
  String get errorSubscriptionTitle;

  /// No description provided for @errorConnectionPermission.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: permission'**
  String get errorConnectionPermission;

  /// No description provided for @errorConnectionNetwork.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: network'**
  String get errorConnectionNetwork;

  /// No description provided for @errorConnectionConfig.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: config'**
  String get errorConnectionConfig;

  /// No description provided for @errorConnectionAuth.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: auth'**
  String get errorConnectionAuth;

  /// No description provided for @errorConnectionGeneric.
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get errorConnectionGeneric;

  /// No description provided for @errorProviderConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Provider configuration required'**
  String get errorProviderConfigTitle;

  /// No description provided for @errorProviderNoHostsMessage.
  ///
  /// In en, this message translates to:
  /// **'Provider has no hosts assigned to this subscription.'**
  String get errorProviderNoHostsMessage;

  /// No description provided for @errorProviderNoHostsAction.
  ///
  /// In en, this message translates to:
  /// **'Open provider panel, add or assign hosts, then refresh subscription.'**
  String get errorProviderNoHostsAction;

  /// No description provided for @errorActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Action: {action}'**
  String errorActionLabel(Object action);

  /// No description provided for @splitTunnelingTitle.
  ///
  /// In en, this message translates to:
  /// **'Split Tunneling'**
  String get splitTunnelingTitle;

  /// No description provided for @splitModeAllApps.
  ///
  /// In en, this message translates to:
  /// **'All apps'**
  String get splitModeAllApps;

  /// No description provided for @splitModeSelectedOnly.
  ///
  /// In en, this message translates to:
  /// **'Selected only'**
  String get splitModeSelectedOnly;

  /// No description provided for @splitModeAllExceptSelected.
  ///
  /// In en, this message translates to:
  /// **'All except selected'**
  String get splitModeAllExceptSelected;

  /// No description provided for @splitSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search apps...'**
  String get splitSearchHint;

  /// No description provided for @splitNoAppsFound.
  ///
  /// In en, this message translates to:
  /// **'No apps found'**
  String get splitNoAppsFound;

  /// No description provided for @splitFailedLoadApps.
  ///
  /// In en, this message translates to:
  /// **'Failed to load apps: {error}'**
  String splitFailedLoadApps(Object error);

  /// No description provided for @splitSelectedAppsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} app(s) selected'**
  String splitSelectedAppsCount(int count);

  /// No description provided for @splitHideSystemApps.
  ///
  /// In en, this message translates to:
  /// **'Hide system apps'**
  String get splitHideSystemApps;

  /// No description provided for @splitShowSystemApps.
  ///
  /// In en, this message translates to:
  /// **'Show system apps'**
  String get splitShowSystemApps;

  /// No description provided for @splitAddRussianAppsBypass.
  ///
  /// In en, this message translates to:
  /// **'Add Russian apps to bypass'**
  String get splitAddRussianAppsBypass;

  /// No description provided for @splitClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get splitClear;

  /// No description provided for @splitNoRussianAppsFound.
  ///
  /// In en, this message translates to:
  /// **'No Russian apps found in the installed apps list'**
  String get splitNoRussianAppsFound;

  /// No description provided for @splitRussianAppsAlreadyAdded.
  ///
  /// In en, this message translates to:
  /// **'All Russian apps already in bypass list'**
  String get splitRussianAppsAlreadyAdded;

  /// No description provided for @splitAddedRussianApps.
  ///
  /// In en, this message translates to:
  /// **'Added {count} Russian app(s) to bypass list'**
  String splitAddedRussianApps(int count);

  /// No description provided for @navServers.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get navServers;

  /// No description provided for @navSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get navSubscriptions;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @serversEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No servers yet'**
  String get serversEmptyTitle;

  /// No description provided for @serversEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add a subscription in the Subscriptions tab'**
  String get serversEmptyHint;

  /// No description provided for @subscriptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get subscriptionsTitle;

  /// No description provided for @subscriptionsAddButton.
  ///
  /// In en, this message translates to:
  /// **'Add subscription'**
  String get subscriptionsAddButton;

  /// No description provided for @subscriptionsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No subscriptions'**
  String get subscriptionsEmptyTitle;

  /// No description provided for @subscriptionsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Tap + to add a subscription URL'**
  String get subscriptionsEmptyHint;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsThemeTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsThemeTitle;

  /// No description provided for @settingsSplitTitle.
  ///
  /// In en, this message translates to:
  /// **'Split Tunneling'**
  String get settingsSplitTitle;

  /// No description provided for @settingsRoutingTitle.
  ///
  /// In en, this message translates to:
  /// **'Routing Rules'**
  String get settingsRoutingTitle;

  /// No description provided for @settingsSplitConfigured.
  ///
  /// In en, this message translates to:
  /// **'{count} apps configured'**
  String settingsSplitConfigured(int count);

  /// No description provided for @settingsRoutingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Direct / proxy / block rules and presets'**
  String get settingsRoutingSubtitle;

  /// No description provided for @settingsResetRoutingTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset routing to defaults'**
  String get settingsResetRoutingTitle;

  /// No description provided for @settingsRoutingResetDone.
  ///
  /// In en, this message translates to:
  /// **'Routing rules reset'**
  String get settingsRoutingResetDone;

  /// No description provided for @settingsRoutingHeaderDesc.
  ///
  /// In en, this message translates to:
  /// **'Decide which sites go directly past the VPN, which are forced through it, and which are blocked. Use a preset for a quick start, then fine-tune each list below.'**
  String get settingsRoutingHeaderDesc;

  /// No description provided for @settingsRoutingPresetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick presets'**
  String get settingsRoutingPresetsTitle;

  /// No description provided for @settingsRoutingPresetsHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a curated list and add it to the matching list below. You can edit or remove entries afterwards.'**
  String get settingsRoutingPresetsHint;

  /// No description provided for @settingsRoutingPresetChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose a preset…'**
  String get settingsRoutingPresetChoose;

  /// No description provided for @settingsRoutingPresetAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get settingsRoutingPresetAdd;

  /// No description provided for @settingsRoutingPresetRuTitle.
  ///
  /// In en, this message translates to:
  /// **'Russian sites — Direct'**
  String get settingsRoutingPresetRuTitle;

  /// No description provided for @settingsRoutingPresetRuDesc.
  ///
  /// In en, this message translates to:
  /// **'All .ru / .рф domains and major RU services bypass the VPN (adds domains to Direct)'**
  String get settingsRoutingPresetRuDesc;

  /// No description provided for @settingsRoutingPresetRuGeoipTitle.
  ///
  /// In en, this message translates to:
  /// **'Russia IPs (GeoIP) — Direct'**
  String get settingsRoutingPresetRuGeoipTitle;

  /// No description provided for @settingsRoutingPresetRuGeoipDesc.
  ///
  /// In en, this message translates to:
  /// **'All Russian IP ranges bypass the VPN via GeoIP — works in Proxy mode'**
  String get settingsRoutingPresetRuGeoipDesc;

  /// No description provided for @settingsRoutingPresetRuGeositeTitle.
  ///
  /// In en, this message translates to:
  /// **'Russia sites (GeoSite) — Direct'**
  String get settingsRoutingPresetRuGeositeTitle;

  /// No description provided for @settingsRoutingPresetRuGeositeDesc.
  ///
  /// In en, this message translates to:
  /// **'Russian domains from the GeoSite database bypass the VPN'**
  String get settingsRoutingPresetRuGeositeDesc;

  /// No description provided for @settingsRoutingPresetBanksTitle.
  ///
  /// In en, this message translates to:
  /// **'Banks & gov — Direct'**
  String get settingsRoutingPresetBanksTitle;

  /// No description provided for @settingsRoutingPresetBanksDesc.
  ///
  /// In en, this message translates to:
  /// **'Banking, payments and state portals bypass the VPN'**
  String get settingsRoutingPresetBanksDesc;

  /// No description provided for @settingsRoutingPresetLanIpsTitle.
  ///
  /// In en, this message translates to:
  /// **'Local network — Direct'**
  String get settingsRoutingPresetLanIpsTitle;

  /// No description provided for @settingsRoutingPresetLanIpsDesc.
  ///
  /// In en, this message translates to:
  /// **'Private LAN IP ranges (192.168.x, 10.x, …) bypass the VPN'**
  String get settingsRoutingPresetLanIpsDesc;

  /// No description provided for @settingsRoutingPresetAdsTitle.
  ///
  /// In en, this message translates to:
  /// **'Ads & trackers — Block'**
  String get settingsRoutingPresetAdsTitle;

  /// No description provided for @settingsRoutingPresetAdsDesc.
  ///
  /// In en, this message translates to:
  /// **'Drop common ad / analytics hosts'**
  String get settingsRoutingPresetAdsDesc;

  /// No description provided for @settingsRoutingPresetAdsGeositeTitle.
  ///
  /// In en, this message translates to:
  /// **'Ads (GeoSite) — Block'**
  String get settingsRoutingPresetAdsGeositeTitle;

  /// No description provided for @settingsRoutingPresetAdsGeositeDesc.
  ///
  /// In en, this message translates to:
  /// **'Block a broad ad / tracker list from the GeoSite database'**
  String get settingsRoutingPresetAdsGeositeDesc;

  /// No description provided for @settingsRoutingPresetStreamingTitle.
  ///
  /// In en, this message translates to:
  /// **'Streaming — Proxy'**
  String get settingsRoutingPresetStreamingTitle;

  /// No description provided for @settingsRoutingPresetStreamingDesc.
  ///
  /// In en, this message translates to:
  /// **'Force YouTube, Netflix, Twitch through the VPN'**
  String get settingsRoutingPresetStreamingDesc;

  /// No description provided for @settingsRoutingPresetMessengersTitle.
  ///
  /// In en, this message translates to:
  /// **'Messengers — Proxy'**
  String get settingsRoutingPresetMessengersTitle;

  /// No description provided for @settingsRoutingPresetMessengersDesc.
  ///
  /// In en, this message translates to:
  /// **'Force Telegram, Discord, WhatsApp through the VPN'**
  String get settingsRoutingPresetMessengersDesc;

  /// No description provided for @settingsRoutingPresetApplied.
  ///
  /// In en, this message translates to:
  /// **'Added \"{name}\"'**
  String settingsRoutingPresetApplied(String name);

  /// No description provided for @settingsRoutingDirectTitle.
  ///
  /// In en, this message translates to:
  /// **'Direct (bypass VPN)'**
  String get settingsRoutingDirectTitle;

  /// No description provided for @settingsRoutingDirectDesc.
  ///
  /// In en, this message translates to:
  /// **'Domains and IPs here connect directly, without the VPN.'**
  String get settingsRoutingDirectDesc;

  /// No description provided for @settingsRoutingProxyTitle.
  ///
  /// In en, this message translates to:
  /// **'Proxy (force VPN)'**
  String get settingsRoutingProxyTitle;

  /// No description provided for @settingsRoutingProxyDesc.
  ///
  /// In en, this message translates to:
  /// **'Domains and IPs here always go through the VPN.'**
  String get settingsRoutingProxyDesc;

  /// No description provided for @settingsRoutingBlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get settingsRoutingBlockTitle;

  /// No description provided for @settingsRoutingBlockDesc.
  ///
  /// In en, this message translates to:
  /// **'Domains and IPs here are dropped and never connect.'**
  String get settingsRoutingBlockDesc;

  /// No description provided for @settingsRoutingSyntaxHint.
  ///
  /// In en, this message translates to:
  /// **'Each list accepts domains and IPs together, comma- or line-separated:\n• ru — every *.ru host (a bare word = domain suffix)\n• vk.com — that domain and its subdomains\n• .example.com — subdomains only\n• 10.0.0.0/8 or 1.2.3.4 — IP address or CIDR range\n• geoip:ru / geosite:refilter — GeoIP/Geosite codes from the bundled databases\nPrivate/LAN IPs and your server always stay direct automatically.'**
  String get settingsRoutingSyntaxHint;

  /// No description provided for @settingsRoutingValuesHint.
  ///
  /// In en, this message translates to:
  /// **'One per line, or comma separated'**
  String get settingsRoutingValuesHint;

  /// No description provided for @settingsRoutingFinalTitle.
  ///
  /// In en, this message translates to:
  /// **'Unmatched traffic'**
  String get settingsRoutingFinalTitle;

  /// No description provided for @settingsRoutingFinalDesc.
  ///
  /// In en, this message translates to:
  /// **'Default action for traffic outside the rules.'**
  String get settingsRoutingFinalDesc;

  /// No description provided for @settingsRoutingFinalProxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get settingsRoutingFinalProxy;

  /// No description provided for @settingsRoutingFinalDirect.
  ///
  /// In en, this message translates to:
  /// **'Bypass'**
  String get settingsRoutingFinalDirect;

  /// No description provided for @settingsRoutingFinalBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get settingsRoutingFinalBlock;

  /// No description provided for @settingsRoutingAdvancedTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom rules'**
  String get settingsRoutingAdvancedTitle;

  /// No description provided for @settingsRoutingAdvancedHint.
  ///
  /// In en, this message translates to:
  /// **'Individual rules with their own on/off switch. Applied on top of the lists above.'**
  String get settingsRoutingAdvancedHint;

  /// No description provided for @settingsRoutingAdvancedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No custom rules yet'**
  String get settingsRoutingAdvancedEmpty;

  /// No description provided for @settingsRoutingAdvancedAdd.
  ///
  /// In en, this message translates to:
  /// **'Add rule'**
  String get settingsRoutingAdvancedAdd;

  /// No description provided for @settingsRoutingRuleNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New rule'**
  String get settingsRoutingRuleNewTitle;

  /// No description provided for @settingsRoutingRuleEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit rule'**
  String get settingsRoutingRuleEditTitle;

  /// No description provided for @settingsRoutingRuleName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get settingsRoutingRuleName;

  /// No description provided for @settingsRoutingRuleNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Streaming'**
  String get settingsRoutingRuleNameHint;

  /// No description provided for @settingsRoutingRuleValues.
  ///
  /// In en, this message translates to:
  /// **'Values'**
  String get settingsRoutingRuleValues;

  /// No description provided for @settingsRoutingRuleValuesHint.
  ///
  /// In en, this message translates to:
  /// **'One per line or comma-separated'**
  String get settingsRoutingRuleValuesHint;

  /// No description provided for @settingsRoutingRuleMatchBy.
  ///
  /// In en, this message translates to:
  /// **'Match by'**
  String get settingsRoutingRuleMatchBy;

  /// No description provided for @settingsRoutingRuleTypeDomain.
  ///
  /// In en, this message translates to:
  /// **'Domain'**
  String get settingsRoutingRuleTypeDomain;

  /// No description provided for @settingsRoutingRuleTypeIp.
  ///
  /// In en, this message translates to:
  /// **'IP / CIDR'**
  String get settingsRoutingRuleTypeIp;

  /// No description provided for @settingsRoutingRuleTypeGeoip.
  ///
  /// In en, this message translates to:
  /// **'GeoIP'**
  String get settingsRoutingRuleTypeGeoip;

  /// No description provided for @settingsRoutingRuleTypeGeosite.
  ///
  /// In en, this message translates to:
  /// **'GeoSite'**
  String get settingsRoutingRuleTypeGeosite;

  /// No description provided for @settingsRoutingRuleAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get settingsRoutingRuleAction;

  /// No description provided for @settingsRoutingRuleSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsRoutingRuleSave;

  /// No description provided for @settingsRoutingRuleDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this rule?'**
  String get settingsRoutingRuleDeleteConfirm;

  /// No description provided for @routingCheatSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'How to write rules'**
  String get routingCheatSheetTitle;

  /// No description provided for @routingCheatSheetBody.
  ///
  /// In en, this message translates to:
  /// **'Rules are just a list: what goes where. Each line is a domain, an IP, or a geo tag, and next to it the action — straight out (bypass), through the VPN (proxy), or blocked.\n\n## Domains\nvk.com — the domain itself and all its subdomains\nru — anything ending in .ru (a bare word, no dot)\n.example.com — subdomains only, not the domain itself\nfull:example.com — exactly this host, no subdomains\nregexp:… — a regex, if you really need to get fancy\n\n## IP addresses\n1.2.3.4 — a single address\n10.0.0.0/8 — a whole range (CIDR)\n\n## GeoIP — by country\ngeoip:ru — every Russian IP. Swap ru for any country: us, de, cn, ua, kz…\nPlus ready-made bundles: geoip:private (LAN), geoip:telegram, geoip:google.\nNeed it by country? This is the one — geoip knows them all.\n\n## GeoSite — ready-made lists\ngeosite:google, geosite:netflix, geosite:telegram, geosite:category-ads-all…\nThese aren\'t countries but service categories someone already put together for you.\nHardly any countries here (just geolocation-cn and geolocation-!cn), so by-country is really geoip\'s job.\n\n## On PC (keqrnel core)\nGeo works the same as on the phone: the xray built into keqrnel does the matching. It just needs geoip.dat and geosite.dat sitting next to keqdroid.exe — a release build already has them there. If geo rules look ignored, check those two files first.\n\n## Order\nTop to bottom: block first, then your server (always direct, or you\'d get a loop), then bypass, then proxy. Whatever is left follows the Unmatched traffic switch up top.'**
  String get routingCheatSheetBody;

  /// No description provided for @settingsRoutingSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Routing updated'**
  String get settingsRoutingSavedToast;

  /// No description provided for @settingsRoutingItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{empty} =1{1 entry} other{{count} entries}}'**
  String settingsRoutingItemCount(int count);

  /// No description provided for @settingsAndroidColorsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Android colors · {mode}'**
  String settingsAndroidColorsSubtitle(Object mode);

  /// No description provided for @settingsSystemColorsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'System colors · {mode}'**
  String settingsSystemColorsSubtitle(Object mode);

  /// No description provided for @themeModeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeModeDark;

  /// No description provided for @themeModeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeModeLight;

  /// No description provided for @themeCustomizationTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get themeCustomizationTitle;

  /// No description provided for @themeUseDynamicColors.
  ///
  /// In en, this message translates to:
  /// **'Use Android dynamic colors'**
  String get themeUseDynamicColors;

  /// No description provided for @themeUseDynamicColorsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use Android dynamic colors when available'**
  String get themeUseDynamicColorsSubtitle;

  /// No description provided for @themeDynamicPaletteHint.
  ///
  /// In en, this message translates to:
  /// **'Dynamic Android palette is active. Light/Dark works independently.'**
  String get themeDynamicPaletteHint;

  /// No description provided for @themeSystemPaletteHint.
  ///
  /// In en, this message translates to:
  /// **'System accent palette is active. Light/Dark works independently.'**
  String get themeSystemPaletteHint;

  /// No description provided for @themeUseSystemColors.
  ///
  /// In en, this message translates to:
  /// **'Use system accent colors'**
  String get themeUseSystemColors;

  /// No description provided for @themeUseSystemColorsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Follow Windows or Linux accent colors when available'**
  String get themeUseSystemColorsSubtitle;

  /// No description provided for @themeCustomPaletteHint.
  ///
  /// In en, this message translates to:
  /// **'Custom palette is active. Light/Dark works independently.'**
  String get themeCustomPaletteHint;

  /// No description provided for @themeColorThemesTitle.
  ///
  /// In en, this message translates to:
  /// **'Color themes'**
  String get themeColorThemesTitle;

  /// No description provided for @serversTwoColumnsTitle.
  ///
  /// In en, this message translates to:
  /// **'Two-column server list'**
  String get serversTwoColumnsTitle;

  /// No description provided for @serversTwoColumnsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show servers in two columns to fit more on screen'**
  String get serversTwoColumnsSubtitle;

  /// No description provided for @settingsLanProxyTitle.
  ///
  /// In en, this message translates to:
  /// **'LAN Proxy'**
  String get settingsLanProxyTitle;

  /// No description provided for @settingsOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsOff;

  /// No description provided for @settingsLanSharingOnIp.
  ///
  /// In en, this message translates to:
  /// **'Sharing on {ip}'**
  String settingsLanSharingOnIp(Object ip);

  /// No description provided for @settingsHwidTitle.
  ///
  /// In en, this message translates to:
  /// **'Send device HWID'**
  String get settingsHwidTitle;

  /// No description provided for @settingsHwidEnabledRecommended.
  ///
  /// In en, this message translates to:
  /// **'Enabled (recommended)'**
  String get settingsHwidEnabledRecommended;

  /// No description provided for @settingsHwidDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get settingsHwidDisabled;

  /// No description provided for @settingsHwidEnabledHint.
  ///
  /// In en, this message translates to:
  /// **'Some providers require HWID for subscription updates and device limits.'**
  String get settingsHwidEnabledHint;

  /// No description provided for @settingsHwidDisabledHint.
  ///
  /// In en, this message translates to:
  /// **'HWID headers are not sent. Some subscriptions may fail if provider requires device binding.'**
  String get settingsHwidDisabledHint;

  /// No description provided for @settingsDeviceIpListTitle.
  ///
  /// In en, this message translates to:
  /// **'Device IP addresses on the network:'**
  String get settingsDeviceIpListTitle;

  /// No description provided for @settingsIpCopied.
  ///
  /// In en, this message translates to:
  /// **'IP copied'**
  String get settingsIpCopied;

  /// No description provided for @settingsSetupAnotherDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Setup on another device:'**
  String get settingsSetupAnotherDeviceTitle;

  /// No description provided for @settingsSocks5PortLabel.
  ///
  /// In en, this message translates to:
  /// **'SOCKS5 port'**
  String get settingsSocks5PortLabel;

  /// No description provided for @settingsHttpPortLabel.
  ///
  /// In en, this message translates to:
  /// **'HTTP port'**
  String get settingsHttpPortLabel;

  /// No description provided for @settingsLanUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get settingsLanUsernameLabel;

  /// No description provided for @settingsLanPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get settingsLanPasswordLabel;

  /// No description provided for @settingsLanAuthHint.
  ///
  /// In en, this message translates to:
  /// **'Both fields set — devices sign in to the proxy with them. Empty — no password (anyone on your network can use it).'**
  String get settingsLanAuthHint;

  /// No description provided for @settingsLocalPortsTitle.
  ///
  /// In en, this message translates to:
  /// **'Local proxy ports'**
  String get settingsLocalPortsTitle;

  /// No description provided for @settingsLocalPortsHint.
  ///
  /// In en, this message translates to:
  /// **'Listen ports for the local SOCKS5 and HTTP proxies (defaults 2080 / 2081). Applied on the next connection. The two ports must differ.'**
  String get settingsLocalPortsHint;

  /// No description provided for @settingsPortInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a port between 1 and 65535'**
  String get settingsPortInvalid;

  /// No description provided for @settingsPortsMustDiffer.
  ///
  /// In en, this message translates to:
  /// **'SOCKS and HTTP ports must differ'**
  String get settingsPortsMustDiffer;

  /// No description provided for @settingsTurnOffToChange.
  ///
  /// In en, this message translates to:
  /// **'Turn off to change setting'**
  String get settingsTurnOffToChange;

  /// No description provided for @settingsProxyCopied.
  ///
  /// In en, this message translates to:
  /// **'{label} {address} copied'**
  String settingsProxyCopied(Object label, Object address);

  /// No description provided for @settingsXrayCoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Core settings'**
  String get settingsXrayCoreTitle;

  /// No description provided for @settingsXrayCoreSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ports, DNS, XMUX, TUN, log and routing'**
  String get settingsXrayCoreSubtitle;

  /// No description provided for @settingsXrayDnsSection.
  ///
  /// In en, this message translates to:
  /// **'DNS'**
  String get settingsXrayDnsSection;

  /// No description provided for @settingsXrayDnsCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom DNS servers'**
  String get settingsXrayDnsCustom;

  /// No description provided for @settingsXrayDnsCustomHint.
  ///
  /// In en, this message translates to:
  /// **'One address per line (DoH, DoT, or plain)'**
  String get settingsXrayDnsCustomHint;

  /// No description provided for @settingsXrayDnsServers.
  ///
  /// In en, this message translates to:
  /// **'DNS servers'**
  String get settingsXrayDnsServers;

  /// No description provided for @settingsXrayDnsSplitDirect.
  ///
  /// In en, this message translates to:
  /// **'Split resolver for direct domains'**
  String get settingsXrayDnsSplitDirect;

  /// No description provided for @settingsXrayDnsSplitDirectHint.
  ///
  /// In en, this message translates to:
  /// **'Uses first server for domains from direct list'**
  String get settingsXrayDnsSplitDirectHint;

  /// No description provided for @settingsXrayDnsQueryStrategy.
  ///
  /// In en, this message translates to:
  /// **'Query strategy'**
  String get settingsXrayDnsQueryStrategy;

  /// No description provided for @settingsXrayDnsDisableCache.
  ///
  /// In en, this message translates to:
  /// **'Disable DNS cache'**
  String get settingsXrayDnsDisableCache;

  /// No description provided for @settingsXrayXmuxSection.
  ///
  /// In en, this message translates to:
  /// **'XMUX (XHTTP)'**
  String get settingsXrayXmuxSection;

  /// No description provided for @settingsXrayXmuxEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable XMUX'**
  String get settingsXrayXmuxEnable;

  /// No description provided for @settingsXrayXmuxEnableHint.
  ///
  /// In en, this message translates to:
  /// **'Multiplexing for XHTTP transport (client-side)'**
  String get settingsXrayXmuxEnableHint;

  /// No description provided for @settingsXrayGeneralSection.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsXrayGeneralSection;

  /// No description provided for @settingsXrayLogLevel.
  ///
  /// In en, this message translates to:
  /// **'Log level'**
  String get settingsXrayLogLevel;

  /// No description provided for @settingsXrayDomainStrategy.
  ///
  /// In en, this message translates to:
  /// **'Routing domain strategy'**
  String get settingsXrayDomainStrategy;

  /// No description provided for @settingsXraySniffing.
  ///
  /// In en, this message translates to:
  /// **'Inbound sniffing'**
  String get settingsXraySniffing;

  /// No description provided for @settingsXraySniffingRouteOnly.
  ///
  /// In en, this message translates to:
  /// **'Sniffing route only'**
  String get settingsXraySniffingRouteOnly;

  /// No description provided for @settingsXrayCoreIntro.
  ///
  /// In en, this message translates to:
  /// **'These options are injected into the generated Xray config. Change only if you know what they do.'**
  String get settingsXrayCoreIntro;

  /// No description provided for @settingsXrayDnsDefaultNote.
  ///
  /// In en, this message translates to:
  /// **'Default: Cloudflare and Google DoH'**
  String get settingsXrayDnsDefaultNote;

  /// No description provided for @settingsXrayXmuxParamsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tuning'**
  String get settingsXrayXmuxParamsTitle;

  /// No description provided for @settingsXrayXmuxParamsHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use Xray defaults. Values can be a number or range (e.g. 16-32).'**
  String get settingsXrayXmuxParamsHint;

  /// No description provided for @settingsXraySniffingHint.
  ///
  /// In en, this message translates to:
  /// **'Detect destination protocol and domain from inbound traffic'**
  String get settingsXraySniffingHint;

  /// No description provided for @settingsXraySniffingRouteOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Use sniffing for routing only, without overriding the destination'**
  String get settingsXraySniffingRouteOnlyHint;

  /// No description provided for @settingsXrayResetDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get settingsXrayResetDefaults;

  /// No description provided for @settingsXrayResetDone.
  ///
  /// In en, this message translates to:
  /// **'Xray core settings restored'**
  String get settingsXrayResetDone;

  /// No description provided for @settingsXrayXmuxMaxConcurrency.
  ///
  /// In en, this message translates to:
  /// **'Max concurrency'**
  String get settingsXrayXmuxMaxConcurrency;

  /// No description provided for @settingsXrayXmuxMaxConnections.
  ///
  /// In en, this message translates to:
  /// **'Max connections'**
  String get settingsXrayXmuxMaxConnections;

  /// No description provided for @settingsXrayXmuxCMaxReuseTimes.
  ///
  /// In en, this message translates to:
  /// **'Connection reuse limit'**
  String get settingsXrayXmuxCMaxReuseTimes;

  /// No description provided for @settingsXrayXmuxHMaxRequestTimes.
  ///
  /// In en, this message translates to:
  /// **'Max requests per stream'**
  String get settingsXrayXmuxHMaxRequestTimes;

  /// No description provided for @settingsXrayXmuxHMaxReusableSecs.
  ///
  /// In en, this message translates to:
  /// **'Stream reuse time (sec)'**
  String get settingsXrayXmuxHMaxReusableSecs;

  /// No description provided for @settingsXrayXmuxHKeepAlivePeriod.
  ///
  /// In en, this message translates to:
  /// **'Keep-alive period (sec)'**
  String get settingsXrayXmuxHKeepAlivePeriod;

  /// No description provided for @settingsTunSection.
  ///
  /// In en, this message translates to:
  /// **'TUN mode'**
  String get settingsTunSection;

  /// No description provided for @settingsTunSectionNote.
  ///
  /// In en, this message translates to:
  /// **'sing-box TUN interface options (desktop). Applied on next connection.'**
  String get settingsTunSectionNote;

  /// No description provided for @settingsTunStackTitle.
  ///
  /// In en, this message translates to:
  /// **'Network stack'**
  String get settingsTunStackTitle;

  /// No description provided for @settingsTunStackSystemHint.
  ///
  /// In en, this message translates to:
  /// **'Kernel TCP/IP stack — fastest, default'**
  String get settingsTunStackSystemHint;

  /// No description provided for @settingsTunStackGvisorHint.
  ///
  /// In en, this message translates to:
  /// **'Userspace stack — better compatibility, a bit slower. Needs a core built with gVisor (cores from app 0.7.1 and older exit with code 1)'**
  String get settingsTunStackGvisorHint;

  /// No description provided for @settingsTunStackMixedHint.
  ///
  /// In en, this message translates to:
  /// **'system for TCP, gVisor for UDP. Needs a core built with gVisor (cores from app 0.7.1 and older exit with code 1)'**
  String get settingsTunStackMixedHint;

  /// No description provided for @settingsTunMtu.
  ///
  /// In en, this message translates to:
  /// **'MTU'**
  String get settingsTunMtu;

  /// No description provided for @settingsTunMtuHint.
  ///
  /// In en, this message translates to:
  /// **'576–65535, default 1400'**
  String get settingsTunMtuHint;

  /// No description provided for @settingsTunUdpTimeout.
  ///
  /// In en, this message translates to:
  /// **'UDP timeout (sec)'**
  String get settingsTunUdpTimeout;

  /// No description provided for @settingsTunUdpTimeoutHint.
  ///
  /// In en, this message translates to:
  /// **'NAT lifetime of idle UDP sessions, default 300'**
  String get settingsTunUdpTimeoutHint;

  /// No description provided for @settingsTunStrictRouteTitle.
  ///
  /// In en, this message translates to:
  /// **'Strict route'**
  String get settingsTunStrictRouteTitle;

  /// No description provided for @settingsTunStrictRouteHint.
  ///
  /// In en, this message translates to:
  /// **'Prevents traffic from leaking around the TUN. On Windows it can break routing when another VPN (e.g. Tailscale) is active'**
  String get settingsTunStrictRouteHint;

  /// No description provided for @settingsTunStrictRouteAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get settingsTunStrictRouteAuto;

  /// No description provided for @settingsTunStrictRouteAutoHint.
  ///
  /// In en, this message translates to:
  /// **'Linux: on, Windows: off'**
  String get settingsTunStrictRouteAutoHint;

  /// No description provided for @settingsTunStrictRouteOn.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get settingsTunStrictRouteOn;

  /// No description provided for @settingsTunStrictRouteOff.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get settingsTunStrictRouteOff;

  /// No description provided for @settingsTunEin.
  ///
  /// In en, this message translates to:
  /// **'Endpoint-independent NAT'**
  String get settingsTunEin;

  /// No description provided for @settingsTunEinHint.
  ///
  /// In en, this message translates to:
  /// **'Full-cone NAT for UDP — helps P2P and games. gVisor/mixed stack only'**
  String get settingsTunEinHint;

  /// No description provided for @settingsTunAutoRoute.
  ///
  /// In en, this message translates to:
  /// **'Auto route'**
  String get settingsTunAutoRoute;

  /// No description provided for @settingsTunAutoRouteHint.
  ///
  /// In en, this message translates to:
  /// **'Adds system routes into the tunnel automatically. Disable only if you manage routes yourself — without it no traffic enters the TUN'**
  String get settingsTunAutoRouteHint;

  /// No description provided for @settingsPingTitle.
  ///
  /// In en, this message translates to:
  /// **'Server ping'**
  String get settingsPingTitle;

  /// No description provided for @settingsPingMethodTitle.
  ///
  /// In en, this message translates to:
  /// **'Ping method'**
  String get settingsPingMethodTitle;

  /// No description provided for @settingsPingMethodTcp.
  ///
  /// In en, this message translates to:
  /// **'TCP ping'**
  String get settingsPingMethodTcp;

  /// No description provided for @settingsPingMethodTcpHint.
  ///
  /// In en, this message translates to:
  /// **'Fast reachability check'**
  String get settingsPingMethodTcpHint;

  /// No description provided for @settingsPingMethodIcmp.
  ///
  /// In en, this message translates to:
  /// **'ICMP ping'**
  String get settingsPingMethodIcmp;

  /// No description provided for @settingsPingMethodIcmpHint.
  ///
  /// In en, this message translates to:
  /// **'Echo to server IP (some servers block it)'**
  String get settingsPingMethodIcmpHint;

  /// No description provided for @settingsPingMethodUrl.
  ///
  /// In en, this message translates to:
  /// **'HTTP via proxy'**
  String get settingsPingMethodUrl;

  /// No description provided for @settingsPingMethodUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Measures GET latency through the server'**
  String get settingsPingMethodUrlHint;

  /// No description provided for @settingsPingMethodSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed test'**
  String get settingsPingMethodSpeed;

  /// No description provided for @settingsPingMethodSpeedHint.
  ///
  /// In en, this message translates to:
  /// **'Downloads a fixed payload through the server and shows throughput in Mbps (works without VPN)'**
  String get settingsPingMethodSpeedHint;

  /// No description provided for @settingsPingTargetTitle.
  ///
  /// In en, this message translates to:
  /// **'HTTP test URL'**
  String get settingsPingTargetTitle;

  /// No description provided for @settingsPingTargetGstatic.
  ///
  /// In en, this message translates to:
  /// **'Google (generate_204)'**
  String get settingsPingTargetGstatic;

  /// No description provided for @settingsPingTargetCloudflare.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare (trace)'**
  String get settingsPingTargetCloudflare;

  /// No description provided for @settingsPingTargetMicrosoft.
  ///
  /// In en, this message translates to:
  /// **'Microsoft (connect test)'**
  String get settingsPingTargetMicrosoft;

  /// No description provided for @settingsPingTargetCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom URL'**
  String get settingsPingTargetCustom;

  /// No description provided for @settingsPingCustomUrl.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get settingsPingCustomUrl;

  /// No description provided for @settingsPingCustomUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https:// or http:// address for GET request'**
  String get settingsPingCustomUrlHint;

  /// No description provided for @settingsPingCustomUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid or unsafe URL (no localhost or private networks)'**
  String get settingsPingCustomUrlInvalid;

  /// No description provided for @subscriptionNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get subscriptionNameLabel;

  /// No description provided for @subscriptionNameHint.
  ///
  /// In en, this message translates to:
  /// **'My Subscription'**
  String get subscriptionNameHint;

  /// No description provided for @subscriptionUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get subscriptionUrlLabel;

  /// No description provided for @subscriptionUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://example.com/sub?token=...'**
  String get subscriptionUrlHint;

  /// No description provided for @subscriptionsAddSubscription.
  ///
  /// In en, this message translates to:
  /// **'Add Subscription'**
  String get subscriptionsAddSubscription;

  /// No description provided for @subscriptionsAddAndFetch.
  ///
  /// In en, this message translates to:
  /// **'Add & Fetch'**
  String get subscriptionsAddAndFetch;

  /// No description provided for @subscriptionsEditSubscription.
  ///
  /// In en, this message translates to:
  /// **'Edit subscription'**
  String get subscriptionsEditSubscription;

  /// No description provided for @subscriptionsCopyUrl.
  ///
  /// In en, this message translates to:
  /// **'Copy URL'**
  String get subscriptionsCopyUrl;

  /// No description provided for @subscriptionsUrlCopied.
  ///
  /// In en, this message translates to:
  /// **'URL copied'**
  String get subscriptionsUrlCopied;

  /// No description provided for @subscriptionsShareButton.
  ///
  /// In en, this message translates to:
  /// **'Share (QR + link)'**
  String get subscriptionsShareButton;

  /// No description provided for @subscriptionsShareAction.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get subscriptionsShareAction;

  /// No description provided for @subscriptionsShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not share: {error}'**
  String subscriptionsShareFailed(Object error);

  /// No description provided for @subscriptionsDeleteSubscription.
  ///
  /// In en, this message translates to:
  /// **'Delete subscription'**
  String get subscriptionsDeleteSubscription;

  /// No description provided for @subscriptionsDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?\n\nThis will also remove all associated servers.'**
  String subscriptionsDeleteConfirm(Object name);

  /// No description provided for @subscriptionsRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get subscriptionsRetry;

  /// No description provided for @subscriptionsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get subscriptionsCancel;

  /// No description provided for @subscriptionsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get subscriptionsDelete;

  /// No description provided for @subscriptionsSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get subscriptionsSave;

  /// No description provided for @subscriptionsMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get subscriptionsMoveUp;

  /// No description provided for @subscriptionsMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get subscriptionsMoveDown;

  /// No description provided for @subscriptionsAutoUpdate.
  ///
  /// In en, this message translates to:
  /// **'Auto-update'**
  String get subscriptionsAutoUpdate;

  /// No description provided for @subscriptionsOn.
  ///
  /// In en, this message translates to:
  /// **'ON'**
  String get subscriptionsOn;

  /// No description provided for @subscriptionsOff.
  ///
  /// In en, this message translates to:
  /// **'OFF'**
  String get subscriptionsOff;

  /// No description provided for @subscriptionsExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get subscriptionsExpired;

  /// No description provided for @subscriptionsRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Refresh failed'**
  String get subscriptionsRefreshFailed;

  /// No description provided for @subscriptionsEveryHour.
  ///
  /// In en, this message translates to:
  /// **'Every hour'**
  String get subscriptionsEveryHour;

  /// No description provided for @subscriptionsEveryHours.
  ///
  /// In en, this message translates to:
  /// **'Every {hours} hours'**
  String subscriptionsEveryHours(int hours);

  /// No description provided for @subscriptionsEveryDay.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get subscriptionsEveryDay;

  /// No description provided for @subscriptionsEveryDays.
  ///
  /// In en, this message translates to:
  /// **'Every {days} days'**
  String subscriptionsEveryDays(int days);

  /// No description provided for @subscriptionsAutoUpdateInterval.
  ///
  /// In en, this message translates to:
  /// **'Auto-update interval'**
  String get subscriptionsAutoUpdateInterval;

  /// No description provided for @subscriptionsCurrentInterval.
  ///
  /// In en, this message translates to:
  /// **'every {hours}h'**
  String subscriptionsCurrentInterval(int hours);

  /// Compact interval label for the chip on the subscription card
  ///
  /// In en, this message translates to:
  /// **'{hours}h'**
  String subscriptionsIntervalShort(int hours);

  /// No description provided for @subscriptionsJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get subscriptionsJustNow;

  /// No description provided for @subscriptionsMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String subscriptionsMinutesAgo(int minutes);

  /// No description provided for @subscriptionsHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String subscriptionsHoursAgo(int hours);

  /// No description provided for @subscriptionsDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String subscriptionsDaysAgo(int days);

  /// No description provided for @subscriptionsInDays.
  ///
  /// In en, this message translates to:
  /// **'in {days}d'**
  String subscriptionsInDays(int days);

  /// No description provided for @subscriptionsInHours.
  ///
  /// In en, this message translates to:
  /// **'in {hours}h'**
  String subscriptionsInHours(int hours);

  /// No description provided for @subscriptionsSoon.
  ///
  /// In en, this message translates to:
  /// **'soon'**
  String get subscriptionsSoon;

  /// No description provided for @serversAddServer.
  ///
  /// In en, this message translates to:
  /// **'Add server'**
  String get serversAddServer;

  /// No description provided for @serversPasteLinks.
  ///
  /// In en, this message translates to:
  /// **'Paste link(s)'**
  String get serversPasteLinks;

  /// No description provided for @serversImportFile.
  ///
  /// In en, this message translates to:
  /// **'Import file'**
  String get serversImportFile;

  /// No description provided for @serversNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Not supported in this build'**
  String get serversNotSupported;

  /// No description provided for @serversAddServerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Server'**
  String get serversAddServerTitle;

  /// No description provided for @serversPasteVlessHint.
  ///
  /// In en, this message translates to:
  /// **'Paste vless://, vmess://, trojan://, ss://, hysteria2:// or hy2:// (one per line), or a whole Xray JSON config'**
  String get serversPasteVlessHint;

  /// No description provided for @serversPasteHint.
  ///
  /// In en, this message translates to:
  /// **'vless://… or hy2://host:port?auth=…'**
  String get serversPasteHint;

  /// No description provided for @serversAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get serversAdd;

  /// No description provided for @serversManualServers.
  ///
  /// In en, this message translates to:
  /// **'Manual servers'**
  String get serversManualServers;

  /// No description provided for @serversRefreshSubscription.
  ///
  /// In en, this message translates to:
  /// **'Refresh subscription'**
  String get serversRefreshSubscription;

  /// No description provided for @serversPingAll.
  ///
  /// In en, this message translates to:
  /// **'Ping all'**
  String get serversPingAll;

  /// No description provided for @settingsAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get settingsAdvanced;

  /// No description provided for @settingsAdvancedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Core settings, ping, routing, HWID and debug'**
  String get settingsAdvancedSubtitle;

  /// No description provided for @serverEditorJsonValid.
  ///
  /// In en, this message translates to:
  /// **'Valid Xray config'**
  String get serverEditorJsonValid;

  /// No description provided for @serverEditorJsonFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get serverEditorJsonFormat;

  /// No description provided for @subscriptionsCardMenu.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get subscriptionsCardMenu;

  /// No description provided for @subscriptionsAutoUpdateOff.
  ///
  /// In en, this message translates to:
  /// **'Do not update automatically'**
  String get subscriptionsAutoUpdateOff;

  /// No description provided for @subscriptionsProviderPage.
  ///
  /// In en, this message translates to:
  /// **'Subscription page'**
  String get subscriptionsProviderPage;

  /// No description provided for @subscriptionsSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get subscriptionsSupport;

  /// No description provided for @subscriptionsLinkOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the link'**
  String get subscriptionsLinkOpenFailed;

  /// No description provided for @settingsAdvancedGroupTraffic.
  ///
  /// In en, this message translates to:
  /// **'Traffic and core'**
  String get settingsAdvancedGroupTraffic;

  /// No description provided for @settingsAdvancedGroupSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsAdvancedGroupSystem;

  /// No description provided for @settingsAdvancedGroupDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get settingsAdvancedGroupDiagnostics;

  /// No description provided for @settingsBackupRestore.
  ///
  /// In en, this message translates to:
  /// **'Backup & restore'**
  String get settingsBackupRestore;

  /// No description provided for @settingsBackupRestoreSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Export/import split tunneling, subscriptions and servers'**
  String get settingsBackupRestoreSubtitle;

  /// No description provided for @settingsSelectAtLeastOne.
  ///
  /// In en, this message translates to:
  /// **'Select at least one section to export'**
  String get settingsSelectAtLeastOne;

  /// No description provided for @settingsBackupSaved.
  ///
  /// In en, this message translates to:
  /// **'Backup saved successfully'**
  String get settingsBackupSaved;

  /// No description provided for @settingsSelectLocation.
  ///
  /// In en, this message translates to:
  /// **'Select location to save backup'**
  String get settingsSelectLocation;

  /// No description provided for @settingsExportFile.
  ///
  /// In en, this message translates to:
  /// **'Export file'**
  String get settingsExportFile;

  /// No description provided for @settingsImportFile.
  ///
  /// In en, this message translates to:
  /// **'Import from file'**
  String get settingsImportFile;

  /// No description provided for @settingsImportBackup.
  ///
  /// In en, this message translates to:
  /// **'Import backup'**
  String get settingsImportBackup;

  /// No description provided for @settingsChooseWhatToImport.
  ///
  /// In en, this message translates to:
  /// **'Choose what to import (selected sections will replace your current data).'**
  String get settingsChooseWhatToImport;

  /// No description provided for @settingsSplitTunnelingApps.
  ///
  /// In en, this message translates to:
  /// **'Split tunneling apps'**
  String get settingsSplitTunnelingApps;

  /// No description provided for @settingsSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get settingsSubscriptions;

  /// No description provided for @settingsServersActive.
  ///
  /// In en, this message translates to:
  /// **'Servers (and active server)'**
  String get settingsServersActive;

  /// No description provided for @settingsImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get settingsImport;

  /// No description provided for @settingsExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get settingsExport;

  /// No description provided for @settingsCreateFileToSave.
  ///
  /// In en, this message translates to:
  /// **'Create a file you can save and import on another device.'**
  String get settingsCreateFileToSave;

  /// No description provided for @settingsPickExportedFile.
  ///
  /// In en, this message translates to:
  /// **'Pick a previously exported file and restore selected sections.'**
  String get settingsPickExportedFile;

  /// No description provided for @settingsWorking.
  ///
  /// In en, this message translates to:
  /// **'Working...'**
  String get settingsWorking;

  /// No description provided for @settingsImportedSections.
  ///
  /// In en, this message translates to:
  /// **'Imported: {count} section(s)'**
  String settingsImportedSections(int count);

  /// No description provided for @settingsDebugMode.
  ///
  /// In en, this message translates to:
  /// **'Debug mode'**
  String get settingsDebugMode;

  /// No description provided for @settingsDebugModeOn.
  ///
  /// In en, this message translates to:
  /// **'Extended diagnostics enabled'**
  String get settingsDebugModeOn;

  /// No description provided for @settingsDebugModeOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsDebugModeOff;

  /// No description provided for @settingsDebugModeHint.
  ///
  /// In en, this message translates to:
  /// **'Shows live VPN metrics in server cards and allows viewing core logs.'**
  String get settingsDebugModeHint;

  /// No description provided for @settingsOpenXrayLogs.
  ///
  /// In en, this message translates to:
  /// **'Open core logs'**
  String get settingsOpenXrayLogs;

  /// No description provided for @settingsXrayCoreLogs.
  ///
  /// In en, this message translates to:
  /// **'Core logs'**
  String get settingsXrayCoreLogs;

  /// No description provided for @settingsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get settingsRefresh;

  /// No description provided for @settingsCopyLogs.
  ///
  /// In en, this message translates to:
  /// **'Copy logs'**
  String get settingsCopyLogs;

  /// No description provided for @settingsAppVersion.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get settingsAppVersion;

  /// No description provided for @settingsChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get settingsChecking;

  /// No description provided for @settingsCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Check failed'**
  String get settingsCheckFailed;

  /// No description provided for @settingsUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get settingsUpdateAvailable;

  /// No description provided for @settingsUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get settingsUpToDate;

  /// No description provided for @settingsNewVersionAvailable.
  ///
  /// In en, this message translates to:
  /// **'New version available'**
  String get settingsNewVersionAvailable;

  /// No description provided for @settingsSize.
  ///
  /// In en, this message translates to:
  /// **'Size: {size}'**
  String settingsSize(Object size);

  /// No description provided for @settingsDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading...'**
  String get settingsDownloading;

  /// No description provided for @settingsCheckForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsCheckForUpdates;

  /// No description provided for @settingsShareDeviceHwid.
  ///
  /// In en, this message translates to:
  /// **'Share device HWID'**
  String get settingsShareDeviceHwid;

  /// No description provided for @settingsHwidWillBeSent.
  ///
  /// In en, this message translates to:
  /// **'HWID will be sent with subscription requests'**
  String get settingsHwidWillBeSent;

  /// No description provided for @settingsHwidNotShared.
  ///
  /// In en, this message translates to:
  /// **'HWID not shared'**
  String get settingsHwidNotShared;

  /// No description provided for @settingsHwidHint.
  ///
  /// In en, this message translates to:
  /// **'When enabled, your device\'s unique ID (HWID) is sent to subscription servers. Required by some providers for HWID binding. Disable to increase privacy.'**
  String get settingsHwidHint;

  /// No description provided for @settingsRoutingRules.
  ///
  /// In en, this message translates to:
  /// **'Routing Rules'**
  String get settingsRoutingRules;

  /// No description provided for @settingsNoRules.
  ///
  /// In en, this message translates to:
  /// **'No rules'**
  String get settingsNoRules;

  /// No description provided for @settingsAddCustomRule.
  ///
  /// In en, this message translates to:
  /// **'Add custom rule'**
  String get settingsAddCustomRule;

  /// No description provided for @settingsAddRule.
  ///
  /// In en, this message translates to:
  /// **'Add rule'**
  String get settingsAddRule;

  /// No description provided for @settingsEditRule.
  ///
  /// In en, this message translates to:
  /// **'Edit routing rule'**
  String get settingsEditRule;

  /// No description provided for @settingsRuleName.
  ///
  /// In en, this message translates to:
  /// **'Rule name'**
  String get settingsRuleName;

  /// No description provided for @settingsType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get settingsType;

  /// No description provided for @settingsAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get settingsAction;

  /// No description provided for @settingsValues.
  ///
  /// In en, this message translates to:
  /// **'Values (what to match)'**
  String get settingsValues;

  /// No description provided for @settingsOrder.
  ///
  /// In en, this message translates to:
  /// **'Order (rule priority)'**
  String get settingsOrder;

  /// No description provided for @settingsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get settingsEnabled;

  /// No description provided for @settingsNameAndValuesRequired.
  ///
  /// In en, this message translates to:
  /// **'Name and values are required'**
  String get settingsNameAndValuesRequired;

  /// No description provided for @settingsUseOnePerLine.
  ///
  /// In en, this message translates to:
  /// **'Use one value per line, or separate with commas.'**
  String get settingsUseOnePerLine;

  /// No description provided for @settingsSmallerOrderFirst.
  ///
  /// In en, this message translates to:
  /// **'Smaller number = checked earlier (e.g. 1 before 50)'**
  String get settingsSmallerOrderFirst;

  /// No description provided for @settingsSmallerOrderWins.
  ///
  /// In en, this message translates to:
  /// **'If two rules can match the same traffic, the rule with smaller order wins.'**
  String get settingsSmallerOrderWins;

  /// No description provided for @settingsSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get settingsSaveChanges;

  /// No description provided for @settingsDeleteRule.
  ///
  /// In en, this message translates to:
  /// **'Delete rule'**
  String get settingsDeleteRule;

  /// No description provided for @settingsAddRuleTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add rule'**
  String get settingsAddRuleTooltip;

  /// No description provided for @settingsDomain.
  ///
  /// In en, this message translates to:
  /// **'Domain'**
  String get settingsDomain;

  /// No description provided for @settingsIpCidr.
  ///
  /// In en, this message translates to:
  /// **'IP CIDR'**
  String get settingsIpCidr;

  /// No description provided for @settingsGeoIp.
  ///
  /// In en, this message translates to:
  /// **'GeoIP'**
  String get settingsGeoIp;

  /// No description provided for @settingsGeosite.
  ///
  /// In en, this message translates to:
  /// **'Geosite'**
  String get settingsGeosite;

  /// No description provided for @settingsProcess.
  ///
  /// In en, this message translates to:
  /// **'Process'**
  String get settingsProcess;

  /// No description provided for @settingsProxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get settingsProxy;

  /// No description provided for @settingsDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get settingsDirect;

  /// No description provided for @settingsBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get settingsBlock;

  /// No description provided for @settingsEgDomain.
  ///
  /// In en, this message translates to:
  /// **'e.g. youtube.com, +google'**
  String get settingsEgDomain;

  /// No description provided for @settingsEgIpCidr.
  ///
  /// In en, this message translates to:
  /// **'e.g. 1.1.1.1/32, 192.168.0.0/16'**
  String get settingsEgIpCidr;

  /// No description provided for @settingsEgGeoip.
  ///
  /// In en, this message translates to:
  /// **'e.g. RU, US, DE'**
  String get settingsEgGeoip;

  /// No description provided for @settingsEgGeosite.
  ///
  /// In en, this message translates to:
  /// **'e.g. category-ads-all'**
  String get settingsEgGeosite;

  /// No description provided for @settingsEgProcess.
  ///
  /// In en, this message translates to:
  /// **'e.g. com.telegram.messenger'**
  String get settingsEgProcess;

  /// No description provided for @settingsExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String settingsExportFailed(Object error);

  /// No description provided for @settingsImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String settingsImportFailed(Object error);

  /// No description provided for @settingsDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String settingsDownloadFailed(Object error);

  /// No description provided for @settingsCheckFailedError.
  ///
  /// In en, this message translates to:
  /// **'Check failed: {error}'**
  String settingsCheckFailedError(Object error);

  /// No description provided for @settingsNoXrayLogsYet.
  ///
  /// In en, this message translates to:
  /// **'No core logs yet'**
  String get settingsNoXrayLogsYet;

  /// No description provided for @settingsLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageTitle;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{language}'**
  String settingsLanguageSubtitle(Object language);

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageRussian.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get settingsLanguageRussian;

  /// No description provided for @settingsLanguageGerman.
  ///
  /// In en, this message translates to:
  /// **'Deutsch'**
  String get settingsLanguageGerman;

  /// No description provided for @settingsLanguageChinese.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get settingsLanguageChinese;

  /// No description provided for @settingsLanguageFarsi.
  ///
  /// In en, this message translates to:
  /// **'فارسی'**
  String get settingsLanguageFarsi;

  /// No description provided for @settingsLanguageSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get settingsLanguageSheetTitle;

  /// No description provided for @splitAddApp.
  ///
  /// In en, this message translates to:
  /// **'Add app'**
  String get splitAddApp;

  /// No description provided for @splitAddAppTitle.
  ///
  /// In en, this message translates to:
  /// **'Add application'**
  String get splitAddAppTitle;

  /// No description provided for @splitAddAppHint.
  ///
  /// In en, this message translates to:
  /// **'Path to .exe or name (e.g. chrome.exe)'**
  String get splitAddAppHint;

  /// No description provided for @splitAddAppPickFile.
  ///
  /// In en, this message translates to:
  /// **'Browse…'**
  String get splitAddAppPickFile;

  /// No description provided for @splitAddAppInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid .exe name or path'**
  String get splitAddAppInvalid;

  /// No description provided for @splitAddAppAdded.
  ///
  /// In en, this message translates to:
  /// **'Added: {name}'**
  String splitAddAppAdded(Object name);

  /// No description provided for @splitRunningApps.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get splitRunningApps;

  /// No description provided for @splitInstalledApps.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get splitInstalledApps;

  /// No description provided for @splitCustomApps.
  ///
  /// In en, this message translates to:
  /// **'Manual entries'**
  String get splitCustomApps;

  /// No description provided for @splitClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get splitClearAll;

  /// No description provided for @splitProxyModeWarning.
  ///
  /// In en, this message translates to:
  /// **'Split tunneling is not applied in Proxy mode — all traffic goes through the system proxy. Switch the connection mode to TUN (in the side panel) so per-process rules work.'**
  String get splitProxyModeWarning;

  /// No description provided for @settingsLatestVersionInstalled.
  ///
  /// In en, this message translates to:
  /// **'You have the latest version'**
  String get settingsLatestVersionInstalled;

  /// No description provided for @serversPingServer.
  ///
  /// In en, this message translates to:
  /// **'Ping server'**
  String get serversPingServer;

  /// No description provided for @serversHealthCheck.
  ///
  /// In en, this message translates to:
  /// **'Health check'**
  String get serversHealthCheck;

  /// No description provided for @serversCopyAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy server address'**
  String get serversCopyAddress;

  /// No description provided for @serversCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get serversCopiedToClipboard;

  /// No description provided for @serversCopyConfig.
  ///
  /// In en, this message translates to:
  /// **'Copy configuration'**
  String get serversCopyConfig;

  /// No description provided for @serversConfigCopied.
  ///
  /// In en, this message translates to:
  /// **'Configuration copied'**
  String get serversConfigCopied;

  /// No description provided for @serversDeleteServer.
  ///
  /// In en, this message translates to:
  /// **'Delete server'**
  String get serversDeleteServer;

  /// No description provided for @serversHealthCheckDesc.
  ///
  /// In en, this message translates to:
  /// **'DNS, TCP and config validation'**
  String get serversHealthCheckDesc;

  /// No description provided for @settingsDebugHintDesktop.
  ///
  /// In en, this message translates to:
  /// **'Shows core session logs. Live VPN metrics are shown under the connect button.'**
  String get settingsDebugHintDesktop;

  /// No description provided for @settingsDebugHintMobile.
  ///
  /// In en, this message translates to:
  /// **'Shows live VPN metrics in server cards and core logs.'**
  String get settingsDebugHintMobile;

  /// No description provided for @serversErrorLoadingApps.
  ///
  /// In en, this message translates to:
  /// **'Error loading apps: {error}'**
  String serversErrorLoadingApps(Object error);

  /// No description provided for @desktopConnectionMode.
  ///
  /// In en, this message translates to:
  /// **'Connection mode'**
  String get desktopConnectionMode;

  /// No description provided for @desktopModeShort.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get desktopModeShort;

  /// No description provided for @desktopDisconnectBeforeModeChange.
  ///
  /// In en, this message translates to:
  /// **'Disconnect before changing connection mode'**
  String get desktopDisconnectBeforeModeChange;

  /// No description provided for @settingsDesktopTitle.
  ///
  /// In en, this message translates to:
  /// **'Windows'**
  String get settingsDesktopTitle;

  /// No description provided for @settingsDesktopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tray, autostart, auto-connect'**
  String get settingsDesktopSubtitle;

  /// No description provided for @settingsMinimizeToTray.
  ///
  /// In en, this message translates to:
  /// **'Minimize to tray on close'**
  String get settingsMinimizeToTray;

  /// No description provided for @settingsMinimizeToTrayHint.
  ///
  /// In en, this message translates to:
  /// **'When off, closing the window exits the app'**
  String get settingsMinimizeToTrayHint;

  /// No description provided for @settingsLaunchAtStartup.
  ///
  /// In en, this message translates to:
  /// **'Start with Windows'**
  String get settingsLaunchAtStartup;

  /// No description provided for @settingsLaunchAtStartupHint.
  ///
  /// In en, this message translates to:
  /// **'Launch the app when you sign in'**
  String get settingsLaunchAtStartupHint;

  /// No description provided for @settingsAutoConnectOnAutostart.
  ///
  /// In en, this message translates to:
  /// **'Connect on autostart'**
  String get settingsAutoConnectOnAutostart;

  /// No description provided for @settingsAutoConnectOnAutostartHint.
  ///
  /// In en, this message translates to:
  /// **'Connect to the last selected server using the mode from the sidebar. If TUN needs admin rights and they are unavailable, Proxy is used'**
  String get settingsAutoConnectOnAutostartHint;

  /// No description provided for @settingsAutoConnectRequiresAutostart.
  ///
  /// In en, this message translates to:
  /// **'Enable \"Start with Windows\" first'**
  String get settingsAutoConnectRequiresAutostart;

  /// No description provided for @desktopTunAdminTitle.
  ///
  /// In en, this message translates to:
  /// **'Administrator rights required'**
  String get desktopTunAdminTitle;

  /// No description provided for @desktopTunAdminMessage.
  ///
  /// In en, this message translates to:
  /// **'TUN mode needs administrator rights. Restart the app as administrator to use TUN. The current mode in the sidebar will be kept.'**
  String get desktopTunAdminMessage;

  /// No description provided for @desktopTunAdminRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart as administrator'**
  String get desktopTunAdminRestart;

  /// No description provided for @desktopTunAdminCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get desktopTunAdminCancel;

  /// No description provided for @desktopTunAdminRestartFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not restart as administrator'**
  String get desktopTunAdminRestartFailed;

  /// No description provided for @trayMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'KeqDroid'**
  String get trayMenuTitle;

  /// No description provided for @trayCloseMenu.
  ///
  /// In en, this message translates to:
  /// **'Close menu'**
  String get trayCloseMenu;

  /// No description provided for @trayConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get trayConnect;

  /// No description provided for @trayDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get trayDisconnect;

  /// No description provided for @trayOpenApp.
  ///
  /// In en, this message translates to:
  /// **'Open app'**
  String get trayOpenApp;

  /// No description provided for @trayExit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get trayExit;

  /// No description provided for @trayServersSection.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get trayServersSection;

  /// No description provided for @trayPickServer.
  ///
  /// In en, this message translates to:
  /// **'Select server…'**
  String get trayPickServer;

  /// No description provided for @trayModeProxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get trayModeProxy;

  /// No description provided for @trayModeTun.
  ///
  /// In en, this message translates to:
  /// **'TUN'**
  String get trayModeTun;

  /// No description provided for @trayStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get trayStatusConnected;

  /// No description provided for @trayStatusDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get trayStatusDisconnected;

  /// No description provided for @trayStatusError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get trayStatusError;

  /// No description provided for @serversSortTitle.
  ///
  /// In en, this message translates to:
  /// **'Sort servers'**
  String get serversSortTitle;

  /// No description provided for @serversSortDefault.
  ///
  /// In en, this message translates to:
  /// **'Default order'**
  String get serversSortDefault;

  /// No description provided for @serversSortPing.
  ///
  /// In en, this message translates to:
  /// **'Ping (low → high)'**
  String get serversSortPing;

  /// No description provided for @serversSortSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed (high → low)'**
  String get serversSortSpeed;

  /// No description provided for @serversSortName.
  ///
  /// In en, this message translates to:
  /// **'Name (A → Z)'**
  String get serversSortName;

  /// No description provided for @updateActionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip this version'**
  String get updateActionSkip;

  /// No description provided for @updateSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size: {size}'**
  String updateSizeLabel(Object size);

  /// No description provided for @updateOpenDownload.
  ///
  /// In en, this message translates to:
  /// **'Open download'**
  String get updateOpenDownload;

  /// No description provided for @vpnConnectedGeneric.
  ///
  /// In en, this message translates to:
  /// **'VPN connected'**
  String get vpnConnectedGeneric;

  /// No description provided for @serversImportedSummary.
  ///
  /// In en, this message translates to:
  /// **'Servers added: {added} of {total}'**
  String serversImportedSummary(Object added, Object total);

  /// No description provided for @serversManualGroup.
  ///
  /// In en, this message translates to:
  /// **'Manual servers'**
  String get serversManualGroup;

  /// No description provided for @serversEmptyGroupHint.
  ///
  /// In en, this message translates to:
  /// **'No servers in this subscription'**
  String get serversEmptyGroupHint;

  /// No description provided for @healthCheckChecksPassed.
  ///
  /// In en, this message translates to:
  /// **'Checks passed: {passed}/{total}'**
  String healthCheckChecksPassed(Object passed, Object total);

  /// No description provided for @healthCheckServerFields.
  ///
  /// In en, this message translates to:
  /// **'Server fields'**
  String get healthCheckServerFields;

  /// No description provided for @healthCheckDnsResolve.
  ///
  /// In en, this message translates to:
  /// **'DNS resolve'**
  String get healthCheckDnsResolve;

  /// No description provided for @healthCheckTcpHandshake.
  ///
  /// In en, this message translates to:
  /// **'TCP handshake'**
  String get healthCheckTcpHandshake;

  /// No description provided for @healthCheckConfigFormat.
  ///
  /// In en, this message translates to:
  /// **'Config format'**
  String get healthCheckConfigFormat;

  /// No description provided for @healthCheckNoIpResolved.
  ///
  /// In en, this message translates to:
  /// **'No IP resolved'**
  String get healthCheckNoIpResolved;

  /// No description provided for @healthCheckDnsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String healthCheckDnsFailed(Object error);

  /// No description provided for @healthCheckUriFormat.
  ///
  /// In en, this message translates to:
  /// **'URI format detected'**
  String get healthCheckUriFormat;

  /// No description provided for @healthCheckMissingScheme.
  ///
  /// In en, this message translates to:
  /// **'Missing URI scheme'**
  String get healthCheckMissingScheme;

  /// No description provided for @healthCheckConfigEmpty.
  ///
  /// In en, this message translates to:
  /// **'Config is empty'**
  String get healthCheckConfigEmpty;

  /// No description provided for @statsInLabel.
  ///
  /// In en, this message translates to:
  /// **'In'**
  String get statsInLabel;

  /// No description provided for @statsTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get statsTimeLabel;

  /// No description provided for @qrScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get qrScanTitle;

  /// No description provided for @qrScanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at a QR code'**
  String get qrScanHint;

  /// No description provided for @qrScanCameraError.
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable'**
  String get qrScanCameraError;

  /// No description provided for @serversScanQrHint.
  ///
  /// In en, this message translates to:
  /// **'Server link or subscription link'**
  String get serversScanQrHint;

  /// No description provided for @qrSubscriptionAdded.
  ///
  /// In en, this message translates to:
  /// **'Subscription added: {name}'**
  String qrSubscriptionAdded(Object name);

  /// No description provided for @qrNotSubscriptionLink.
  ///
  /// In en, this message translates to:
  /// **'QR code doesn\'t contain a subscription link'**
  String get qrNotSubscriptionLink;

  /// No description provided for @settingsHotkeysTitle.
  ///
  /// In en, this message translates to:
  /// **'Hotkeys'**
  String get settingsHotkeysTitle;

  /// No description provided for @settingsHotkeysSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts for connection, mode and servers'**
  String get settingsHotkeysSubtitle;

  /// No description provided for @hotkeysHintGlobal.
  ///
  /// In en, this message translates to:
  /// **'Hotkeys work system-wide, even when the window is hidden in the tray. All hotkeys are disabled until you assign them.'**
  String get hotkeysHintGlobal;

  /// No description provided for @hotkeysHintInApp.
  ///
  /// In en, this message translates to:
  /// **'On Linux hotkeys work while the app window is focused. All hotkeys are disabled until you assign them.'**
  String get hotkeysHintInApp;

  /// No description provided for @hotkeyActionToggleConnection.
  ///
  /// In en, this message translates to:
  /// **'Connect / disconnect'**
  String get hotkeyActionToggleConnection;

  /// No description provided for @hotkeyActionToggleConnectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Toggle the tunnel for the active server'**
  String get hotkeyActionToggleConnectionDesc;

  /// No description provided for @hotkeyActionToggleTun.
  ///
  /// In en, this message translates to:
  /// **'Toggle TUN mode'**
  String get hotkeyActionToggleTun;

  /// No description provided for @hotkeyActionToggleTunDesc.
  ///
  /// In en, this message translates to:
  /// **'Switch between Proxy and TUN, reconnecting if needed'**
  String get hotkeyActionToggleTunDesc;

  /// No description provided for @hotkeyActionBestPing.
  ///
  /// In en, this message translates to:
  /// **'Best-ping server'**
  String get hotkeyActionBestPing;

  /// No description provided for @hotkeyActionBestPingDesc.
  ///
  /// In en, this message translates to:
  /// **'Switch to the server with the lowest ping'**
  String get hotkeyActionBestPingDesc;

  /// No description provided for @hotkeyActionToggleWindow.
  ///
  /// In en, this message translates to:
  /// **'Show / hide window'**
  String get hotkeyActionToggleWindow;

  /// No description provided for @hotkeyActionToggleWindowDesc.
  ///
  /// In en, this message translates to:
  /// **'Restore the window from the tray or hide it'**
  String get hotkeyActionToggleWindowDesc;

  /// No description provided for @hotkeyNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get hotkeyNotSet;

  /// No description provided for @hotkeyPressKeys.
  ///
  /// In en, this message translates to:
  /// **'Press a shortcut…'**
  String get hotkeyPressKeys;

  /// No description provided for @hotkeyRecordingHint.
  ///
  /// In en, this message translates to:
  /// **'Esc — cancel, Backspace — clear'**
  String get hotkeyRecordingHint;

  /// No description provided for @hotkeyNeedsModifier.
  ///
  /// In en, this message translates to:
  /// **'Use a modifier (Ctrl/Alt/Shift/Win) or an F-key'**
  String get hotkeyNeedsModifier;

  /// No description provided for @hotkeyConflictTaken.
  ///
  /// In en, this message translates to:
  /// **'Shortcut {combo} is already taken by another app'**
  String hotkeyConflictTaken(Object combo);

  /// No description provided for @hotkeyClearTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear shortcut'**
  String get hotkeyClearTooltip;

  /// No description provided for @hotkeyNoPingData.
  ///
  /// In en, this message translates to:
  /// **'No ping results yet — run a ping test first'**
  String get hotkeyNoPingData;

  /// No description provided for @clipboardNoSubscriptionLink.
  ///
  /// In en, this message translates to:
  /// **'Clipboard has no subscription link (http/https)'**
  String get clipboardNoSubscriptionLink;

  /// No description provided for @splitTunnelingReconnectHint.
  ///
  /// In en, this message translates to:
  /// **'Changes apply after reconnecting the VPN'**
  String get splitTunnelingReconnectHint;

  /// No description provided for @serversDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String serversDeleteConfirm(Object name);

  /// No description provided for @errorTunAdminMessage.
  ///
  /// In en, this message translates to:
  /// **'TUN mode on Windows needs Administrator rights.'**
  String get errorTunAdminMessage;

  /// No description provided for @errorTunAdminAction.
  ///
  /// In en, this message translates to:
  /// **'Run the app as administrator or switch to Proxy mode in settings.'**
  String get errorTunAdminAction;

  /// No description provided for @errorVpnPermissionMessage.
  ///
  /// In en, this message translates to:
  /// **'VPN permission was not granted.'**
  String get errorVpnPermissionMessage;

  /// No description provided for @errorVpnPermissionAction.
  ///
  /// In en, this message translates to:
  /// **'Allow VPN permission in the system dialog and try again.'**
  String get errorVpnPermissionAction;

  /// No description provided for @errorHwidBindMessage.
  ///
  /// In en, this message translates to:
  /// **'Provider requires HWID binding for this device.'**
  String get errorHwidBindMessage;

  /// No description provided for @errorHwidBindAction.
  ///
  /// In en, this message translates to:
  /// **'Bind this device in provider panel, then refresh subscription.'**
  String get errorHwidBindAction;

  /// No description provided for @errorDeviceLimitMessage.
  ///
  /// In en, this message translates to:
  /// **'Provider refused subscription due to device limit.'**
  String get errorDeviceLimitMessage;

  /// No description provided for @errorDeviceLimitAction.
  ///
  /// In en, this message translates to:
  /// **'Remove old devices in provider panel or raise device limit.'**
  String get errorDeviceLimitAction;

  /// No description provided for @errorConfigInvalidMessage.
  ///
  /// In en, this message translates to:
  /// **'Subscription or server configuration is invalid.'**
  String get errorConfigInvalidMessage;

  /// No description provided for @errorConfigInvalidAction.
  ///
  /// In en, this message translates to:
  /// **'Check URL/config format and import a valid subscription link.'**
  String get errorConfigInvalidAction;

  /// No description provided for @errorAuthDeniedMessage.
  ///
  /// In en, this message translates to:
  /// **'Access to subscription is denied by provider.'**
  String get errorAuthDeniedMessage;

  /// No description provided for @errorAuthDeniedAction.
  ///
  /// In en, this message translates to:
  /// **'Check token/credentials and verify subscription has not expired.'**
  String get errorAuthDeniedAction;

  /// No description provided for @errorSubUrlInvalidMessage.
  ///
  /// In en, this message translates to:
  /// **'Subscription link is missing or expired.'**
  String get errorSubUrlInvalidMessage;

  /// No description provided for @errorSubUrlInvalidAction.
  ///
  /// In en, this message translates to:
  /// **'Request a fresh URL from provider and update it in app.'**
  String get errorSubUrlInvalidAction;

  /// No description provided for @errorSubInsecureHttpMessage.
  ///
  /// In en, this message translates to:
  /// **'Subscription link uses plain http, updates are blocked.'**
  String get errorSubInsecureHttpMessage;

  /// No description provided for @errorSubInsecureHttpAction.
  ///
  /// In en, this message translates to:
  /// **'Replace the link with its https:// version.'**
  String get errorSubInsecureHttpAction;

  /// No description provided for @subInsecureHttpWarning.
  ///
  /// In en, this message translates to:
  /// **'http link — updates are blocked'**
  String get subInsecureHttpWarning;

  /// No description provided for @subSwitchToHttps.
  ///
  /// In en, this message translates to:
  /// **'Switch to https'**
  String get subSwitchToHttps;

  /// No description provided for @errorNetworkMessage.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach server right now.'**
  String get errorNetworkMessage;

  /// No description provided for @errorNetworkAction.
  ///
  /// In en, this message translates to:
  /// **'Check internet, DNS, and server availability, then retry.'**
  String get errorNetworkAction;

  /// No description provided for @errorUnknownAction.
  ///
  /// In en, this message translates to:
  /// **'Retry operation. If issue repeats, check server and app settings.'**
  String get errorUnknownAction;

  /// No description provided for @serversPin.
  ///
  /// In en, this message translates to:
  /// **'Pin server'**
  String get serversPin;

  /// No description provided for @serversUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin server'**
  String get serversUnpin;

  /// No description provided for @serversPinDesc.
  ///
  /// In en, this message translates to:
  /// **'Pinned servers stay on top of the list'**
  String get serversPinDesc;

  /// No description provided for @serversRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get serversRename;

  /// No description provided for @serversRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename server'**
  String get serversRenameTitle;

  /// No description provided for @serversRenameHint.
  ///
  /// In en, this message translates to:
  /// **'Server name'**
  String get serversRenameHint;

  /// No description provided for @serversRenameReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get serversRenameReset;

  /// No description provided for @serversRenameOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original name: {name}'**
  String serversRenameOriginal(Object name);

  /// No description provided for @serversEditConfig.
  ///
  /// In en, this message translates to:
  /// **'Edit configuration'**
  String get serversEditConfig;

  /// No description provided for @serversEditConfigDesc.
  ///
  /// In en, this message translates to:
  /// **'SNI, fingerprint, transport and other settings'**
  String get serversEditConfigDesc;

  /// No description provided for @serverEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'Server configuration'**
  String get serverEditorTitle;

  /// No description provided for @serverEditorSectionGeneral.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get serverEditorSectionGeneral;

  /// No description provided for @serverEditorSectionSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get serverEditorSectionSecurity;

  /// No description provided for @serverEditorSectionTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get serverEditorSectionTransport;

  /// No description provided for @serverEditorSectionProtocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol settings'**
  String get serverEditorSectionProtocol;

  /// No description provided for @serverEditorAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get serverEditorAddress;

  /// No description provided for @serverEditorPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get serverEditorPort;

  /// No description provided for @serverEditorPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get serverEditorPassword;

  /// No description provided for @serverEditorMethod.
  ///
  /// In en, this message translates to:
  /// **'Encryption method'**
  String get serverEditorMethod;

  /// No description provided for @serverEditorEncryption.
  ///
  /// In en, this message translates to:
  /// **'Encryption'**
  String get serverEditorEncryption;

  /// No description provided for @serverEditorSecurityMode.
  ///
  /// In en, this message translates to:
  /// **'Security mode'**
  String get serverEditorSecurityMode;

  /// No description provided for @serverEditorFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint (uTLS)'**
  String get serverEditorFingerprint;

  /// No description provided for @serverEditorAlpn.
  ///
  /// In en, this message translates to:
  /// **'ALPN (comma-separated)'**
  String get serverEditorAlpn;

  /// No description provided for @serverEditorAllowInsecure.
  ///
  /// In en, this message translates to:
  /// **'Allow insecure certificate (insecure)'**
  String get serverEditorAllowInsecure;

  /// No description provided for @serverEditorPbk.
  ///
  /// In en, this message translates to:
  /// **'Public key (pbk)'**
  String get serverEditorPbk;

  /// No description provided for @serverEditorSid.
  ///
  /// In en, this message translates to:
  /// **'Short ID (sid)'**
  String get serverEditorSid;

  /// No description provided for @serverEditorSpx.
  ///
  /// In en, this message translates to:
  /// **'SpiderX (spx)'**
  String get serverEditorSpx;

  /// No description provided for @serverEditorTransportType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get serverEditorTransportType;

  /// No description provided for @serverEditorPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get serverEditorPath;

  /// No description provided for @serverEditorServiceName.
  ///
  /// In en, this message translates to:
  /// **'gRPC service name'**
  String get serverEditorServiceName;

  /// No description provided for @serverEditorMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get serverEditorMode;

  /// No description provided for @serverEditorHeaderType.
  ///
  /// In en, this message translates to:
  /// **'Header type'**
  String get serverEditorHeaderType;

  /// No description provided for @serverEditorAuth.
  ///
  /// In en, this message translates to:
  /// **'Auth password'**
  String get serverEditorAuth;

  /// No description provided for @serverEditorObfs.
  ///
  /// In en, this message translates to:
  /// **'Obfuscation (obfs)'**
  String get serverEditorObfs;

  /// No description provided for @serverEditorObfsPassword.
  ///
  /// In en, this message translates to:
  /// **'Obfuscation password'**
  String get serverEditorObfsPassword;

  /// No description provided for @serverEditorUp.
  ///
  /// In en, this message translates to:
  /// **'Upload, Mbps'**
  String get serverEditorUp;

  /// No description provided for @serverEditorDown.
  ///
  /// In en, this message translates to:
  /// **'Download, Mbps'**
  String get serverEditorDown;

  /// No description provided for @serverEditorMport.
  ///
  /// In en, this message translates to:
  /// **'Port hopping (mport)'**
  String get serverEditorMport;

  /// No description provided for @serverEditorHopInterval.
  ///
  /// In en, this message translates to:
  /// **'Hop interval, s'**
  String get serverEditorHopInterval;

  /// No description provided for @serverEditorPinSha256.
  ///
  /// In en, this message translates to:
  /// **'Certificate pinning (SHA-256)'**
  String get serverEditorPinSha256;

  /// No description provided for @serverEditorRawConfig.
  ///
  /// In en, this message translates to:
  /// **'Raw config'**
  String get serverEditorRawConfig;

  /// No description provided for @serverEditorRawToggle.
  ///
  /// In en, this message translates to:
  /// **'Edit as text'**
  String get serverEditorRawToggle;

  /// No description provided for @serverEditorRawOnlyNote.
  ///
  /// In en, this message translates to:
  /// **'This format is edited as raw text'**
  String get serverEditorRawOnlyNote;

  /// No description provided for @serverEditorPreview.
  ///
  /// In en, this message translates to:
  /// **'Resulting link'**
  String get serverEditorPreview;

  /// No description provided for @serverEditorSubscriptionNote.
  ///
  /// In en, this message translates to:
  /// **'This server comes from a subscription: your edits are kept when it refreshes.'**
  String get serverEditorSubscriptionNote;

  /// No description provided for @serverEditorOverriddenNote.
  ///
  /// In en, this message translates to:
  /// **'Config edited manually — subscription updates no longer replace it.'**
  String get serverEditorOverriddenNote;

  /// No description provided for @serverEditorRevert.
  ///
  /// In en, this message translates to:
  /// **'Restore subscription config'**
  String get serverEditorRevert;

  /// No description provided for @serverEditorSaved.
  ///
  /// In en, this message translates to:
  /// **'Configuration saved'**
  String get serverEditorSaved;

  /// No description provided for @serverEditorReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Configuration saved, reconnecting…'**
  String get serverEditorReconnecting;

  /// No description provided for @serverEditorInvalidPort.
  ///
  /// In en, this message translates to:
  /// **'Invalid port'**
  String get serverEditorInvalidPort;

  /// No description provided for @serverEditorServerMissing.
  ///
  /// In en, this message translates to:
  /// **'Server no longer exists'**
  String get serverEditorServerMissing;

  /// No description provided for @appearanceTabGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get appearanceTabGeneral;

  /// No description provided for @appearanceTabThemes.
  ///
  /// In en, this message translates to:
  /// **'Themes'**
  String get appearanceTabThemes;

  /// No description provided for @appearanceAmoled.
  ///
  /// In en, this message translates to:
  /// **'Pure black (AMOLED)'**
  String get appearanceAmoled;

  /// No description provided for @appearanceAmoledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'True black background in the dark theme — saves power on OLED screens'**
  String get appearanceAmoledSubtitle;

  /// No description provided for @appearanceAmoledNeedsDark.
  ///
  /// In en, this message translates to:
  /// **'Available with the dark theme on'**
  String get appearanceAmoledNeedsDark;

  /// No description provided for @appearanceHaptics.
  ///
  /// In en, this message translates to:
  /// **'Haptic feedback'**
  String get appearanceHaptics;

  /// No description provided for @appearanceHapticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Vibrate on connect, tab and server taps'**
  String get appearanceHapticsSubtitle;

  /// No description provided for @appearanceShowTraffic.
  ///
  /// In en, this message translates to:
  /// **'Show traffic'**
  String get appearanceShowTraffic;

  /// No description provided for @appearanceShowTrafficSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Speed and data usage chips under the connect button'**
  String get appearanceShowTrafficSubtitle;

  /// No description provided for @appearanceShowTime.
  ///
  /// In en, this message translates to:
  /// **'Show connection time'**
  String get appearanceShowTime;

  /// No description provided for @appearanceShowTimeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Session duration chip under the connect button'**
  String get appearanceShowTimeSubtitle;

  /// No description provided for @appearanceFontTitle.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get appearanceFontTitle;

  /// No description provided for @appearanceFontSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get appearanceFontSystem;

  /// No description provided for @settingsResetConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset settings?'**
  String get settingsResetConfirmTitle;

  /// No description provided for @settingsResetConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get settingsResetConfirmAction;

  /// No description provided for @settingsResetRoutingConfirm.
  ///
  /// In en, this message translates to:
  /// **'This restores the built-in routing rules and discards your direct/proxy/blocked lists. This can\'t be undone.'**
  String get settingsResetRoutingConfirm;

  /// No description provided for @settingsXrayResetConfirm.
  ///
  /// In en, this message translates to:
  /// **'This restores the default Xray core, TUN and local port settings. This can\'t be undone.'**
  String get settingsXrayResetConfirm;

  /// No description provided for @settingsPermissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get settingsPermissionsTitle;

  /// No description provided for @settingsPermissionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'App permissions you can review and revoke'**
  String get settingsPermissionsSubtitle;

  /// No description provided for @settingsPermNotifTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsPermNotifTitle;

  /// No description provided for @settingsPermNotifDesc.
  ///
  /// In en, this message translates to:
  /// **'VPN status bar and subscription-update alerts'**
  String get settingsPermNotifDesc;

  /// No description provided for @settingsPermStatusGranted.
  ///
  /// In en, this message translates to:
  /// **'Granted'**
  String get settingsPermStatusGranted;

  /// No description provided for @settingsPermStatusDenied.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get settingsPermStatusDenied;

  /// No description provided for @settingsPermCameraTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get settingsPermCameraTitle;

  /// No description provided for @settingsPermCameraDesc.
  ///
  /// In en, this message translates to:
  /// **'Scan config QR codes'**
  String get settingsPermCameraDesc;

  /// No description provided for @settingsPermInstallTitle.
  ///
  /// In en, this message translates to:
  /// **'Install apps'**
  String get settingsPermInstallTitle;

  /// No description provided for @settingsPermInstallDesc.
  ///
  /// In en, this message translates to:
  /// **'Install app updates'**
  String get settingsPermInstallDesc;

  /// No description provided for @settingsPermOpenAppSettings.
  ///
  /// In en, this message translates to:
  /// **'Open app settings'**
  String get settingsPermOpenAppSettings;

  /// No description provided for @settingsPermRevokeHint.
  ///
  /// In en, this message translates to:
  /// **'Revoke any permission in the system app settings.'**
  String get settingsPermRevokeHint;

  /// No description provided for @settingsPermTunHeader.
  ///
  /// In en, this message translates to:
  /// **'TUN MODE (LINUX)'**
  String get settingsPermTunHeader;

  /// No description provided for @settingsPermTunPasswordlessTitle.
  ///
  /// In en, this message translates to:
  /// **'Passwordless TUN'**
  String get settingsPermTunPasswordlessTitle;

  /// No description provided for @settingsPermTunPasswordlessSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start TUN mode without entering the polkit password each time'**
  String get settingsPermTunPasswordlessSubtitle;

  /// No description provided for @settingsPermTunDisabled.
  ///
  /// In en, this message translates to:
  /// **'Passwordless TUN disabled'**
  String get settingsPermTunDisabled;

  /// No description provided for @appearanceNotifSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'NOTIFICATION'**
  String get appearanceNotifSectionTitle;

  /// No description provided for @appearanceNotifSpeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection speed in notification'**
  String get appearanceNotifSpeedTitle;

  /// No description provided for @appearanceNotifSpeedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show ↓/↑ speed in the VPN status notification'**
  String get appearanceNotifSpeedSubtitle;

  /// No description provided for @appearanceNotifUptimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection time in notification'**
  String get appearanceNotifUptimeTitle;

  /// No description provided for @appearanceNotifUptimeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show session uptime in the VPN status notification'**
  String get appearanceNotifUptimeSubtitle;

  /// No description provided for @appearanceNotifSubUpdatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription update notifications'**
  String get appearanceNotifSubUpdatesTitle;

  /// No description provided for @appearanceNotifSubUpdatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Notify when subscriptions refresh in the background'**
  String get appearanceNotifSubUpdatesSubtitle;

  /// No description provided for @tunRememberTitle.
  ///
  /// In en, this message translates to:
  /// **'Remember authorization?'**
  String get tunRememberTitle;

  /// No description provided for @tunRememberMessage.
  ///
  /// In en, this message translates to:
  /// **'TUN mode needs root and asks for your password each time. Install a polkit rule so it starts without a password from now on? You\'ll be asked for your password once to install it.'**
  String get tunRememberMessage;

  /// No description provided for @tunRememberWarning.
  ///
  /// In en, this message translates to:
  /// **'After this, any program running as your user can start the VPN core as root without a password. You can undo it anytime in Advanced → Permissions.'**
  String get tunRememberWarning;

  /// No description provided for @tunRememberEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get tunRememberEnable;

  /// No description provided for @tunRememberNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get tunRememberNotNow;

  /// No description provided for @tunRememberInstalled.
  ///
  /// In en, this message translates to:
  /// **'Passwordless TUN enabled'**
  String get tunRememberInstalled;

  /// No description provided for @tunRememberFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change TUN authorization'**
  String get tunRememberFailed;

  /// No description provided for @settingsRoutingPresetTelegramGeoTitle.
  ///
  /// In en, this message translates to:
  /// **'Telegram (GeoIP+GeoSite) — Proxy'**
  String get settingsRoutingPresetTelegramGeoTitle;

  /// No description provided for @settingsRoutingPresetTelegramGeoDesc.
  ///
  /// In en, this message translates to:
  /// **'Telegram by domains and by IP ranges (MTProto uses bare IPs)'**
  String get settingsRoutingPresetTelegramGeoDesc;

  /// No description provided for @settingsRoutingPresetRefilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Blocked in Russia (Re-filter) — Proxy'**
  String get settingsRoutingPresetRefilterTitle;

  /// No description provided for @settingsRoutingPresetRefilterDesc.
  ///
  /// In en, this message translates to:
  /// **'Domains and IPs blocked in Russia go through the VPN, everything else stays direct'**
  String get settingsRoutingPresetRefilterDesc;

  /// No description provided for @settingsRoutingGeoUnknownTitle.
  ///
  /// In en, this message translates to:
  /// **'Missing from the geo databases — will be ignored'**
  String get settingsRoutingGeoUnknownTitle;

  /// No description provided for @settingsRoutingGeoUnknownHint.
  ///
  /// In en, this message translates to:
  /// **'The core aborts the whole config on an unknown geo code, so these entries are dropped before connecting. Pick an existing code with the globe button above.'**
  String get settingsRoutingGeoUnknownHint;

  /// No description provided for @settingsRoutingGeoPickerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Insert a geo code'**
  String get settingsRoutingGeoPickerTooltip;

  /// No description provided for @settingsRoutingGeoPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Geo codes in the bundled databases'**
  String get settingsRoutingGeoPickerTitle;

  /// No description provided for @settingsRoutingGeoPickerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search, e.g. telegram'**
  String get settingsRoutingGeoPickerSearchHint;

  /// No description provided for @settingsRoutingGeoPickerEmpty.
  ///
  /// In en, this message translates to:
  /// **'No codes match'**
  String get settingsRoutingGeoPickerEmpty;

  /// No description provided for @settingsRoutingGeoPickerGeosite.
  ///
  /// In en, this message translates to:
  /// **'Domains (geosite)'**
  String get settingsRoutingGeoPickerGeosite;

  /// No description provided for @settingsRoutingGeoPickerGeoip.
  ///
  /// In en, this message translates to:
  /// **'IP ranges (geoip)'**
  String get settingsRoutingGeoPickerGeoip;

  /// No description provided for @settingsOpenConnections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get settingsOpenConnections;

  /// No description provided for @settingsConnectionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get settingsConnectionsTitle;

  /// No description provided for @connectionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No connections captured yet.'**
  String get connectionsEmpty;

  /// No description provided for @connectionsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Connection list is unavailable.'**
  String get connectionsUnavailable;

  /// No description provided for @connectionsFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Filter by domain, IP, process or rule'**
  String get connectionsFilterHint;

  /// No description provided for @connectionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no connections} =1{1 connection} other{{count} connections}}'**
  String connectionsCount(int count);

  /// No description provided for @connectionsPause.
  ///
  /// In en, this message translates to:
  /// **'Pause updates'**
  String get connectionsPause;

  /// No description provided for @connectionsResume.
  ///
  /// In en, this message translates to:
  /// **'Resume updates'**
  String get connectionsResume;

  /// No description provided for @connectionsPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get connectionsPaused;

  /// No description provided for @connectionsSourceApi.
  ///
  /// In en, this message translates to:
  /// **'live from core'**
  String get connectionsSourceApi;

  /// No description provided for @connectionsSourceLog.
  ///
  /// In en, this message translates to:
  /// **'from core log'**
  String get connectionsSourceLog;

  /// No description provided for @connectionsSourceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'no source'**
  String get connectionsSourceUnavailable;

  /// No description provided for @connectionsRuleHint.
  ///
  /// In en, this message translates to:
  /// **'The core only logs which rule matched at log level Info.'**
  String get connectionsRuleHint;

  /// No description provided for @connectionsRuleHintAction.
  ///
  /// In en, this message translates to:
  /// **'Set Info'**
  String get connectionsRuleHintAction;

  /// No description provided for @connectionsRuleHintApplied.
  ///
  /// In en, this message translates to:
  /// **'Core log level set to Info — reconnect to apply'**
  String get connectionsRuleHintApplied;

  /// No description provided for @connectionsRuleDefault.
  ///
  /// In en, this message translates to:
  /// **'no rule (default action)'**
  String get connectionsRuleDefault;

  /// No description provided for @connectionsRuleViaCore.
  ///
  /// In en, this message translates to:
  /// **'decided inside the core (needs Info logs)'**
  String get connectionsRuleViaCore;

  /// No description provided for @connectionsVerdictCore.
  ///
  /// In en, this message translates to:
  /// **'CORE'**
  String get connectionsVerdictCore;

  /// No description provided for @connectionsVerdictProxy.
  ///
  /// In en, this message translates to:
  /// **'PROXY'**
  String get connectionsVerdictProxy;

  /// No description provided for @connectionsVerdictDirect.
  ///
  /// In en, this message translates to:
  /// **'DIRECT'**
  String get connectionsVerdictDirect;

  /// No description provided for @connectionsVerdictBlock.
  ///
  /// In en, this message translates to:
  /// **'BLOCKED'**
  String get connectionsVerdictBlock;

  /// No description provided for @connectionsClosed.
  ///
  /// In en, this message translates to:
  /// **'closed'**
  String get connectionsClosed;

  /// No description provided for @connectionsAppNamesHint.
  ///
  /// In en, this message translates to:
  /// **'App names appear after reconnecting: the tunnel starts its detailed log together with debug mode.'**
  String get connectionsAppNamesHint;

  /// No description provided for @connectionsSplitTunnelNote.
  ///
  /// In en, this message translates to:
  /// **'Apps kept out of the tunnel are not listed here: Android routes them past it, so their traffic never reaches the core.'**
  String get connectionsSplitTunnelNote;

  /// No description provided for @subscriptionsExpiredOn.
  ///
  /// In en, this message translates to:
  /// **'Subscription expired on {date}'**
  String subscriptionsExpiredOn(String date);

  /// No description provided for @subscriptionsExpiredHint.
  ///
  /// In en, this message translates to:
  /// **'The provider no longer updates the server list. Renew the subscription to keep it working.'**
  String get subscriptionsExpiredHint;

  /// No description provided for @subscriptionsExpiredNotifTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription expired'**
  String get subscriptionsExpiredNotifTitle;

  /// No description provided for @subscriptionsExpiredNotifBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" expired on {date}. The provider has stopped updating the server list — renew it to keep the servers working.'**
  String subscriptionsExpiredNotifBody(String name, String date);

  /// No description provided for @chainTitle.
  ///
  /// In en, this message translates to:
  /// **'Proxy chain'**
  String get chainTitle;

  /// No description provided for @chainNew.
  ///
  /// In en, this message translates to:
  /// **'New chain'**
  String get chainNew;

  /// No description provided for @chainCreate.
  ///
  /// In en, this message translates to:
  /// **'Build a chain'**
  String get chainCreate;

  /// No description provided for @chainCreateDesc.
  ///
  /// In en, this message translates to:
  /// **'Send traffic through several servers in a row'**
  String get chainCreateDesc;

  /// No description provided for @chainGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Chains'**
  String get chainGroupTitle;

  /// No description provided for @chainNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Chain name'**
  String get chainNameLabel;

  /// No description provided for @chainNameHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to name it by the route'**
  String get chainNameHint;

  /// No description provided for @chainHint.
  ///
  /// In en, this message translates to:
  /// **'Traffic goes top to bottom. The first node is the one this device connects to; the last one is the address sites see.'**
  String get chainHint;

  /// No description provided for @chainDeviceNode.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get chainDeviceNode;

  /// No description provided for @chainInternetNode.
  ///
  /// In en, this message translates to:
  /// **'Internet'**
  String get chainInternetNode;

  /// No description provided for @chainAddNode.
  ///
  /// In en, this message translates to:
  /// **'Add node'**
  String get chainAddNode;

  /// No description provided for @chainRemoveNode.
  ///
  /// In en, this message translates to:
  /// **'Remove node'**
  String get chainRemoveNode;

  /// No description provided for @chainExitNodeHint.
  ///
  /// In en, this message translates to:
  /// **'Exit node — sites see this address'**
  String get chainExitNodeHint;

  /// No description provided for @chainNodeMissing.
  ///
  /// In en, this message translates to:
  /// **'Server is gone — using the saved copy'**
  String get chainNodeMissing;

  /// No description provided for @chainSave.
  ///
  /// In en, this message translates to:
  /// **'Save chain'**
  String get chainSave;

  /// No description provided for @chainNeedsTwoNodes.
  ///
  /// In en, this message translates to:
  /// **'A chain needs at least two nodes'**
  String get chainNeedsTwoNodes;

  /// No description provided for @chainPickNode.
  ///
  /// In en, this message translates to:
  /// **'Choose a server'**
  String get chainPickNode;

  /// No description provided for @chainPickSearch.
  ///
  /// In en, this message translates to:
  /// **'Search servers'**
  String get chainPickSearch;

  /// No description provided for @chainPickEmpty.
  ///
  /// In en, this message translates to:
  /// **'No servers can be a chain node here. VLESS, VMess, Trojan, Shadowsocks and Hysteria2 work; AmneziaWG and ready-made JSON configs do not.'**
  String get chainPickEmpty;

  /// No description provided for @chainEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit chain'**
  String get chainEdit;

  /// No description provided for @chainDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate chain'**
  String get chainDuplicate;

  /// No description provided for @chainDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete chain'**
  String get chainDelete;

  /// No description provided for @chainRouteLabel.
  ///
  /// In en, this message translates to:
  /// **'Route'**
  String get chainRouteLabel;

  /// No description provided for @chainMaxNodes.
  ///
  /// In en, this message translates to:
  /// **'A chain holds at most {max} nodes'**
  String chainMaxNodes(int max);

  /// No description provided for @chainDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the chain \"{name}\"? The servers it uses stay in the list.'**
  String chainDeleteConfirm(String name);

  /// No description provided for @chainNodesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no nodes} =1{1 node} other{{count} nodes}}'**
  String chainNodesCount(int count);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['de', 'en', 'fa', 'ru', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de': return AppLocalizationsDe();
    case 'en': return AppLocalizationsEn();
    case 'fa': return AppLocalizationsFa();
    case 'ru': return AppLocalizationsRu();
    case 'zh': return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
