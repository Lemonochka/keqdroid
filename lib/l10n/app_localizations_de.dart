// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'KEQDIS';

  @override
  String vpnConnectedTo(Object serverName) {
    return 'Verbunden mit: $serverName';
  }

  @override
  String get vpnConnecting => 'Verbinden...';

  @override
  String get vpnDisconnecting => 'Trennen...';

  @override
  String vpnTapToConnect(Object serverName) {
    return 'Tippen, um mit $serverName zu verbinden';
  }

  @override
  String get vpnSelectServer => 'Wähle unten einen Server';

  @override
  String get vpnSelectServerFirst => 'Wähle zuerst einen Server';

  @override
  String get updateTitle => 'Update verfügbar';

  @override
  String get updateWhatsNew => 'Neuerungen:';

  @override
  String get updateActionLater => 'Später';

  @override
  String get updateActionNow => 'Aktualisieren';

  @override
  String get updateApplying => 'Update wird installiert...';

  @override
  String get errorSubscriptionTitle => 'Abonnement-Fehler';

  @override
  String get errorConnectionPermission =>
      'Verbindung fehlgeschlagen: Berechtigung';

  @override
  String get errorConnectionNetwork => 'Verbindung fehlgeschlagen: Netzwerk';

  @override
  String get errorConnectionConfig =>
      'Verbindung fehlgeschlagen: Konfiguration';

  @override
  String get errorConnectionAuth =>
      'Verbindung fehlgeschlagen: Authentifizierung';

  @override
  String get errorConnectionGeneric => 'Verbindungsfehler';

  @override
  String get errorProviderConfigTitle => 'Provider-Konfiguration erforderlich';

  @override
  String get errorProviderNoHostsMessage =>
      'Dem Provider sind für dieses Abonnement keine Hosts zugewiesen.';

  @override
  String get errorProviderNoHostsAction =>
      'Öffne das Provider-Panel, füge Hosts hinzu oder weise sie zu und aktualisiere dann das Abonnement.';

  @override
  String errorActionLabel(Object action) {
    return 'Aktion: $action';
  }

  @override
  String get splitTunnelingTitle => 'Split-Tunneling';

  @override
  String get splitModeAllApps => 'Alle Apps';

  @override
  String get splitModeSelectedOnly => 'Nur ausgewählte';

  @override
  String get splitModeAllExceptSelected => 'Alle außer ausgewählte';

  @override
  String get splitSearchHint => 'Apps suchen...';

  @override
  String get splitNoAppsFound => 'Keine Apps gefunden';

  @override
  String splitFailedLoadApps(Object error) {
    return 'Apps konnten nicht geladen werden: $error';
  }

  @override
  String splitSelectedAppsCount(int count) {
    return '$count App(s) ausgewählt';
  }

  @override
  String get splitHideSystemApps => 'System-Apps ausblenden';

  @override
  String get splitShowSystemApps => 'System-Apps anzeigen';

  @override
  String get splitAddRussianAppsBypass =>
      'Russische Apps zum Umgehen hinzufügen';

  @override
  String get splitClear => 'Löschen';

  @override
  String get splitNoRussianAppsFound =>
      'Keine russischen Apps in der Liste der installierten Apps gefunden';

  @override
  String get splitRussianAppsAlreadyAdded =>
      'Alle russischen Apps sind bereits in der Umgehungsliste';

  @override
  String splitAddedRussianApps(int count) {
    return '$count russische App(s) zur Umgehungsliste hinzugefügt';
  }

  @override
  String get navServers => 'Server';

  @override
  String get navSubscriptions => 'Abonnements';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get serversEmptyTitle => 'Noch keine Server';

  @override
  String get serversEmptyHint => 'Füge im Tab Abonnements ein Abonnement hinzu';

  @override
  String get subscriptionsTitle => 'Abonnements';

  @override
  String get subscriptionsAddButton => 'Abonnement hinzufügen';

  @override
  String get subscriptionsEmptyTitle => 'Keine Abonnements';

  @override
  String get subscriptionsEmptyHint =>
      'Tippe auf +, um eine Abonnement-URL hinzuzufügen';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsThemeTitle => 'Design';

  @override
  String get settingsSplitTitle => 'Split-Tunneling';

  @override
  String get settingsRoutingTitle => 'Routing-Regeln';

  @override
  String settingsSplitConfigured(int count) {
    return '$count Apps konfiguriert';
  }

  @override
  String get settingsRoutingSubtitle =>
      'Direct- / Proxy- / Block-Regeln und Presets';

  @override
  String get settingsResetRoutingTitle => 'Routing auf Standard zurücksetzen';

  @override
  String get settingsResetRoutingSubtitle =>
      'Integrierte Routing-Regeln wiederherstellen';

  @override
  String get settingsRoutingResetDone => 'Routing-Regeln zurückgesetzt';

  @override
  String get settingsRoutingHeaderDesc =>
      'Lege fest, welche Seiten direkt am VPN vorbei gehen, welche zwingend hindurch geleitet und welche blockiert werden. Beginne mit einem Preset und passe dann jede Liste unten an.';

  @override
  String get settingsRoutingPresetsTitle => 'Schnelle Presets';

  @override
  String get settingsRoutingPresetsHint =>
      'Tippen, um eine kuratierte Liste hinzuzufügen. Einträge können danach bearbeitet oder entfernt werden.';

  @override
  String get settingsRoutingPresetRuTitle => 'Russische Seiten — Direkt';

  @override
  String get settingsRoutingPresetRuDesc =>
      'Alle .ru / .рф und großen RU-Dienste umgehen das VPN';

  @override
  String get settingsRoutingPresetBanksTitle => 'Banken & Behörden — Direkt';

  @override
  String get settingsRoutingPresetBanksDesc =>
      'Banken, Zahlungen und Behördenportale umgehen das VPN';

  @override
  String get settingsRoutingPresetAdsTitle => 'Werbung & Tracker — Blockieren';

  @override
  String get settingsRoutingPresetAdsDesc =>
      'Gängige Werbe-/Analyse-Hosts verwerfen';

  @override
  String get settingsRoutingPresetStreamingTitle => 'Streaming — Proxy';

  @override
  String get settingsRoutingPresetStreamingDesc =>
      'YouTube, Netflix, Twitch zwingend über das VPN';

  @override
  String get settingsRoutingPresetMessengersTitle => 'Messenger — Proxy';

  @override
  String get settingsRoutingPresetMessengersDesc =>
      'Telegram, Discord, WhatsApp zwingend über das VPN';

  @override
  String settingsRoutingPresetApplied(String name) {
    return '\"$name\" hinzugefügt';
  }

  @override
  String get settingsRoutingDirectTitle => 'Direkte Domains (VPN umgehen)';

  @override
  String get settingsRoutingDirectDesc =>
      'Diese Hosts verbinden sich direkt, ohne VPN.';

  @override
  String get settingsRoutingProxyTitle => 'Proxy-Domains (VPN erzwingen)';

  @override
  String get settingsRoutingProxyDesc =>
      'Diese Hosts gehen immer über das VPN.';

  @override
  String get settingsRoutingBlockTitle => 'Blockierte Domains';

  @override
  String get settingsRoutingBlockDesc =>
      'Diese Hosts werden verworfen und verbinden nie.';

  @override
  String get settingsRoutingDirectIpsTitle =>
      'Direkte IPs / Subnetze (VPN umgehen)';

  @override
  String get settingsRoutingDirectIpsDesc =>
      'IPv4/IPv6-Adressen oder CIDR-Bereiche, die das VPN umgehen.';

  @override
  String get settingsRoutingValuesHint =>
      'Eine pro Zeile oder durch Komma getrennt';

  @override
  String get settingsRoutingSavedToast => 'Routing aktualisiert';

  @override
  String settingsRoutingItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge',
      one: '1 Eintrag',
      zero: 'leer',
    );
    return '$_temp0';
  }

  @override
  String settingsAndroidColorsSubtitle(Object mode) {
    return 'Android-Farben · $mode';
  }

  @override
  String settingsSystemColorsSubtitle(Object mode) {
    return 'Systemfarben · $mode';
  }

  @override
  String get themeModeDark => 'Dunkel';

  @override
  String get themeModeLight => 'Hell';

  @override
  String get themeCustomizationTitle => 'Design anpassen';

  @override
  String get themeUseDynamicColors => 'Dynamische Android-Farben verwenden';

  @override
  String get themeUseDynamicColorsSubtitle =>
      'Dynamische Android-Farben verwenden, wenn verfügbar';

  @override
  String get themeDynamicPaletteHint =>
      'Die dynamische Android-Palette ist aktiv. Hell/Dunkel funktioniert unabhängig.';

  @override
  String get themeSystemPaletteHint =>
      'Die System-Akzentpalette ist aktiv. Hell/Dunkel funktioniert unabhängig.';

  @override
  String get themeUseSystemColors => 'System-Akzentfarben verwenden';

  @override
  String get themeUseSystemColorsSubtitle =>
      'Akzentfarben von Windows oder Linux übernehmen, wenn verfügbar';

  @override
  String get themeCustomPaletteHint =>
      'Die benutzerdefinierte Palette ist aktiv. Hell/Dunkel funktioniert unabhängig.';

  @override
  String get themeColorThemesTitle => 'Farbthemen';

  @override
  String get settingsLanProxyTitle => 'LAN-Proxy';

  @override
  String get settingsOff => 'Aus';

  @override
  String settingsLanSharingOnIp(Object ip) {
    return 'Freigabe auf $ip';
  }

  @override
  String get settingsHwidTitle => 'Geräte-HWID senden';

  @override
  String get settingsHwidEnabledRecommended => 'Aktiviert (empfohlen)';

  @override
  String get settingsHwidDisabled => 'Deaktiviert';

  @override
  String get settingsHwidEnabledHint =>
      'Einige Provider benötigen die HWID für Abonnement-Updates und Gerätelimits.';

  @override
  String get settingsHwidDisabledHint =>
      'HWID-Header werden nicht gesendet. Manche Abonnements schlagen fehl, wenn der Provider eine Gerätebindung verlangt.';

  @override
  String get settingsDeviceIpListTitle => 'IP-Adressen des Geräts im Netzwerk:';

  @override
  String get settingsIpCopied => 'IP kopiert';

  @override
  String get settingsSetupAnotherDeviceTitle =>
      'Einrichtung auf einem anderen Gerät:';

  @override
  String get settingsSocks5PortLabel => 'SOCKS5-Port';

  @override
  String get settingsHttpPortLabel => 'HTTP-Port';

  @override
  String get settingsTurnOffToChange =>
      'Zum Ändern der Einstellung ausschalten';

  @override
  String settingsProxyCopied(Object label, Object address) {
    return '$label $address kopiert';
  }

  @override
  String get settingsXrayCoreTitle => 'Xray-Kern';

  @override
  String get settingsXrayCoreSubtitle => 'DNS, XMUX, Log und Routing';

  @override
  String get settingsXrayDnsSection => 'DNS';

  @override
  String get settingsXrayDnsCustom => 'Eigene DNS-Server';

  @override
  String get settingsXrayDnsCustomHint =>
      'Eine Adresse pro Zeile (DoH, DoT oder einfach)';

  @override
  String get settingsXrayDnsServers => 'DNS-Server';

  @override
  String get settingsXrayDnsSplitDirect =>
      'Getrennter Resolver für Direct-Domains';

  @override
  String get settingsXrayDnsSplitDirectHint =>
      'Verwendet den ersten Server für Domains aus der Direct-Liste';

  @override
  String get settingsXrayDnsQueryStrategy => 'Abfragestrategie';

  @override
  String get settingsXrayDnsDisableCache => 'DNS-Cache deaktivieren';

  @override
  String get settingsXrayXmuxSection => 'XMUX (XHTTP)';

  @override
  String get settingsXrayXmuxEnable => 'XMUX aktivieren';

  @override
  String get settingsXrayXmuxEnableHint =>
      'Multiplexing für den XHTTP-Transport (clientseitig)';

  @override
  String get settingsXrayGeneralSection => 'Allgemein';

  @override
  String get settingsXrayLogLevel => 'Log-Level';

  @override
  String get settingsXrayDomainStrategy => 'Routing-Domainstrategie';

  @override
  String get settingsXraySniffing => 'Inbound-Sniffing';

  @override
  String get settingsXraySniffingRouteOnly => 'Sniffing nur für Routing';

  @override
  String get settingsXrayCoreIntro =>
      'Diese Optionen werden in die generierte Xray-Konfiguration eingefügt. Ändere sie nur, wenn du weißt, was sie bewirken.';

  @override
  String get settingsXrayDnsDefaultNote =>
      'Standard: Cloudflare und Google DoH';

  @override
  String get settingsXrayXmuxParamsTitle => 'Feineinstellung';

  @override
  String get settingsXrayXmuxParamsHint =>
      'Leer lassen, um die Xray-Standardwerte zu verwenden. Werte können eine Zahl oder ein Bereich sein (z. B. 16-32).';

  @override
  String get settingsXraySniffingHint =>
      'Zielprotokoll und Domain aus dem eingehenden Verkehr erkennen';

  @override
  String get settingsXraySniffingRouteOnlyHint =>
      'Sniffing nur für das Routing nutzen, ohne das Ziel zu überschreiben';

  @override
  String get settingsXrayResetDefaults => 'Auf Standard zurücksetzen';

  @override
  String get settingsXrayResetDone =>
      'Xray-Kerneinstellungen wiederhergestellt';

  @override
  String get settingsXrayXmuxMaxConcurrency => 'Max. Parallelität';

  @override
  String get settingsXrayXmuxMaxConnections => 'Max. Verbindungen';

  @override
  String get settingsXrayXmuxCMaxReuseTimes =>
      'Limit für Verbindungs-Wiederverwendung';

  @override
  String get settingsXrayXmuxHMaxRequestTimes => 'Max. Anfragen pro Stream';

  @override
  String get settingsXrayXmuxHMaxReusableSecs =>
      'Stream-Wiederverwendungszeit (Sek.)';

  @override
  String get settingsXrayXmuxHKeepAlivePeriod => 'Keep-Alive-Intervall (Sek.)';

  @override
  String get settingsPingTitle => 'Server-Ping';

  @override
  String get settingsPingMethodTitle => 'Ping-Methode';

  @override
  String get settingsPingMethodTcp => 'TCP-Ping';

  @override
  String get settingsPingMethodTcpHint => 'Schnelle Erreichbarkeitsprüfung';

  @override
  String get settingsPingMethodUrl => 'HTTP über Proxy';

  @override
  String get settingsPingMethodUrlHint =>
      'Misst die GET-Latenz über den Server';

  @override
  String get settingsPingMethodSpeed => 'Geschwindigkeitstest';

  @override
  String get settingsPingMethodSpeedHint =>
      'Lädt eine feste Datenmenge über den Server herunter und zeigt den Durchsatz in Mbit/s an (funktioniert ohne VPN)';

  @override
  String get settingsPingTargetTitle => 'HTTP-Test-URL';

  @override
  String get settingsPingTargetGstatic => 'Google (generate_204)';

  @override
  String get settingsPingTargetCloudflare => 'Cloudflare (trace)';

  @override
  String get settingsPingTargetMicrosoft => 'Microsoft (connect test)';

  @override
  String get settingsPingTargetCustom => 'Eigene URL';

  @override
  String get settingsPingCustomUrl => 'URL';

  @override
  String get settingsPingCustomUrlHint =>
      'https:// oder http:// Adresse für die GET-Anfrage';

  @override
  String get settingsPingCustomUrlInvalid =>
      'Ungültige oder unsichere URL (kein localhost oder private Netzwerke)';

  @override
  String get subscriptionNameLabel => 'Name';

  @override
  String get subscriptionNameHint => 'Mein Abonnement';

  @override
  String get subscriptionUrlLabel => 'URL';

  @override
  String get subscriptionUrlHint => 'https://example.com/sub?token=...';

  @override
  String get subscriptionsAddSubscription => 'Abonnement hinzufügen';

  @override
  String get subscriptionsAddAndFetch => 'Hinzufügen & abrufen';

  @override
  String get subscriptionsEditSubscription => 'Abonnement bearbeiten';

  @override
  String get subscriptionsCopyUrl => 'URL kopieren';

  @override
  String get subscriptionsUrlCopied => 'URL kopiert';

  @override
  String get subscriptionsDeleteSubscription => 'Abonnement löschen';

  @override
  String subscriptionsDeleteConfirm(Object name) {
    return 'Möchtest du \"$name\" wirklich löschen?\n\nDadurch werden auch alle zugehörigen Server entfernt.';
  }

  @override
  String get subscriptionsRetry => 'Erneut versuchen';

  @override
  String get subscriptionsCancel => 'Abbrechen';

  @override
  String get subscriptionsDelete => 'Löschen';

  @override
  String get subscriptionsSave => 'Speichern';

  @override
  String get subscriptionsMoveUp => 'Nach oben';

  @override
  String get subscriptionsMoveDown => 'Nach unten';

  @override
  String get subscriptionsAutoUpdate => 'Automatische Aktualisierung';

  @override
  String get subscriptionsOn => 'EIN';

  @override
  String get subscriptionsOff => 'AUS';

  @override
  String get subscriptionsExpired => 'Abgelaufen';

  @override
  String get subscriptionsRefreshFailed => 'Aktualisierung fehlgeschlagen';

  @override
  String get subscriptionsEveryHour => 'Jede Stunde';

  @override
  String subscriptionsEveryHours(int hours) {
    return 'Alle $hours Stunden';
  }

  @override
  String get subscriptionsEveryDay => 'Täglich';

  @override
  String subscriptionsEveryDays(int days) {
    return 'Alle $days Tage';
  }

  @override
  String get subscriptionsAutoUpdateInterval => 'Aktualisierungsintervall';

  @override
  String subscriptionsCurrentInterval(int hours) {
    return 'alle $hours Std.';
  }

  @override
  String get subscriptionsJustNow => 'gerade eben';

  @override
  String subscriptionsMinutesAgo(int minutes) {
    return 'vor $minutes Min.';
  }

  @override
  String subscriptionsHoursAgo(int hours) {
    return 'vor $hours Std.';
  }

  @override
  String subscriptionsDaysAgo(int days) {
    return 'vor $days T.';
  }

  @override
  String subscriptionsInDays(int days) {
    return 'in $days T.';
  }

  @override
  String subscriptionsInHours(int hours) {
    return 'in $hours Std.';
  }

  @override
  String get subscriptionsSoon => 'bald';

  @override
  String get serversAddServer => 'Server hinzufügen';

  @override
  String get serversPasteLinks => 'Link(s) einfügen';

  @override
  String get serversImportFile => 'Datei importieren';

  @override
  String get serversNotSupported => 'In diesem Build nicht unterstützt';

  @override
  String get serversAddServerTitle => 'Server hinzufügen';

  @override
  String get serversPasteVlessHint =>
      'Füge vless://, vmess://, trojan://, ss://, hysteria2:// oder hy2:// ein (eine pro Zeile)';

  @override
  String get serversPasteHint => 'vless://… oder hy2://host:port?auth=…';

  @override
  String get serversAdd => 'Hinzufügen';

  @override
  String get serversManualServers => 'Manuelle Server';

  @override
  String get serversRefreshSubscription => 'Abonnement aktualisieren';

  @override
  String get serversPingAll => 'Alle anpingen';

  @override
  String get settingsAdvanced => 'Erweitert';

  @override
  String get settingsAdvancedSubtitle =>
      'Kerneinstellungen, Ping, Routing, HWID und Debug';

  @override
  String get settingsBackupRestore => 'Sichern & wiederherstellen';

  @override
  String get settingsBackupRestoreSubtitle =>
      'Split-Tunneling, Abonnements und Server exportieren/importieren';

  @override
  String get settingsSelectAtLeastOne =>
      'Wähle mindestens einen Abschnitt zum Exportieren';

  @override
  String get settingsBackupSaved => 'Sicherung erfolgreich gespeichert';

  @override
  String get settingsSelectLocation => 'Speicherort für die Sicherung wählen';

  @override
  String get settingsExportFile => 'Datei exportieren';

  @override
  String get settingsImportFile => 'Aus Datei importieren';

  @override
  String get settingsImportBackup => 'Sicherung importieren';

  @override
  String get settingsChooseWhatToImport =>
      'Wähle, was importiert werden soll (ausgewählte Abschnitte ersetzen deine aktuellen Daten).';

  @override
  String get settingsSplitTunnelingApps => 'Split-Tunneling-Apps';

  @override
  String get settingsSubscriptions => 'Abonnements';

  @override
  String get settingsServersActive => 'Server (und aktiver Server)';

  @override
  String get settingsImport => 'Importieren';

  @override
  String get settingsExport => 'Exportieren';

  @override
  String get settingsCreateFileToSave =>
      'Erstelle eine Datei, die du speichern und auf einem anderen Gerät importieren kannst.';

  @override
  String get settingsPickExportedFile =>
      'Wähle eine zuvor exportierte Datei und stelle ausgewählte Abschnitte wieder her.';

  @override
  String get settingsWorking => 'Wird ausgeführt...';

  @override
  String settingsImportedSections(int count) {
    return 'Importiert: $count Abschnitt(e)';
  }

  @override
  String get settingsDebugMode => 'Debug-Modus';

  @override
  String get settingsDebugModeOn => 'Erweiterte Diagnose aktiviert';

  @override
  String get settingsDebugModeOff => 'Aus';

  @override
  String get settingsDebugModeHint =>
      'Zeigt Live-VPN-Metriken in Serverkarten an und ermöglicht das Anzeigen der Xray-Kern-Logs.';

  @override
  String get settingsOpenXrayLogs => 'Xray-Logs öffnen';

  @override
  String get settingsXrayCoreLogs => 'Xray-Kern-Logs';

  @override
  String get settingsRefresh => 'Aktualisieren';

  @override
  String get settingsAppVersion => 'App-Version';

  @override
  String get settingsChecking => 'Wird geprüft...';

  @override
  String get settingsCheckFailed => 'Prüfung fehlgeschlagen';

  @override
  String get settingsUpdateAvailable => 'Update verfügbar';

  @override
  String get settingsUpToDate => 'Aktuell';

  @override
  String get settingsNewVersionAvailable => 'Neue Version verfügbar';

  @override
  String settingsSize(Object size) {
    return 'Größe: $size';
  }

  @override
  String get settingsDownloading => 'Wird heruntergeladen...';

  @override
  String get settingsCheckForUpdates => 'Nach Updates suchen';

  @override
  String get settingsShareDeviceHwid => 'Geräte-HWID teilen';

  @override
  String get settingsHwidWillBeSent =>
      'Die HWID wird mit Abonnement-Anfragen gesendet';

  @override
  String get settingsHwidNotShared => 'HWID wird nicht geteilt';

  @override
  String get settingsHwidHint =>
      'Wenn aktiviert, wird die eindeutige ID deines Geräts (HWID) an Abonnement-Server gesendet. Von manchen Providern für die HWID-Bindung erforderlich. Deaktivieren, um die Privatsphäre zu erhöhen.';

  @override
  String get settingsRoutingRules => 'Routing-Regeln';

  @override
  String get settingsNoRules => 'Keine Regeln';

  @override
  String get settingsAddCustomRule => 'Eigene Regel hinzufügen';

  @override
  String get settingsAddRule => 'Regel hinzufügen';

  @override
  String get settingsEditRule => 'Routing-Regel bearbeiten';

  @override
  String get settingsRuleName => 'Regelname';

  @override
  String get settingsType => 'Typ';

  @override
  String get settingsAction => 'Aktion';

  @override
  String get settingsValues => 'Werte (was zutreffen soll)';

  @override
  String get settingsOrder => 'Reihenfolge (Regelpriorität)';

  @override
  String get settingsEnabled => 'Aktiviert';

  @override
  String get settingsNameAndValuesRequired =>
      'Name und Werte sind erforderlich';

  @override
  String get settingsUseOnePerLine =>
      'Verwende einen Wert pro Zeile oder trenne sie durch Kommas.';

  @override
  String get settingsSmallerOrderFirst =>
      'Kleinere Zahl = früher geprüft (z. B. 1 vor 50)';

  @override
  String get settingsSmallerOrderWins =>
      'Wenn zwei Regeln denselben Verkehr betreffen, gewinnt die Regel mit der kleineren Reihenfolge.';

  @override
  String get settingsSaveChanges => 'Änderungen speichern';

  @override
  String get settingsDeleteRule => 'Regel löschen';

  @override
  String get settingsAddRuleTooltip => 'Regel hinzufügen';

  @override
  String get settingsDomain => 'Domain';

  @override
  String get settingsIpCidr => 'IP CIDR';

  @override
  String get settingsGeoIp => 'GeoIP';

  @override
  String get settingsGeosite => 'Geosite';

  @override
  String get settingsProcess => 'Prozess';

  @override
  String get settingsProxy => 'Proxy';

  @override
  String get settingsDirect => 'Direkt';

  @override
  String get settingsBlock => 'Blockieren';

  @override
  String get settingsEgDomain => 'z. B. youtube.com, +google';

  @override
  String get settingsEgIpCidr => 'z. B. 1.1.1.1/32, 192.168.0.0/16';

  @override
  String get settingsEgGeoip => 'z. B. RU, US, DE';

  @override
  String get settingsEgGeosite => 'z. B. category-ads-all';

  @override
  String get settingsEgProcess => 'z. B. com.telegram.messenger';

  @override
  String settingsExportFailed(Object error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String settingsImportFailed(Object error) {
    return 'Import fehlgeschlagen: $error';
  }

  @override
  String settingsDownloadFailed(Object error) {
    return 'Download fehlgeschlagen: $error';
  }

  @override
  String settingsCheckFailedError(Object error) {
    return 'Prüfung fehlgeschlagen: $error';
  }

  @override
  String get settingsNoXrayLogsYet => 'Noch keine Xray-Logs';

  @override
  String get settingsLanguageTitle => 'Sprache';

  @override
  String settingsLanguageSubtitle(Object language) {
    return '$language';
  }

  @override
  String get settingsLanguageSystem => 'Systemstandard';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageGerman => 'Deutsch';

  @override
  String get settingsLanguageChinese => '中文';

  @override
  String get settingsLanguageSheetTitle => 'Sprache wählen';

  @override
  String get splitAddApp => 'App hinzufügen';

  @override
  String get splitAddAppTitle => 'Anwendung hinzufügen';

  @override
  String get splitAddAppHint => 'Pfad zur .exe oder Name (z. B. chrome.exe)';

  @override
  String get splitAddAppPickFile => 'Durchsuchen…';

  @override
  String get splitAddAppInvalid =>
      'Gib einen gültigen .exe-Namen oder Pfad ein';

  @override
  String splitAddAppAdded(Object name) {
    return 'Hinzugefügt: $name';
  }

  @override
  String get splitRunningApps => 'Laufend';

  @override
  String get splitInstalledApps => 'Installiert';

  @override
  String get splitCustomApps => 'Manuelle Einträge';

  @override
  String get splitClearAll => 'Alle löschen';

  @override
  String get splitProxyModeWarning =>
      'Im Proxy-Modus wird Split-Tunneling nicht angewendet — der gesamte Verkehr läuft über den System-Proxy. Wechsle den Verbindungsmodus auf TUN (im Seitenpanel), damit die Regeln pro Prozess wirken.';

  @override
  String get settingsLatestVersionInstalled => 'Du hast die neueste Version';

  @override
  String get serversPingServer => 'Server anpingen';

  @override
  String get serversHealthCheck => 'Funktionsprüfung';

  @override
  String get serversCopyAddress => 'Serveradresse kopieren';

  @override
  String get serversCopiedToClipboard => 'In die Zwischenablage kopiert';

  @override
  String get serversCopyConfig => 'Konfiguration kopieren';

  @override
  String get serversConfigCopied => 'Konfiguration kopiert';

  @override
  String get serversDeleteServer => 'Server löschen';

  @override
  String get serversHealthCheckDesc => 'DNS-, TCP- und Konfigurationsprüfung';

  @override
  String get settingsDebugHintDesktop =>
      'Zeigt Xray-Sitzungslogs an. Live-VPN-Metriken werden unter der Verbindungstaste angezeigt.';

  @override
  String get settingsDebugHintMobile =>
      'Zeigt Live-VPN-Metriken in Serverkarten und Xray-Logs an.';

  @override
  String serversErrorLoadingApps(Object error) {
    return 'Fehler beim Laden der Apps: $error';
  }

  @override
  String get desktopConnectionMode => 'Verbindungsmodus';

  @override
  String get desktopModeShort => 'Modus';

  @override
  String get desktopDisconnectBeforeModeChange =>
      'Trenne die Verbindung, bevor du den Verbindungsmodus änderst';

  @override
  String get settingsDesktopTitle => 'Windows';

  @override
  String get settingsDesktopSubtitle => 'Tray, Autostart, Auto-Connect';

  @override
  String get settingsMinimizeToTray => 'Beim Schließen in Tray minimieren';

  @override
  String get settingsMinimizeToTrayHint =>
      'Wenn aus, beendet Schließen die App';

  @override
  String get settingsLaunchAtStartup => 'Mit Windows starten';

  @override
  String get settingsLaunchAtStartupHint => 'App beim Anmelden starten';

  @override
  String get settingsAutoConnectOnAutostart => 'Bei Autostart verbinden';

  @override
  String get settingsAutoConnectOnAutostartHint =>
      'Verbindet mit dem zuletzt gewählten Server im Modus der Seitenleiste. Ohne Admin-Rechte für TUN wird Proxy verwendet';

  @override
  String get settingsAutoConnectRequiresAutostart =>
      'Zuerst „Mit Windows starten“ aktivieren';

  @override
  String get desktopTunAdminTitle => 'Administratorrechte erforderlich';

  @override
  String get desktopTunAdminMessage =>
      'Der TUN-Modus benötigt Administratorrechte. Starten Sie die App als Administrator neu — der Modus in der Seitenleiste bleibt erhalten.';

  @override
  String get desktopTunAdminRestart => 'Als Administrator neu starten';

  @override
  String get desktopTunAdminCancel => 'Abbrechen';

  @override
  String get desktopTunAdminRestartFailed =>
      'Neustart als Administrator fehlgeschlagen';

  @override
  String get trayMenuTitle => 'KeqDroid';

  @override
  String get trayCloseMenu => 'Menü schließen';

  @override
  String get trayConnect => 'Verbinden';

  @override
  String get trayDisconnect => 'Trennen';

  @override
  String get trayOpenApp => 'App öffnen';

  @override
  String get trayExit => 'Beenden';

  @override
  String get trayServersSection => 'Server';

  @override
  String get trayPickServer => 'Server wählen…';

  @override
  String get trayModeProxy => 'Proxy';

  @override
  String get trayModeTun => 'TUN';

  @override
  String get trayStatusConnected => 'Verbunden';

  @override
  String get trayStatusDisconnected => 'Getrennt';

  @override
  String get trayStatusError => 'Fehler';
}
