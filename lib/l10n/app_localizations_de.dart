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
  String get vpnConnecting => 'Verbinden…';

  @override
  String get vpnDisconnecting => 'Wird getrennt…';

  @override
  String vpnTapToConnect(Object serverName) {
    return 'Tippe, um dich mit $serverName zu verbinden';
  }

  @override
  String get vpnSelectServer => 'Wähle unten einen Server aus';

  @override
  String get vpnSelectServerFirst => 'Wähle zuerst einen Server aus';

  @override
  String get updateTitle => 'Update verfügbar';

  @override
  String get updateWhatsNew => 'Neuerungen:';

  @override
  String get updateActionLater => 'Später';

  @override
  String get updateActionNow => 'Aktualisieren';

  @override
  String get updateApplying => 'Update wird installiert…';

  @override
  String get errorSubscriptionTitle => 'Abonnementfehler';

  @override
  String get errorConnectionPermission => 'Verbindung fehlgeschlagen: Berechtigung';

  @override
  String get errorConnectionNetwork => 'Verbindung fehlgeschlagen: Netzwerk';

  @override
  String get errorConnectionConfig => 'Verbindung fehlgeschlagen: Konfiguration';

  @override
  String get errorConnectionAuth => 'Verbindung fehlgeschlagen: Authentifizierung';

  @override
  String get errorConnectionGeneric => 'Verbindungsfehler';

  @override
  String get errorProviderConfigTitle => 'Einrichtung beim Anbieter erforderlich';

  @override
  String get errorProviderNoHostsMessage => 'Der Anbieter hat diesem Abonnement keine Hosts zugewiesen.';

  @override
  String get errorProviderNoHostsAction => 'Öffne das Panel des Anbieters, füge Hosts hinzu oder weise sie zu und aktualisiere dann das Abonnement.';

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
  String get splitModeAllExceptSelected => 'Alle außer ausgewählten';

  @override
  String get splitSearchHint => 'Apps suchen…';

  @override
  String get splitNoAppsFound => 'Keine Apps gefunden';

  @override
  String splitFailedLoadApps(Object error) {
    return 'Apps konnten nicht geladen werden: $error';
  }

  @override
  String splitSelectedAppsCount(int count) {
    return 'Ausgewählte Apps: $count';
  }

  @override
  String get splitHideSystemApps => 'System-Apps ausblenden';

  @override
  String get splitShowSystemApps => 'System-Apps anzeigen';

  @override
  String get splitAddRussianAppsBypass => 'Russische Apps vom VPN ausschließen';

  @override
  String get splitClear => 'Leeren';

  @override
  String get splitNoRussianAppsFound => 'Keine russischen Apps in der Liste der installierten Apps gefunden';

  @override
  String get splitRussianAppsAlreadyAdded => 'Alle russischen Apps sind bereits ausgeschlossen';

  @override
  String splitAddedRussianApps(int count) {
    return 'Russische Apps ausgeschlossen: $count';
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
  String get serversEmptyHint => 'Füge auf dem Tab „Abonnements“ ein Abonnement hinzu';

  @override
  String get subscriptionsTitle => 'Abonnements';

  @override
  String get subscriptionsAddButton => 'Abonnement hinzufügen';

  @override
  String get subscriptionsEmptyTitle => 'Keine Abonnements';

  @override
  String get subscriptionsEmptyHint => 'Tippe auf +, um eine Abonnement-URL hinzuzufügen';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsThemeTitle => 'Erscheinungsbild';

  @override
  String get settingsSplitTitle => 'Split-Tunneling';

  @override
  String get settingsRoutingTitle => 'Routing';

  @override
  String settingsSplitConfigured(int count) {
    return '$count Apps konfiguriert';
  }

  @override
  String get settingsRoutingPresetsTitle => 'Fertige Listen';

  @override
  String get settingsRoutingPresetRuTitle => 'Russische Websites';

  @override
  String get settingsRoutingPresetIrTitle => 'Iranische Websites';

  @override
  String get settingsRoutingPresetAdsTitle => 'Werbung und Tracker';

  @override
  String get settingsRoutingDirectTitle => 'Direkt';

  @override
  String get settingsRoutingProxyTitle => 'Über das VPN';

  @override
  String get settingsRoutingBlockTitle => 'Blockieren';

  @override
  String get settingsRoutingFinalTitle => 'Alles andere';

  @override
  String get settingsRoutingReconnect => 'Neu verbinden';

  @override
  String get routingCheatSheetTitle => 'So schreibst du Regeln';

  @override
  String get routingCheatSheetBody => 'Eine Route liest sich „wer → was → wohin“. Unter „Eigene Websites“ ist jede Zeile eine Domain, eine IP, ein Geo-Tag oder ein Link zu einer Liste; wohin sie gehen, wählt die Route selbst: direkt, über das VPN oder blockiert.\n\n## Domains\nvk.com – die Domain selbst und alle ihre Subdomains\nru – alles, was auf .ru endet (nur das Wort, ohne Punkt)\n.example.com – nur Subdomains, nicht die Domain selbst\nfull:example.com – genau dieser Host, ohne Subdomains\nregexp:… – ein regulärer Ausdruck, falls es wirklich knifflig wird\n\n## IP-Adressen\n1.2.3.4 – eine einzelne Adresse\n10.0.0.0/8 – ein ganzer Bereich (CIDR)\n\n## GeoIP: nach Land\ngeoip:ru – alle russischen IPs. Statt ru geht jedes Land: us, de, cn, ua, kz…\nDazu fertige Pakete: geoip:private (LAN), geoip:telegram, geoip:google.\nDu willst nach Land filtern? Dann hier, geoip kennt sie alle.\n\n## GeoSite: fertige Listen\ngeosite:google, geosite:netflix, geosite:telegram, geosite:category-ads-all…\nDas sind keine Länder, sondern Kategorien von Diensten, die schon jemand für dich zusammengestellt hat.\nLänder gibt es hier kaum (nur geolocation-cn und geolocation-!cn), nach Land geht es also mit geoip.\n\n## Am PC\nGeo funktioniert wie auf dem Handy. Es braucht nur geoip.dat und geosite.dat neben keqdroid.exe. Im Release liegen sie schon dort. Wenn Geo-Regeln ignoriert werden, prüfe zuerst diese beiden Dateien.\n\n## Reihenfolge\nVon oben nach unten, wie auf dem Bildschirm: Blockieren, einzelne Apps, alle Apps. Bei allen Apps wird „Direkt“ vor „Über das VPN“ geprüft. Dein Server geht immer zuerst direkt, sonst entsteht eine Schleife. Was zu keiner Route passt, folgt der Zeile „Alles andere“.';

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
  String get routePickEmpty => 'Keine Server, die der aktuelle Kern als eigenen Ausgang nutzen kann. Eine fertige Konfiguration passt nur zu ihrem eigenen Kern, Ketten nur zu mihomo.';

  @override
  String settingsRoutingRouteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Routen',
      one: '1 Route',
      zero: 'keine Routen',
    );
    return '$_temp0';
  }

  @override
  String get routesSectionBlock => 'Blockieren';

  @override
  String get routesSectionApps => 'Apps';

  @override
  String get routesSectionAllApps => 'Alle Apps';

  @override
  String get routesHint => 'Die Listen „Direkt“, „Über das VPN“ und „Blockieren“ sind jetzt Routen. Tippe auf eine Route, um sie zu ändern.';

  @override
  String get routesHintDismiss => 'Verstanden';

  @override
  String get routeNew => 'Neue Route';

  @override
  String get routeNewSubtitle => 'App, Websites oder fertige Liste';

  @override
  String get routeNewSubtitleSites => 'Websites oder fertige Liste';

  @override
  String get routeEditorTitle => 'Route';

  @override
  String get routeWho => 'Wer';

  @override
  String get routeWhat => 'Was';

  @override
  String get routeWhere => 'Wohin';

  @override
  String get routeWhoAllSubtitle => 'Alles, was über das VPN läuft';

  @override
  String get routeWhoApps => 'Einzelne Apps';

  @override
  String routeWhoDone(int count) {
    return 'Fertig · $count';
  }

  @override
  String get routeWhatAll => 'Gesamter Datenverkehr';

  @override
  String get routeWhatAllSubtitle => 'Alles, was die App öffnet';

  @override
  String get routeWhatSites => 'Eigene Websites';

  @override
  String get routeWhatSitesSubtitle => 'Domains, IPs und Links zu Listen';

  @override
  String routeWhatPresetValue(String name) {
    return 'Fertige Liste · $name';
  }

  @override
  String routeWhatSitesValue(String entries) {
    return 'Eigene Websites · $entries';
  }

  @override
  String get routeWhereVpnSubtitle => 'Über den Server, mit dem die App verbunden ist';

  @override
  String get routeWhereDirectSubtitle => 'Am VPN vorbei';

  @override
  String get routeWhereBlockSubtitle => 'Verbindungen werden nicht geöffnet';

  @override
  String get routeWhereServers => 'Anderer Server';

  @override
  String get routeToVpn => 'über das VPN';

  @override
  String get routeToDirect => 'direkt';

  @override
  String get routeToBlock => 'blockieren';

  @override
  String get routeAllTrafficShort => 'gesamter Datenverkehr';

  @override
  String get routeDisabledShort => 'aus';

  @override
  String get routeEnabled => 'Route aktiv';

  @override
  String get routeDeleteConfirm => 'Route löschen?';

  @override
  String get routeServerMissing => 'Server fehlt, läuft über das VPN';

  @override
  String get routeServerUnsupported => 'der aktuelle Kern kann diesen Server nicht nutzen, läuft über das VPN';

  @override
  String get routeAppsUnsupported => 'der aktuelle Kern unterscheidet keine Apps, die Route wirkt nicht';

  @override
  String get routeAppsNeedTun => 'wirkt nur im TUN-Modus';

  @override
  String get routeAppsNeedVpn => 'wirkt nur im VPN-Modus';

  @override
  String get routingProfileMain => 'Hauptprofil';

  @override
  String get routingIgnoreProviderRules => 'Regeln des Anbieters ignorieren';

  @override
  String get routingIgnoreProviderRulesHint => 'Es gelten nur deine Routen';

  @override
  String get routingProfileScopeAll => 'Alle Abonnements und eigene Server';

  @override
  String get routingProfileScopeRest => 'Übrige Abonnements und eigene Server';

  @override
  String routingProfileRouteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Routen',
      one: '1 Route',
      zero: 'keine Routen',
    );
    return '$_temp0';
  }

  @override
  String routingProfileFinal(String target) {
    return 'alles andere → $target';
  }

  @override
  String get routingProfileOff => 'Aus: es gilt das Hauptprofil';

  @override
  String get routingProfileNoSubscriptions => 'Mit keinem Abonnement verknüpft';

  @override
  String get routingProfileNew => 'Neues Profil';

  @override
  String get routingProfileName => 'Name';

  @override
  String get routingProfileForSubscriptions => 'Für Abonnements';

  @override
  String routingProfileSubOnOther(String name) {
    return 'jetzt im Profil „$name“';
  }

  @override
  String get routingProfileStartFrom => 'Beginnen mit';

  @override
  String get routingProfileStartCopy => 'Kopie des Hauptprofils';

  @override
  String get routingProfileStartCopyHint => 'Dieselben Routen, danach passt du sie an das Abonnement an';

  @override
  String get routingProfileStartEmpty => 'Leeres Profil';

  @override
  String get routingProfileStartEmptyHint => 'Nur alles andere über das VPN';

  @override
  String get routingProfileCreate => 'Erstellen';

  @override
  String get routingProfileNoSubscriptionsYet => 'Noch keine Abonnements: ein Profil gilt für die Server von Abonnements';

  @override
  String get routingProfileRenameTitle => 'Profil umbenennen';

  @override
  String get routingProfileSubscriptions => 'Abonnements';

  @override
  String routingProfileDeleteConfirm(String name) {
    return 'Profil „$name“ löschen? Seine Abonnements kehren zum Hauptprofil zurück.';
  }

  @override
  String routeSplitExcluded(String apps) {
    return 'Split-Tunneling leitet $apps am VPN vorbei';
  }

  @override
  String get routeRefilterUnmatched => '„Alles andere“ läuft jetzt direkt';

  @override
  String settingsRoutingLinkDomains(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted Domains aus Links',
      one: '1 Domain aus Links',
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
      other: '$formatted Domains',
      one: '1 Domain',
    );
    return '$_temp0';
  }

  @override
  String ruleListLoaded(String host, String domains, String when) {
    return '$host – $domains, aktualisiert $when';
  }

  @override
  String ruleListLoadedStale(String host, String domains, String when) {
    return '$host – $domains, aktualisiert $when; die neue Fassung wurde nicht geladen';
  }

  @override
  String ruleListLoading(String host) {
    return '$host – wird geladen…';
  }

  @override
  String ruleListFailedNetwork(String host) {
    return '$host – nicht geladen, neuer Versuch bei der nächsten Verbindung';
  }

  @override
  String ruleListFailedInsecure(String host) {
    return '$host – der Link muss mit https beginnen';
  }

  @override
  String ruleListFailedHttp(String host, int code) {
    return '$host – der Server antwortete mit $code';
  }

  @override
  String ruleListFailedTooLarge(String host) {
    return '$host – die Datei ist größer als 30 MB';
  }

  @override
  String ruleListFailedEmpty(String host) {
    return '$host – keine Domains in der Datei';
  }

  @override
  String ruleListMemoryWarning(String limit) {
    return 'Mehr als $limit Domains aus Links: Der Kern braucht deutlich mehr Speicher, und das System kann ihn im Hintergrund beenden.';
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
  String get themeCustomizationTitle => 'Erscheinungsbild';

  @override
  String get themeUseDynamicColors => 'Dynamische Android-Farben verwenden';

  @override
  String get themePaletteHint => 'Hell und Dunkel werden weiterhin separat umgeschaltet';

  @override
  String get themeUseSystemColors => 'System-Akzentfarben verwenden';

  @override
  String get themeColorThemesTitle => 'Farbdesigns';

  @override
  String get serversColumnsTitle => 'Mehrere Spalten';

  @override
  String get serversColumnsNoRoom => 'Passen bei dieser Oberflächengröße nicht';

  @override
  String serversColumnsOnlyFit(int count) {
    return 'Bei dieser Oberflächengröße passen nur $count';
  }

  @override
  String get appearanceServerIconThemeColors => 'Serversymbole ohne Flagge in Designfarben';

  @override
  String get settingsLanProxyTitle => 'LAN-Proxy';

  @override
  String get settingsOff => 'Aus';

  @override
  String settingsLanSharingOnIp(Object ip) {
    return 'Freigabe auf $ip';
  }

  @override
  String settingsLanFirewallHint(Object ports) {
    return 'Wenn sich andere Geräte nicht verbinden, öffne die Ports $ports in der Firewall:';
  }

  @override
  String get settingsDeviceIpListTitle => 'IP-Adressen des Geräts im Netzwerk:';

  @override
  String get settingsIpCopied => 'IP kopiert';

  @override
  String get settingsSetupAnotherDeviceTitle => 'Einrichtung auf einem anderen Gerät:';

  @override
  String get settingsSocks5PortLabel => 'SOCKS5-Port';

  @override
  String get settingsHttpPortLabel => 'HTTP-Port';

  @override
  String get settingsLanUsernameLabel => 'Benutzername';

  @override
  String get settingsLanPasswordLabel => 'Passwort';

  @override
  String get settingsLanAuthHint => 'Sind beide Felder ausgefüllt, melden sich Geräte damit am Proxy an. Bleiben sie leer, gibt es kein Passwort und jeder in deinem Netzwerk kann den Proxy nutzen.';

  @override
  String get settingsLocalPortsTitle => 'Lokale Proxy-Ports';

  @override
  String get settingsLocalPortsHint => 'SOCKS5 und HTTP, Standard 2080 / 2081, müssen verschieden sein. Gilt ab der nächsten Verbindung.';

  @override
  String get settingsPortInvalid => 'Gib einen Port zwischen 1 und 65535 ein';

  @override
  String get settingsPortsMustDiffer => 'SOCKS- und HTTP-Port müssen sich unterscheiden';

  @override
  String get settingsTurnOffToChange => 'Zum Ändern der Einstellung ausschalten';

  @override
  String settingsProxyCopied(Object label, Object address) {
    return '$label $address kopiert';
  }

  @override
  String get settingsXrayCoreTitle => 'Kerneinstellungen';

  @override
  String get settingsXrayCoreSubtitle => 'DNS, Mux, Fragmentierung, TUN und Protokolle';

  @override
  String get settingsXrayDnsSection => 'DNS';

  @override
  String get settingsXrayDnsCustom => 'Eigene DNS-Server';

  @override
  String get settingsXrayDnsCustomHint => 'Eine Adresse pro Zeile (DoH, DoT oder unverschlüsselt)';

  @override
  String get settingsXrayDnsCustomHintXray => 'Eine Adresse pro Zeile (DoH oder unverschlüsselt), DoT kann Xray nicht';

  @override
  String get settingsXrayDnsServers => 'DNS-Server';

  @override
  String get settingsXrayDnsSplitDirect => 'Eigener Resolver für direkte Domains';

  @override
  String get settingsXrayDnsSplitDirectHint => 'Domains aus der Direkt-Liste löst der erste Server auf';

  @override
  String get settingsXrayDnsSplitDirectSystemHint => 'Domains aus der Direkt-Liste löst das System-DNS auf';

  @override
  String get settingsXrayDnsHosts => 'Eigene Adressen für Domains';

  @override
  String get settingsXrayDnsPolicy => 'Resolver für einzelne Domains';

  @override
  String get settingsXrayDnsQueryStrategy => 'Abfragestrategie';

  @override
  String get settingsXrayDnsDisableCache => 'DNS-Cache deaktivieren';

  @override
  String get settingsXrayXmuxSection => 'XMUX (XHTTP)';

  @override
  String get settingsXrayXmuxEnable => 'XMUX selbst einstellen';

  @override
  String get settingsXrayXmuxEnableHint => 'Sonst hält Xray bis zu 3 Verbindungen und ersetzt jede nach 600-900 Anfragen oder 30-50 Minuten';

  @override
  String get settingsXrayMuxSection => 'Mux';

  @override
  String get settingsXrayMuxEnable => 'Mux aktivieren';

  @override
  String get settingsXrayMuxEnableHint => 'Mehrere Verbindungen in einer: weniger Handshakes, bei Downloads und Speedtests aber meist schlechter.';

  @override
  String get settingsXrayMuxParamsTitle => 'Streams pro Verbindung';

  @override
  String get settingsXrayMuxParamsHint => '-1 schaltet das Multiplexing ab. TCP bis 128, UDP bis 1024.';

  @override
  String get settingsXrayMuxConcurrency => 'TCP-Streams';

  @override
  String get settingsXrayMuxXudpConcurrency => 'UDP-Streams (XUDP)';

  @override
  String get settingsXrayMuxUdp443Title => 'QUIC (UDP/443)';

  @override
  String get settingsXrayMuxUdp443Reject => 'Ablehnen';

  @override
  String get settingsXrayMuxUdp443Allow => 'Über Mux leiten';

  @override
  String get settingsXrayMuxUdp443Skip => 'Mux umgehen';

  @override
  String get settingsXrayGeneralSection => 'Allgemein';

  @override
  String get settingsXrayLogLevel => 'Protokollebene';

  @override
  String get settingsXrayDomainStrategy => 'Routing-Domainstrategie';

  @override
  String get settingsXrayConcurrentDial => 'Alle Adressen gleichzeitig anwählen';

  @override
  String get settingsXrayConcurrentDialHint => 'Hilft, wenn ein Teil der Serveradressen gesperrt ist';

  @override
  String get settingsXraySniffing => 'Domains im Datenverkehr erkennen (Sniffing)';

  @override
  String get settingsXraySniffingRouteOnly => 'Erkannte Domain nur fürs Routing';

  @override
  String get settingsXrayDnsDefaultNote => 'Standard: Cloudflare und Google DoH';

  @override
  String get settingsXrayXmuxParamsTitle => 'Feineinstellung';

  @override
  String get settingsXrayXmuxParamsHint => 'Leer nutzt den Xray-Standard. Zahl oder Bereich, z. B. 16-32.';

  @override
  String get settingsXraySniffingHint => 'Zielprotokoll und Domain aus dem eingehenden Datenverkehr erkennen';

  @override
  String get settingsXraySniffingRouteOnlyHint => 'Die erkannte Domain wählt nur die Regel; verbunden wird zur Adresse der App.';

  @override
  String get settingsXrayUdpPerAddress => 'UDP je Zieladresse nach Regeln leiten';

  @override
  String get settingsXrayUdpPerAddressHint => 'Der Ausgang folgt für jede Zieladresse den Regeln, nicht dem ersten Paket eines Sockets. P2P über STUN (Anrufe, Spiele, Torrents) kommt eventuell nicht direkt zustande, wenn die Regeln STUN-Server und Gegenstelle über verschiedene Ausgänge schicken.';

  @override
  String get settingsXrayResetDefaults => 'Zurücksetzen';

  @override
  String get settingsXrayResetDone => 'Xray-Kerneinstellungen wiederhergestellt';

  @override
  String get settingsXrayXmuxMaxConcurrency => 'Max. Parallelität';

  @override
  String get settingsXrayXmuxMaxConnections => 'Max. Verbindungen';

  @override
  String get settingsXrayXmuxOneOfTwo => 'Nur eines von beiden';

  @override
  String get settingsXrayXmuxConnectionsIgnored => 'Wird ignoriert, solange die Parallelität gesetzt ist';

  @override
  String get settingsXrayXmuxCMaxReuseTimes => 'Limit für Verbindungs-Wiederverwendung';

  @override
  String get settingsXrayXmuxHMaxRequestTimes => 'Max. Anfragen pro Stream';

  @override
  String get settingsXrayXmuxHMaxReusableSecs => 'Stream-Wiederverwendungszeit (Sek.)';

  @override
  String get settingsXrayXmuxHKeepAlivePeriod => 'Keep-Alive-Intervall (Sek.)';

  @override
  String get settingsXrayFragmentSection => 'Fragmentierung';

  @override
  String get settingsXrayFragmentEnable => 'TLS-ClientHello aufteilen';

  @override
  String get settingsXrayFragmentEnableHint => 'Das erste Paket geht in Stücken hinaus, sodass DPI die SNI nicht lesen kann.';

  @override
  String get settingsXrayNoiseSection => 'UDP-Rauschen';

  @override
  String get settingsXrayNoiseEnable => 'Rauschen vor UDP senden';

  @override
  String get settingsXrayNoiseEnableHint => 'Vor dem ersten echten Paket geht ein Paket mit Zufallsdaten an den Server. Für hysteria und mkcp, wo es kein ClientHello zum Aufteilen gibt.';

  @override
  String get settingsXrayNoiseKindTitle => 'Was gesendet wird';

  @override
  String get settingsXrayNoiseKindRand => 'Zufallsdaten';

  @override
  String get settingsXrayNoiseKindStr => 'Eigenes Paket: Text';

  @override
  String get settingsXrayNoiseKindHex => 'Eigenes Paket: Hex';

  @override
  String get settingsXrayNoiseKindBase64 => 'Eigenes Paket: Base64';

  @override
  String get settingsXrayNoisePacket => 'Paket';

  @override
  String get settingsXrayNoiseRandLength => 'Länge, Bytes';

  @override
  String get settingsXrayNoiseRandBytes => 'Bytewerte (0-255)';

  @override
  String get settingsXrayNoiseDelay => 'Verzögerung, ms';

  @override
  String get settingsXrayNoiseReset => 'Wiederholung, Sek.';

  @override
  String get settingsXrayNoiseParamsHint => 'Eine Zahl oder ein Bereich, z. B. 50-100. Leer überlässt es dem Kern.';

  @override
  String get settingsXrayFragmentPacketsTitle => 'Was aufgeteilt wird';

  @override
  String get settingsXrayFragmentPacketsTlsHello => 'Nur TLS-ClientHello';

  @override
  String get settingsXrayFragmentPacketsFirst => 'Erste Pakete des Streams';

  @override
  String get settingsXrayFragmentParamsTitle => 'Stückgröße und Verzögerung';

  @override
  String get settingsXrayFragmentParamsHint => 'Zahl oder Bereich, z. B. 100-200.';

  @override
  String get settingsXrayFragmentLength => 'Größe, Bytes';

  @override
  String get settingsXrayFragmentInterval => 'Verzögerung, ms';

  @override
  String get settingsTunSection => 'TUN-Modus';

  @override
  String get settingsTunSectionNote => 'Gelten ab der nächsten Verbindung.';

  @override
  String get settingsTunStackTitle => 'Netzwerk-Stack';

  @override
  String get settingsTunStackSystemHint => 'OS-Stack: am schnellsten, braucht unter Windows eine Firewall-Regel.';

  @override
  String get settingsTunStackGvisorHint => 'Userspace-Stack: kein Listener, keine Firewall-Regeln, etwas langsamer. Braucht einen Kern mit gVisor.';

  @override
  String get settingsTunStackMixedHint => 'system für TCP, gVisor für UDP. Wie system braucht er unter Windows eine Firewall-Regel. Braucht einen Kern mit gVisor.';

  @override
  String get settingsTunStackMipsHint => 'Der eigene Userspace-Stack von mihomo statt gVisor: leichter, mit wählbarer TCP-Staukontrolle. Nur mit dem mihomo-Kern.';

  @override
  String get settingsTunMtu => 'MTU';

  @override
  String get settingsTunMtuHint => '576–65535, Standard 9000';

  @override
  String get settingsTunUdpTimeout => 'UDP-Timeout (Sek.)';

  @override
  String get settingsTunUdpTimeoutHint => 'NAT-Lebensdauer inaktiver UDP-Sitzungen, Standard 300';

  @override
  String get settingsTunStrictRouteTitle => 'Strenges Routing (strict route)';

  @override
  String get settingsTunStrictRouteHint => 'Verhindert, dass Datenverkehr am TUN vorbeiläuft. Unter Windows kann es das Routing stören, wenn ein anderes VPN (z. B. Tailscale) aktiv ist';

  @override
  String get settingsTunStrictRouteAuto => 'Auto';

  @override
  String get settingsTunStrictRouteAutoHint => 'Linux: an, Windows: aus';

  @override
  String get settingsTunStrictRouteOn => 'An';

  @override
  String get settingsTunStrictRouteOff => 'Aus';

  @override
  String get settingsTunAutoRoute => 'Automatisches Routing (auto route)';

  @override
  String get settingsTunAutoRouteHint => 'Fügt Systemrouten in den Tunnel ein. Ohne diese Option gelangt kein Datenverkehr ins TUN.';

  @override
  String get settingsTunIpv6 => 'IPv6 im Tunnel halten';

  @override
  String get settingsTunIpv6Hint => 'Gibt dem TUN-Interface eine IPv6-Adresse, sonst läuft der gesamte IPv6-Verkehr am Tunnel vorbei.';

  @override
  String get settingsFakeIp => 'Fake IP';

  @override
  String get settingsFakeIpHint => 'Sofortige Auflösung über Fake-Adressen. Im Proxy-Modus ohne Wirkung.';

  @override
  String get settingsPingTitle => 'Server-Ping';

  @override
  String get settingsPingMethodTitle => 'Ping-Methode';

  @override
  String get settingsPingMethodTcp => 'TCP-Ping';

  @override
  String get settingsPingMethodTcpHint => 'Schnelle Erreichbarkeitsprüfung';

  @override
  String get settingsPingMethodIcmp => 'ICMP-Ping';

  @override
  String get settingsPingMethodIcmpHint => 'Echo an Server-IP (manche Server blockieren es)';

  @override
  String get settingsPingMethodUrl => 'HTTP über Proxy';

  @override
  String get settingsPingMethodUrlHint => 'Misst die GET-Latenz über den Server';

  @override
  String get settingsPingKeepAliveTitle => 'Art der Messung';

  @override
  String get settingsPingKeepAlive => 'Auf warmer Verbindung messen';

  @override
  String get settingsPingKeepAliveHint => 'Die Anfrage geht zweimal hinaus und gezählt wird die zweite, also ohne Handshake. Aus: eine einzige Anfrage samt Aufwärmen, wie beim ersten Öffnen einer Website.';

  @override
  String get settingsPingAutoTitle => 'Wann messen';

  @override
  String get settingsPingAuto => 'Automatisch messen';

  @override
  String get settingsPingAutoHint => 'Beim Öffnen der App und direkt nach dem Aktualisieren eines Abonnements';

  @override
  String get settingsPingMethodSpeed => 'Geschwindigkeitstest';

  @override
  String get settingsPingMethodSpeedHint => 'Lädt eine feste Datenmenge über den Server herunter und zeigt den Durchsatz in Mbit/s (funktioniert auch ohne VPN)';

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
  String get settingsPingCustomUrlHint => 'Adresse für die GET-Anfrage (https:// oder http://)';

  @override
  String get settingsPingCustomUrlInvalid => 'Ungültige oder unsichere URL (localhost und private Netzwerke sind nicht erlaubt)';

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
  String get subscriptionsAddAndFetch => 'Hinzufügen und laden';

  @override
  String get subscriptionsEditSubscription => 'Abonnement bearbeiten';

  @override
  String get subscriptionsCopyUrl => 'URL kopieren';

  @override
  String get subscriptionsUrlCopied => 'URL kopiert';

  @override
  String get subscriptionsShareButton => 'Teilen (QR + Link)';

  @override
  String get subscriptionsShareAction => 'Teilen';

  @override
  String subscriptionsShareFailed(Object error) {
    return 'Teilen fehlgeschlagen: $error';
  }

  @override
  String subscriptionsQrSaved(Object path) {
    return 'QR-Code gespeichert: $path';
  }

  @override
  String subscriptionsQrSaveFailed(Object error) {
    return 'QR-Code konnte nicht gespeichert werden: $error';
  }

  @override
  String get subscriptionsQrSaveTitle => 'QR-Code speichern';

  @override
  String get subscriptionIdentityTitle => 'Geräteidentität';

  @override
  String get subscriptionIdentityHint => 'Was das Panel sieht: HWID, User-Agent und Geräte-Header. Gilt nur für dieses Abonnement.';

  @override
  String get subscriptionIdentityEnable => 'Eigene Identität verwenden';

  @override
  String get subscriptionIdentityAppDefault => 'App-Standard';

  @override
  String get subscriptionIdentityAppDefaultHint => 'Echten Wert dieses Geräts senden';

  @override
  String get subscriptionIdentityHwid => 'HWID';

  @override
  String get subscriptionIdentityHwidOff => 'In den erweiterten Einstellungen ist „Geräte-HWID senden“ ausgeschaltet, daher wird keine HWID gesendet, auch keine eigene.';

  @override
  String get subscriptionIdentityUserAgent => 'User-Agent';

  @override
  String get subscriptionIdentityDeviceOs => 'Geräte-OS';

  @override
  String get subscriptionIdentityDeviceModel => 'Gerätemodell';

  @override
  String get subscriptionIdentityOsVersion => 'OS-Version';

  @override
  String get subscriptionIdentitySectionUsed => 'Bereits verwendet';

  @override
  String get subscriptionIdentitySectionUaAndroid => 'Android-Clients';

  @override
  String get subscriptionIdentitySectionUaApple => 'iPhone- und iPad-Clients';

  @override
  String get subscriptionIdentitySectionUaDesktop => 'Desktop-Clients';

  @override
  String get subscriptionIdentitySectionUaCores => 'Kerne und reines HTTP';

  @override
  String get subscriptionIdentitySectionOs => 'Betriebssysteme';

  @override
  String get subscriptionIdentitySectionApple => 'iPhone und iPad';

  @override
  String get subscriptionIdentitySectionDesktop => 'Desktop';

  @override
  String get subscriptionIdentitySectionAndroidRelease => 'Android-Versionen';

  @override
  String get subscriptionIdentitySectionAndroidBuild => 'Android-Builds';

  @override
  String get subscriptionIdentitySectionIosRelease => 'iOS-Versionen';

  @override
  String get subscriptionIdentitySectionIosBuild => 'iOS-Builds';

  @override
  String get subscriptionIdentitySearchOrEnter => 'Suchen oder eigenen Wert eingeben';

  @override
  String get subscriptionIdentityUseTyped => 'Diesen Wert verwenden';

  @override
  String get subscriptionIdentityReset => 'Zurücksetzen';

  @override
  String get subscriptionIdentityApply => 'Übernehmen';

  @override
  String get subscriptionsDeleteSubscription => 'Abonnement löschen';

  @override
  String subscriptionsDeleteConfirm(Object name) {
    return 'Möchtest du „$name“ wirklich löschen?\n\nDadurch werden auch alle zugehörigen Server entfernt.';
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
  String get subscriptionsOff => 'AUS';

  @override
  String get subscriptionsExpired => 'Abgelaufen';

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
  String subscriptionsIntervalShort(int hours) {
    return '$hours Std.';
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
    return 'vor $days Tg.';
  }

  @override
  String subscriptionsInDays(int days) {
    return 'in $days Tg.';
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
  String get serversPasteLinksHint => 'Serverlinks oder komplette Konfiguration';

  @override
  String get serversImportFile => 'Datei importieren';

  @override
  String get serversImportFileHint => 'Datei mit Serverlinks oder Konfiguration';

  @override
  String get serversAddServerTitle => 'Server hinzufügen';

  @override
  String get serversPasteVlessHint => 'Ein Link pro Zeile oder eine komplette Konfiguration: Xray, Clash, sing-box, AmneziaWG';

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
  String get settingsAdvancedSubtitle => 'Kerneinstellungen, Ping, Routing, HWID und Debug';

  @override
  String get serverEditorJsonValid => 'Gültige Xray-Konfiguration';

  @override
  String get serverEditorJsonFormat => 'Formatieren';

  @override
  String get subscriptionsCardMenu => 'Mehr';

  @override
  String get subscriptionsAutoUpdateOff => 'Nicht automatisch aktualisieren';

  @override
  String get subscriptionsProviderPage => 'Abonnementseite';

  @override
  String get subscriptionsSupport => 'Support';

  @override
  String get subscriptionsLinkOpenFailed => 'Link konnte nicht geöffnet werden';

  @override
  String get settingsAdvancedGroupTraffic => 'Datenverkehr und Kern';

  @override
  String get settingsAdvancedGroupSystem => 'System';

  @override
  String get settingsAdvancedGroupDiagnostics => 'Diagnose';

  @override
  String get settingsBackupRestore => 'Sichern und wiederherstellen';

  @override
  String get settingsBackupRestoreSubtitle => 'Export/Import: Split-Tunneling, Abonnements, Server, Einstellungen';

  @override
  String get settingsSelectAtLeastOne => 'Wähle mindestens einen Abschnitt zum Exportieren';

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
  String get settingsChooseWhatToImport => 'Ausgewählte Abschnitte ersetzen deine aktuellen Daten';

  @override
  String get settingsSplitTunnelingApps => 'Split-Tunneling-Apps';

  @override
  String get settingsSubscriptions => 'Abonnements';

  @override
  String get settingsServersActive => 'Server (und aktiver Server)';

  @override
  String get settingsAppSettings => 'App-Einstellungen';

  @override
  String get settingsImport => 'Importieren';

  @override
  String get settingsExport => 'Exportieren';

  @override
  String get settingsCreateFileToSave => 'Die Datei lässt sich auf ein anderes Gerät mitnehmen';

  @override
  String get settingsPickExportedFile => 'Was wiederhergestellt wird, wählst du nach der Datei';

  @override
  String get settingsWorking => 'Wird ausgeführt…';

  @override
  String settingsImportedSections(int count) {
    return 'Importierte Abschnitte: $count';
  }

  @override
  String get settingsShareHwidTitle => 'Geräte-HWID senden';

  @override
  String get settingsShareHwidOn => 'Wird mit Abonnementanfragen gesendet';

  @override
  String get settingsShareHwidOff => 'Wird nicht gesendet';

  @override
  String get settingsDebugMode => 'Debug-Modus';

  @override
  String get settingsDebugModeOn => 'Erweiterte Diagnose aktiviert';

  @override
  String get settingsDebugModeOff => 'Aus';

  @override
  String get settingsOpenXrayLogs => 'Kernprotokoll öffnen';

  @override
  String get settingsXrayCoreLogs => 'Kernprotokoll';

  @override
  String get settingsRefresh => 'Aktualisieren';

  @override
  String get settingsCopyLogs => 'Protokoll kopieren';

  @override
  String get settingsAppVersion => 'App-Version';

  @override
  String get settingsChecking => 'Wird geprüft…';

  @override
  String get settingsCheckFailed => 'Prüfung fehlgeschlagen';

  @override
  String get settingsUpdateAvailable => 'Update verfügbar';

  @override
  String get settingsUpToDate => 'Aktuell';

  @override
  String get settingsNewVersionAvailable => 'Neue Version verfügbar';

  @override
  String get settingsDownloading => 'Wird heruntergeladen…';

  @override
  String get settingsCheckForUpdates => 'Nach Updates suchen';

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
  String get settingsLanguageTitle => 'Sprache';

  @override
  String settingsLanguageSubtitle(Object language) {
    return '$language';
  }

  @override
  String get settingsBehaviourTitle => 'Verhalten';

  @override
  String settingsBehaviourSubtitle(Object interval) {
    return 'Updates: $interval';
  }

  @override
  String get behaviourUpdatesSection => 'App-Updates';

  @override
  String get behaviourUpdatePrompt => 'Über neue Versionen informieren';

  @override
  String get behaviourEveryDay => 'Täglich';

  @override
  String get behaviourEvery3Days => 'Alle 3 Tage';

  @override
  String get behaviourEveryWeek => 'Wöchentlich';

  @override
  String get settingsLanguageSystem => 'Systemsprache';

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
  String get splitAddAppInvalid => 'Gib einen gültigen .exe-Namen oder Pfad ein';

  @override
  String get splitAddAppHintLinux => 'Pfad zum Programm oder sein Name (z. B. firefox)';

  @override
  String get splitAddAppInvalidLinux => 'Gib einen Programmnamen oder Pfad ein';

  @override
  String splitAddAppAdded(Object name) {
    return 'Hinzugefügt: $name';
  }

  @override
  String get splitProxyModeWarning => 'Im Proxy-Modus wird Split-Tunneling nicht angewendet, der gesamte Datenverkehr läuft über den System-Proxy. Wechsle den Verbindungsmodus in der Seitenleiste auf TUN, damit die Regeln pro Prozess greifen.';

  @override
  String get settingsLatestVersionInstalled => 'Du hast die neueste Version';

  @override
  String get serversPingServer => 'Server anpingen';

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
  String get settingsDebugHintDesktop => 'Zeigt das Sitzungsprotokoll des Kerns. Live-Messwerte des VPN stehen unter der Verbinden-Schaltfläche.';

  @override
  String get settingsDebugHintMobile => 'Zeigt Live-Messwerte des VPN in den Serverkarten und das Kernprotokoll.';

  @override
  String get desktopConnectionMode => 'Verbindungsmodus';

  @override
  String get desktopModeShort => 'Modus';

  @override
  String get settingsDesktopTitle => 'Windows';

  @override
  String get settingsDesktopTitleLinux => 'Linux';

  @override
  String get settingsDesktopSubtitle => 'Infobereich, Autostart, automatisches Verbinden';

  @override
  String get settingsMinimizeToTray => 'Beim Schließen in den Infobereich minimieren';

  @override
  String get settingsLaunchAtStartup => 'Mit Windows starten';

  @override
  String get settingsLaunchAtLogin => 'Beim Anmelden starten';

  @override
  String get settingsLaunchAtStartupAdmin => 'Mit Administratorrechten starten';

  @override
  String get settingsAutostartInTray => 'Im Infobereich starten, ohne Fenster';

  @override
  String get settingsAutostartAdminFailed => 'Administratorrechte wurden nicht erteilt';

  @override
  String get settingsAutoConnectOnAutostart => 'Bei Autostart verbinden';

  @override
  String get settingsAutoConnectRequiresAutostart => 'Zuerst „Mit Windows starten“ aktivieren';

  @override
  String get settingsAutoConnectRequiresLogin => 'Zuerst „Beim Anmelden starten“ aktivieren';

  @override
  String get desktopTunAdminTitle => 'Administratorrechte erforderlich';

  @override
  String get desktopTunAdminMessage => 'Der TUN-Modus benötigt Administratorrechte. Starte die App als Administrator neu, der in der Seitenleiste gewählte Modus bleibt erhalten.';

  @override
  String get desktopTunAdminRestart => 'Als Administrator neu starten';

  @override
  String get desktopTunAdminCancel => 'Abbrechen';

  @override
  String get desktopTunAdminRestartFailed => 'Neustart als Administrator fehlgeschlagen';

  @override
  String get trayConnect => 'Verbinden';

  @override
  String get trayDisconnect => 'Trennen';

  @override
  String get trayOpenApp => 'App öffnen';

  @override
  String get trayExit => 'Beenden';

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

  @override
  String get serversSortTitle => 'Server sortieren';

  @override
  String get serversSortDefault => 'Standardreihenfolge';

  @override
  String get serversSortPing => 'Ping (aufsteigend)';

  @override
  String get serversSortSpeed => 'Geschwindigkeit (absteigend)';

  @override
  String get serversSortName => 'Name (A → Z)';

  @override
  String get updateActionSkip => 'Diese Version überspringen';

  @override
  String updateSizeLabel(Object size) {
    return 'Größe: $size';
  }

  @override
  String get updateOpenDownload => 'Download öffnen';

  @override
  String get vpnConnectedGeneric => 'VPN verbunden';

  @override
  String serversImportedSummary(Object added, Object total) {
    return 'Server hinzugefügt: $added von $total';
  }

  @override
  String get sidebarJumpTitle => 'Schnellzugriff';

  @override
  String get desktopRailCollapse => 'Leiste einklappen';

  @override
  String get desktopRailExpand => 'Leiste ausklappen';

  @override
  String get serversScrollToEnd => 'Zum Ende springen';

  @override
  String get serversScrollToTop => 'Zum Anfang springen';

  @override
  String get serversJumpToActive => 'In der Liste zeigen';

  @override
  String get exitIpLabel => 'IP, die Websites sehen';

  @override
  String get serversAutoSelect => 'Auto';

  @override
  String get serversAutoSelectTooltip => 'Die App wählt den Server in diesem Abonnement selbst und wechselt, wenn er nicht mehr funktioniert';

  @override
  String get serversManualGroup => 'Manuelle Server';

  @override
  String get serversEmptyGroupHint => 'Keine Server in diesem Abonnement';

  @override
  String get statsInLabel => 'Empfangen';

  @override
  String get statsTimeLabel => 'Zeit';

  @override
  String get statsDownloadLabel => 'Download';

  @override
  String get statsUploadLabel => 'Upload';

  @override
  String get statsSplitVpnTag => 'VPN';

  @override
  String get statsSplitDirectTag => 'direkt';

  @override
  String get statsSplitVpnLabel => 'Über das VPN';

  @override
  String get statsSplitDirectLabel => 'Am VPN vorbei';

  @override
  String get statsSplitTotalLabel => 'Übertragen';

  @override
  String get qrScanTitle => 'QR-Code scannen';

  @override
  String get qrScanHint => 'Richte die Kamera auf einen QR-Code';

  @override
  String get qrScanCameraError => 'Kamera nicht verfügbar';

  @override
  String get serversScanQrHint => 'Server- oder Abonnement-Link';

  @override
  String qrSubscriptionAdded(Object name) {
    return 'Abonnement hinzugefügt: $name';
  }

  @override
  String get qrNotSubscriptionLink => 'Der QR-Code enthält keinen Abonnement-Link';

  @override
  String get tvReceiveTitle => 'Vom Smartphone empfangen';

  @override
  String get tvReceiveSubtitle => 'Abonnement vom Smartphone über WLAN';

  @override
  String get tvReceiveHint => 'Scanne den Code mit keqdroid auf dem Smartphone. Smartphone und Fernseher müssen im selben WLAN sein.';

  @override
  String get tvReceiveWaiting => 'Warte auf ein Abonnement…';

  @override
  String tvReceiveGot(Object name) {
    return 'Empfangen: $name';
  }

  @override
  String tvReceiveFailed(Object error) {
    return 'Hinzufügen fehlgeschlagen: $error';
  }

  @override
  String get tvReceiveNoNetwork => 'Der Fernseher ist mit keinem Netzwerk verbunden';

  @override
  String get tvSendTitle => 'An Fernseher senden';

  @override
  String get tvSendPick => 'Welches Abonnement möchtest du senden?';

  @override
  String get tvSendAction => 'Senden';

  @override
  String get tvSendDone => 'Abonnement an den Fernseher gesendet';

  @override
  String get tvSendNothing => 'Auf diesem Smartphone gibt es keine Abonnements zum Senden';

  @override
  String get tvSendUnreachable => 'Der Fernseher antwortet nicht. Prüfe, ob Smartphone und Fernseher im selben WLAN sind und der Empfangsbildschirm auf dem Fernseher geöffnet ist.';

  @override
  String get tvSendExpired => 'Dieser Code ist abgelaufen. Öffne den Empfangsbildschirm auf dem Fernseher erneut und scanne den neuen Code.';

  @override
  String tvSendRejected(Object error) {
    return 'Der Fernseher hat das Abonnement nicht hinzugefügt: $error';
  }

  @override
  String get settingsHotkeysTitle => 'Tastenkürzel';

  @override
  String get settingsHotkeysSubtitle => 'Kürzel für Verbindung, Modus und Server';

  @override
  String get hotkeysHintGlobal => 'Kürzel funktionieren systemweit, auch wenn das Fenster im Infobereich versteckt ist. Alle Kürzel sind inaktiv, bis du sie zuweist.';

  @override
  String get hotkeysHintInApp => 'Unter Linux funktionieren Kürzel, solange das App-Fenster im Fokus ist. Alle Kürzel sind inaktiv, bis du sie zuweist.';

  @override
  String get hotkeyActionToggleConnection => 'Verbinden / Trennen';

  @override
  String get hotkeyActionToggleTun => 'TUN / Proxy umschalten';

  @override
  String get hotkeyActionBestPing => 'Zum Server mit bestem Ping wechseln';

  @override
  String get hotkeyActionToggleWindow => 'Fenster anzeigen / ausblenden';

  @override
  String get hotkeyNotSet => 'Nicht belegt';

  @override
  String get hotkeyPressKeys => 'Tasten drücken…';

  @override
  String get hotkeyRecordingHint => 'Esc bricht ab, Rücktaste löscht';

  @override
  String get hotkeyNeedsModifier => 'Modifikator (Strg/Alt/Umschalt/Win) oder F-Taste nötig';

  @override
  String hotkeyConflictTaken(Object combo) {
    return 'Kürzel $combo wird bereits von einer anderen App verwendet';
  }

  @override
  String get hotkeyClearTooltip => 'Kürzel entfernen';

  @override
  String get hotkeyNoPingData => 'Noch keine Ping-Ergebnisse, starte zuerst einen Ping-Test';

  @override
  String get clipboardNoSubscriptionLink => 'Die Zwischenablage enthält keinen Abonnement-Link (http/https)';

  @override
  String get splitTunnelingReconnectHint => 'Änderungen gelten nach dem erneuten Verbinden des VPN';

  @override
  String serversDeleteConfirm(Object name) {
    return 'Server „$name“ wirklich löschen?';
  }

  @override
  String get errorTunAdminMessage => 'Der TUN-Modus unter Windows benötigt Administratorrechte.';

  @override
  String get errorTunAdminAction => 'Starte die App als Administrator oder wechsle in den Einstellungen in den Proxy-Modus.';

  @override
  String get errorTunAdapterRefusedTitle => 'Windows hat den Adapter abgelehnt';

  @override
  String get errorTunAdapterRefusedMessage => 'Windows lehnte den TUN-Adapter dreimal ab, am Server liegt es nicht.';

  @override
  String get errorTunAdapterRefusedAction => 'Verbinde dich in einer Minute erneut oder starte den Computer neu. Proxy geht weiter.';

  @override
  String get errorPolkitMissingTitle => 'Polkit erforderlich';

  @override
  String get errorPolkitMissingMessage => 'Der TUN-Modus startet den Kern über pkexec als root, und polkit ist nicht installiert.';

  @override
  String get errorPolkitMissingAction => 'Installiere polkit samt Authentifizierungsagent, starte die App als root (sudo -E keqdroid) oder wechsle in den Einstellungen zum Proxy-Modus.';

  @override
  String get errorPolkitNoAgentTitle => 'Polkit erforderlich';

  @override
  String get errorPolkitNoAgentMessage => 'Die Anfrage nach root-Rechten blieb unbeantwortet: es läuft kein polkit-Authentifizierungsagent.';

  @override
  String get errorPolkitNoAgentAction => 'Starte einen polkit-Agenten für deine Arbeitsumgebung (polkit-gnome, lxqt-policykit und ähnliche) oder wechsle in den Einstellungen zum Proxy-Modus.';

  @override
  String get errorVpnPermissionMessage => 'Die VPN-Berechtigung wurde nicht erteilt.';

  @override
  String get errorVpnPermissionAction => 'Erlaube die VPN-Berechtigung im Systemdialog und versuche es erneut.';

  @override
  String get errorHwidBindMessage => 'Der Anbieter verlangt, dieses Gerät per HWID zu verknüpfen.';

  @override
  String get errorHwidBindAction => 'Verknüpfe dieses Gerät im Panel des Anbieters und aktualisiere dann das Abonnement.';

  @override
  String get errorDeviceLimitMessage => 'Der Anbieter hat das Abonnement wegen des Gerätelimits abgelehnt.';

  @override
  String get errorDeviceLimitAction => 'Entferne alte Geräte im Panel des Anbieters oder erhöhe das Gerätelimit.';

  @override
  String get errorConfigInvalidMessage => 'Die Abonnement- oder Serverkonfiguration ist ungültig.';

  @override
  String get errorConfigInvalidAction => 'Prüfe den Link bzw. die Konfiguration und importiere einen gültigen Abonnement-Link.';

  @override
  String get errorAuthDeniedMessage => 'Der Anbieter verweigert den Zugriff auf das Abonnement.';

  @override
  String get errorAuthDeniedAction => 'Prüfe Token bzw. Zugangsdaten und ob das Abonnement noch gültig ist.';

  @override
  String get errorSubUrlInvalidMessage => 'Der Abonnement-Link fehlt oder ist abgelaufen.';

  @override
  String get errorSubUrlInvalidAction => 'Fordere eine neue URL vom Anbieter an und aktualisiere sie in der App.';

  @override
  String get errorSubInsecureHttpMessage => 'Der Abonnement-Link nutzt unverschlüsseltes http, Updates sind blockiert.';

  @override
  String get errorSubInsecureHttpAction => 'Ersetze den Link durch seine https-Version.';

  @override
  String get subInsecureHttpWarning => 'http-Link, Updates blockiert';

  @override
  String get subSwitchToHttps => 'Auf https umstellen';

  @override
  String get errorNetworkMessage => 'Der Server ist derzeit nicht erreichbar.';

  @override
  String get errorNetworkAction => 'Prüfe Internet, DNS und Servererreichbarkeit und versuche es erneut.';

  @override
  String get errorUnknownAction => 'Versuche es erneut. Tritt der Fehler weiterhin auf, prüfe Server und App-Einstellungen.';

  @override
  String get errorFileDialogMessage => 'Diese Desktop-Sitzung hat keine Dateiauswahl: weder ein XDG-Portal-Backend noch zenity/kdialog.';

  @override
  String get errorFileDialogAction => 'Installiere xdg-desktop-portal-gtk (oder zenity) oder füge den Konfigurationstext ein, statt eine Datei zu wählen.';

  @override
  String get errorTunAdminTitle => 'Berechtigung erforderlich';

  @override
  String get errorVpnPermissionTitle => 'Berechtigung erforderlich';

  @override
  String get errorHwidBindTitle => 'Geräteverknüpfung erforderlich';

  @override
  String get errorDeviceLimitTitle => 'Gerätelimit erreicht';

  @override
  String get errorProviderNoHostsTitle => 'Einrichtung beim Anbieter erforderlich';

  @override
  String get errorConfigInvalidTitle => 'Konfigurationsfehler';

  @override
  String get errorAuthDeniedTitle => 'Autorisierung fehlgeschlagen';

  @override
  String get errorSubUrlInvalidTitle => 'Ungültiger Abonnement-Link';

  @override
  String get errorSubInsecureHttpTitle => 'Unsicherer Abonnement-Link';

  @override
  String get errorNetworkTitle => 'Netzwerkfehler';

  @override
  String get errorUnknownTitle => 'Vorgang fehlgeschlagen';

  @override
  String get errorFileDialogTitle => 'Kein Dateidialog';

  @override
  String get serversPin => 'Server anheften';

  @override
  String get serversUnpin => 'Server loslösen';

  @override
  String get serversRename => 'Umbenennen';

  @override
  String get serversRenameTitle => 'Server umbenennen';

  @override
  String get serversRenameHint => 'Servername';

  @override
  String get serversRenameReset => 'Zurücksetzen';

  @override
  String serversRenameOriginal(Object name) {
    return 'Ursprünglicher Name: $name';
  }

  @override
  String get serversEditConfig => 'Konfiguration bearbeiten';

  @override
  String get serverEditorTitle => 'Serverkonfiguration';

  @override
  String get serverEditorSectionGeneral => 'Server';

  @override
  String get serverEditorSectionSecurity => 'Sicherheit';

  @override
  String get serverEditorSectionTransport => 'Transport';

  @override
  String get serverEditorSectionProtocol => 'Protokolleinstellungen';

  @override
  String get serverEditorAddress => 'Adresse';

  @override
  String get serverEditorPort => 'Port';

  @override
  String get serverEditorPassword => 'Passwort';

  @override
  String get serverEditorMethod => 'Verschlüsselungsmethode';

  @override
  String get serverEditorEncryption => 'Verschlüsselung';

  @override
  String get serverEditorSecurityMode => 'Sicherheitsmodus';

  @override
  String get serverEditorFingerprint => 'Fingerprint (uTLS)';

  @override
  String get serverEditorAlpn => 'ALPN (durch Komma getrennt)';

  @override
  String get serverEditorAllowInsecure => 'Unsicheres Zertifikat erlauben (insecure)';

  @override
  String get serverEditorPbk => 'Öffentlicher Schlüssel (pbk)';

  @override
  String get serverEditorSid => 'Short ID (sid)';

  @override
  String get serverEditorSpx => 'SpiderX (spx)';

  @override
  String get serverEditorPinnedCert => 'Gepinntes Zertifikat (SHA-256)';

  @override
  String get serverEditorVerifyCertName => 'Zertifikatsname prüfen';

  @override
  String get serverEditorPqv => 'Post-Quanten-Schlüssel (ML-DSA-65)';

  @override
  String get serverEditorEarlyData => 'Early Data, Bytes';

  @override
  String get serverEditorPadding => 'Padding, Bytes';

  @override
  String get serverEditorExtra => 'Extra (JSON)';

  @override
  String get serverEditorAuthority => 'Authority';

  @override
  String get serverEditorSeed => 'Seed';

  @override
  String get serverEditorHttpMethod => 'HTTP-Methode';

  @override
  String get serverEditorIssueVision => 'Vision läuft nur über TCP mit TLS oder REALITY.';

  @override
  String get serverEditorIssueFlow => 'Diesen Flow kennt der Kern nicht und verwirft die ganze Konfiguration.';

  @override
  String get serverEditorIssueRealityTransport => 'Über diesen Transport läuft REALITY nicht.';

  @override
  String get serverEditorIssueRealityKey => 'REALITY braucht den öffentlichen Schlüssel des Servers.';

  @override
  String get serverEditorIssueEncryption => 'Encryption muss none oder ein mlkem768x25519plus-Schlüssel sein.';

  @override
  String get serverEditorIssueNoSecurity => 'Ohne TLS, REALITY oder Encryption erlaubt der Kern nur private Adressen.';

  @override
  String get serverEditorTransportType => 'Typ';

  @override
  String get serverEditorPath => 'Pfad';

  @override
  String get serverEditorServiceName => 'gRPC-Dienstname';

  @override
  String get serverEditorMode => 'Modus';

  @override
  String get serverEditorHeaderType => 'Header-Typ';

  @override
  String get serverEditorAuth => 'Auth-Passwort';

  @override
  String get serverEditorObfs => 'Verschleierung (obfs)';

  @override
  String get serverEditorObfsPassword => 'Verschleierungs-Passwort';

  @override
  String get serverEditorUp => 'Upload, Mbit/s';

  @override
  String get serverEditorDown => 'Download, Mbit/s';

  @override
  String get serverEditorMport => 'Port-Hopping (mport)';

  @override
  String get serverEditorHopInterval => 'Hop-Intervall, s';

  @override
  String get serverEditorPinSha256 => 'Zertifikat-Pinning (SHA-256)';

  @override
  String get serverEditorRawConfig => 'Roh-Konfiguration';

  @override
  String get serverEditorRawToggle => 'Als Text bearbeiten';

  @override
  String get serverEditorRawOnlyNote => 'Dieses Format wird als Rohtext bearbeitet';

  @override
  String get serverEditorPreview => 'Ergebnis-Link';

  @override
  String get serverEditorSubscriptionNote => 'Server aus einem Abonnement: Deine Änderungen bleiben beim Aktualisieren erhalten.';

  @override
  String get serverEditorOverriddenNote => 'Konfiguration manuell geändert, Abonnement-Updates ersetzen sie nicht mehr.';

  @override
  String get serverEditorRevert => 'Konfiguration aus dem Abonnement wiederherstellen';

  @override
  String get serverEditorSaved => 'Konfiguration gespeichert';

  @override
  String get serverEditorReconnecting => 'Konfiguration gespeichert, Verbindung wird neu aufgebaut…';

  @override
  String get serverEditorInvalidPort => 'Ungültiger Port';

  @override
  String get serverEditorServerMissing => 'Server existiert nicht mehr';

  @override
  String get appearanceTabGeneral => 'Allgemein';

  @override
  String get appearanceTabThemes => 'Designs';

  @override
  String get appearanceAmoled => 'Reines Schwarz (AMOLED)';

  @override
  String get appearanceAmoledNeedsDark => 'Nur mit dunklem Design verfügbar';

  @override
  String get appearanceHalloween => 'Festliche Gestaltung anzeigen';

  @override
  String get appearanceHalloweenUntil => 'Bis zum 2. November';

  @override
  String get appearanceHaptics => 'Vibration';

  @override
  String get appearanceShowTraffic => 'Geschwindigkeit und Datenmenge';

  @override
  String get appearanceShowTime => 'Verbindungsdauer';

  @override
  String get appearanceShowTrafficSplit => 'VPN- und Direktverkehr getrennt';

  @override
  String get appearanceWaveLatencyColor => 'Wellenfarbe nach Ping';

  @override
  String get appearanceFontTitle => 'Schriftart';

  @override
  String get appearanceFontSystem => 'System';

  @override
  String get settingsResetConfirmTitle => 'Einstellungen zurücksetzen?';

  @override
  String get settingsResetConfirmAction => 'Zurücksetzen';

  @override
  String get settingsXrayResetConfirm => 'Die Standardeinstellungen für den Xray-Kern, TUN und die lokalen Ports werden wiederhergestellt. Das kann nicht rückgängig gemacht werden.';

  @override
  String get settingsPermissionsTitle => 'Berechtigungen';

  @override
  String get settingsPermissionsSubtitle => 'App-Berechtigungen ansehen und widerrufen';

  @override
  String get settingsPermNotifTitle => 'Benachrichtigungen';

  @override
  String get settingsPermNotifDesc => 'VPN-Statusbenachrichtigung und Hinweise zu Abonnement-Updates';

  @override
  String get settingsPermBatteryTitle => 'Uneingeschränkte Hintergrundaktivität';

  @override
  String get settingsPermBatteryDesc => 'Ohne sie kann das System den VPN-Start über die Kachel blockieren';

  @override
  String get settingsPermAutostartTitle => 'Autostart';

  @override
  String get settingsPermAutostartDesc => 'Firmware-Einstellung: Ohne sie startet das VPN eventuell nicht über die Kachel und schaltet sich im Hintergrund ab';

  @override
  String get settingsPermAutostartHint => 'Suche Autostart und Hintergrundaktivität (meist unter Akku) und erlaube beides';

  @override
  String get settingsPermStatusGranted => 'Erteilt';

  @override
  String get settingsPermStatusDenied => 'Verweigert';

  @override
  String get settingsPermCameraTitle => 'Kamera';

  @override
  String get settingsPermCameraDesc => 'Konfigurations-QR-Codes scannen';

  @override
  String get settingsPermInstallTitle => 'Apps installieren';

  @override
  String get settingsPermInstallDesc => 'App-Updates installieren';

  @override
  String get settingsPermOpenAppSettings => 'App-Einstellungen öffnen';

  @override
  String get settingsPermRevokeHint => 'Jede Berechtigung lässt sich in den App-Einstellungen des Systems widerrufen.';

  @override
  String get settingsPermTunHeader => 'TUN-Modus (Linux)';

  @override
  String get settingsPermTunPasswordlessTitle => 'TUN ohne Passwort';

  @override
  String get settingsPermTunDisabled => 'TUN ohne Passwort deaktiviert';

  @override
  String get appearanceNotifSectionTitle => 'Benachrichtigungen';

  @override
  String get appearanceNotifSpeedTitle => 'Verbindungsgeschwindigkeit in der Benachrichtigung';

  @override
  String get appearanceNotifUptimeTitle => 'Verbindungsdauer in der Benachrichtigung';

  @override
  String get appearanceNotifSubUpdatesTitle => 'Benachrichtigungen zu Abonnement-Updates';

  @override
  String get tunRememberInstalled => 'TUN ohne Passwort aktiviert';

  @override
  String get tunRememberFailed => 'TUN-Autorisierung konnte nicht geändert werden';

  @override
  String get settingsRoutingPresetRefilterTitle => 'In Russland gesperrt (Re-filter)';

  @override
  String get settingsRoutingPresetWhitelistTitle => 'Mobilfunk-Whitelists in Russland';

  @override
  String get settingsRoutingGeoUnknownTitle => 'Nicht in den Geo-Datenbanken – wird ignoriert';

  @override
  String get settingsRoutingGeoUnknownHint => 'Bei einem unbekannten Geo-Code verwirft der Kern die gesamte Konfiguration, daher werden solche Einträge vor dem Verbinden entfernt. Wähle oben mit der Globus-Schaltfläche einen vorhandenen Code.';

  @override
  String get settingsRoutingGeoPickerTooltip => 'Geo-Code einfügen';

  @override
  String get settingsRoutingGeoPickerTitle => 'Geo-Codes der mitgelieferten Datenbanken';

  @override
  String get settingsRoutingGeoPickerSearchHint => 'Suche, z. B. telegram';

  @override
  String get settingsRoutingGeoPickerEmpty => 'Keine Codes gefunden';

  @override
  String get settingsRoutingGeoPickerGeosite => 'Domains (geosite)';

  @override
  String get settingsRoutingGeoPickerGeoip => 'IP-Bereiche (geoip)';

  @override
  String get settingsOpenConnections => 'Verbindungen';

  @override
  String get settingsConnectionsTitle => 'Verbindungen';

  @override
  String get connectionsEmpty => 'Noch keine Verbindungen erfasst.';

  @override
  String get connectionsUnavailable => 'Verbindungsliste ist nicht verfügbar.';

  @override
  String get connectionsFilterHint => 'Filter nach Domain, IP, Prozess oder Regel';

  @override
  String connectionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Verbindungen',
      one: '1 Verbindung',
      zero: 'keine Verbindungen',
    );
    return '$_temp0';
  }

  @override
  String get connectionsPause => 'Aktualisierung pausieren';

  @override
  String get connectionsResume => 'Aktualisierung fortsetzen';

  @override
  String get connectionsPaused => 'Pausiert';

  @override
  String get connectionsSourceApi => 'live aus dem Kern';

  @override
  String get connectionsSourceLog => 'aus dem Kernprotokoll';

  @override
  String get connectionsSourceUnavailable => 'keine Quelle';

  @override
  String get connectionsRuleHint => 'Domains und die zutreffende Regel protokolliert der Kern nur bei Protokollebene Info.';

  @override
  String get connectionsRuleHintAction => 'Info setzen';

  @override
  String get connectionsRuleHintApplied => 'Protokollebene des Kerns auf Info gesetzt. Verbinde dich neu, um sie zu übernehmen';

  @override
  String get connectionsRuleDefault => 'keine Regel (Standardaktion)';

  @override
  String get connectionsRuleViaCore => 'entscheidet der Kern (braucht Protokollebene Info)';

  @override
  String get connectionsRuleViaCoreUnseen => 'der Kern entscheidet, die Entscheidung fehlt im Log';

  @override
  String get connectionsVerdictCore => 'KERN';

  @override
  String get connectionsVerdictProxy => 'PROXY';

  @override
  String get connectionsVerdictDirect => 'DIREKT';

  @override
  String get connectionsVerdictBlock => 'BLOCKIERT';

  @override
  String get connectionsClosed => 'geschlossen';

  @override
  String get connectionsAppNamesHint => 'App-Namen liefert das System, und es kennt nur offene Verbindungen – geschlossene bleiben ohne Namen.';

  @override
  String get connectionsSplitTunnelNote => 'Apps außerhalb des Tunnels stehen hier nicht: Android leitet sie daran vorbei. Eine Zeile mit der Regel outside-vpn heißt, dass so eine App selbst eine Verbindung in den Tunnel geschickt und der Kern sie abgewiesen hat.';

  @override
  String subscriptionsExpiredOn(String date) {
    return 'Abonnement am $date abgelaufen';
  }

  @override
  String get subscriptionsExpiredHint => 'Der Anbieter aktualisiert die Serverliste nicht mehr. Verlängere das Abonnement, damit es weiter funktioniert.';

  @override
  String get subscriptionsExpiredNotifTitle => 'Abonnement abgelaufen';

  @override
  String subscriptionsExpiredNotifBody(String name, String date) {
    return '„$name“ ist am $date abgelaufen. Der Anbieter aktualisiert die Serverliste nicht mehr. Verlängere das Abonnement, damit die Server weiter funktionieren.';
  }

  @override
  String get chainTitle => 'Proxy-Kette';

  @override
  String get chainNew => 'Neue Kette';

  @override
  String get chainCreate => 'Kette bauen';

  @override
  String get chainCreateDesc => 'Datenverkehr nacheinander über mehrere Server schicken';

  @override
  String get chainGroupTitle => 'Ketten';

  @override
  String get chainNameLabel => 'Name der Kette';

  @override
  String get chainNameHint => 'Leer lassen, um sie nach der Route zu benennen';

  @override
  String get chainHint => 'Der Datenverkehr läuft von oben nach unten. Mit dem ersten Knoten verbindet sich dieses Gerät, die Adresse des letzten sehen die Websites.';

  @override
  String get chainDeviceNode => 'Dieses Gerät';

  @override
  String get chainInternetNode => 'Internet';

  @override
  String get chainAddNode => 'Knoten hinzufügen';

  @override
  String get chainRemoveNode => 'Knoten entfernen';

  @override
  String get chainExitNodeHint => 'Ausgangsknoten, seine Adresse sehen die Websites';

  @override
  String get chainNodeMissing => 'Server gibt es nicht mehr, die gespeicherte Kopie wird verwendet';

  @override
  String get chainSave => 'Kette speichern';

  @override
  String get chainNeedsTwoNodes => 'Eine Kette braucht mindestens zwei Knoten';

  @override
  String get chainPickNode => 'Server auswählen';

  @override
  String get chainPickSearch => 'Server suchen';

  @override
  String chainPickEmpty(String core) {
    return 'Hier taugt kein Server als Kettenknoten für $core. Einen anderen Kern wählst du unter „Über die App“.';
  }

  @override
  String get chainEdit => 'Kette bearbeiten';

  @override
  String get chainDelete => 'Kette löschen';

  @override
  String get chainRouteLabel => 'Route';

  @override
  String chainMaxNodes(int max) {
    return 'Eine Kette fasst höchstens $max Knoten';
  }

  @override
  String chainDeleteConfirm(String name) {
    return 'Kette „$name“ löschen? Die verwendeten Server bleiben in der Liste.';
  }

  @override
  String chainNodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Knoten',
      one: '1 Knoten',
      zero: 'keine Knoten',
    );
    return '$_temp0';
  }

  @override
  String get settingsInternalsTitle => 'Über die App';

  @override
  String get settingsInternalsSubtitle => 'Version, Kerne, Geo-Datenbanken und aktuelle Sitzung';

  @override
  String get settingsCoreXraySubtitle => 'Standard-Kern. Führt Links, Ketten und fertige Xray-Konfigurationen aus.';

  @override
  String get settingsCoreMihomoSubtitle => 'Clash-kompatibler Kern. Fertige Xray-Konfigurationen bleiben bei Xray.';

  @override
  String get settingsCoreHint => 'Gilt ab der nächsten Verbindung – die laufende Sitzung wird nicht neu gestartet.';

  @override
  String get settingsProxyAuthTitle => 'Passwort für den lokalen Proxy';

  @override
  String get settingsProxyAuthSubtitle => 'Ausschalten, wo es kein Feld dafür gibt – etwa beim WLAN-Proxy';

  @override
  String get settingsProxyAuthUser => 'Benutzername';

  @override
  String get settingsProxyAuthPass => 'Passwort';

  @override
  String get settingsTunnelModeSection => 'Verbindungsmodus';

  @override
  String get settingsTunnelModeVpn => 'VPN';

  @override
  String get settingsTunnelModeVpnSubtitle => 'Der gesamte Geräteverkehr läuft durch den Tunnel';

  @override
  String get settingsTunnelModeProxy => 'Proxy';

  @override
  String get settingsTunnelModeProxySubtitle => 'Nur lokaler Proxy, kein System-VPN';

  @override
  String get settingsTunnelModeHint => 'Der Proxy-Modus startet SOCKS und HTTP auf 127.0.0.1, richte eine App oder das WLAN darauf. Der Proxy steht jeder App auf dem Gerät offen. Routing pro App und das Abfangen von DNS gibt es nur im VPN-Modus.';

  @override
  String get settingsCoreSkipClash => 'Der aktive Server ist eine fertige Clash-Konfiguration – sie läuft unabhängig von der Kernauswahl nur auf mihomo.';

  @override
  String get settingsCoreSkipCustom => 'Der aktive Server ist eine fertige Xray-JSON-Konfiguration und läuft daher unabhängig vom gewählten Kern über libxray. mihomo braucht ein Abonnement mit normalen Links.';

  @override
  String get settingsCoreSkipChainXrayOnly => 'Der aktive Server ist eine Proxy-Kette mit Knoten, die mihomo nicht verbinden kann – sie läuft unabhängig von der Kernauswahl auf Xray.';

  @override
  String get settingsCoreSkipChainMihomoOnly => 'Der aktive Server ist eine Proxy-Kette mit einem Knoten, den nur mihomo verbinden kann, etwa einem AmneziaWG-Profil – sie läuft unabhängig von der Kernauswahl auf mihomo.';

  @override
  String get settingsCoreSkipAwg => 'Der aktive Server ist ein AmneziaWG-Profil – er läuft unabhängig von der Kernauswahl auf mihomo.';

  @override
  String get settingsCoreSkipPlatform => 'Der mihomo-Kern wird für diese Plattform nicht mitgeliefert – die Verbindung läuft über den Xray-Kern.';

  @override
  String get settingsCoreSkipLinkXrayOnly => 'Der Link des aktiven Servers nutzt einen Transport, für den mihomo bei diesem Protokoll keine Felder hat – er läuft unabhängig von der Kernauswahl auf Xray.';

  @override
  String get settingsCoreSkipLinkMihomoOnly => 'Der Link des aktiven Servers nutzt einen Transport, den Xray 26 entfernt hat – er läuft unabhängig von der Kernauswahl auf mihomo.';

  @override
  String get settingsInternalsCores => 'Kerne';

  @override
  String get settingsInternalsGeo => 'Geo-Datenbanken';

  @override
  String get settingsInternalsSession => 'Aktuelle Sitzung';

  @override
  String get settingsInternalsExits => 'Warum die App beendet wurde';

  @override
  String get settingsInternalsExitsHint => 'Diese Einträge führt das System selbst. Wenn sich das VPN im Hintergrund abgeschaltet hat, kopiere sie mit der Schaltfläche oben und schicke sie uns.';

  @override
  String get settingsInternalsExitSystem => 'Vom System oder der Firmware beendet';

  @override
  String get settingsInternalsExitMemory => 'Dem System ging der Speicher aus';

  @override
  String get settingsInternalsExitCrash => 'Die App ist abgestürzt';

  @override
  String get settingsInternalsExitUser => 'Manuell beendet';

  @override
  String get settingsInternalsExitUserOrUpdate => 'Manuell oder durch ein Update beendet';

  @override
  String get settingsInternalsExitUpdate => 'App-Update oder geänderte Berechtigungen';

  @override
  String get settingsInternalsExitSelf => 'Die App hat sich selbst beendet';

  @override
  String get settingsInternalsExitVpnOn => 'VPN war an';

  @override
  String get appLogTitle => 'App-Protokoll';

  @override
  String get appLogSubtitle => 'Was passiert ist und was fehlschlug – nach App-Teilen';

  @override
  String get appLogSourceApp => 'App';

  @override
  String get appLogSourceAppDesc => 'Oberfläche, Abonnements, Verbindungsaufbau';

  @override
  String get appLogSourceNative => 'Nativer Teil';

  @override
  String get appLogSourceNativeDesc => 'VPN-Dienst, Kachel in den Schnelleinstellungen, Verbindungsfenster';

  @override
  String get appLogSourceExitsDesc => 'Systemeinträge: wann und warum die App beendet wurde';

  @override
  String appLogProblems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Probleme',
      one: '1 Problem',
      zero: 'Keine Probleme',
    );
    return '$_temp0';
  }

  @override
  String get appLogOnlyProblems => 'Nur Probleme';

  @override
  String get appLogEmpty => 'Noch leer';

  @override
  String get appLogCopyAll => 'Gesamtes Protokoll kopieren';

  @override
  String get settingsInternalsBuild => 'App und Gerät';

  @override
  String get settingsInternalsCopyAll => 'Bericht kopieren';

  @override
  String get settingsInternalsCopied => 'Bericht kopiert';

  @override
  String get settingsInternalsNoCores => 'Für diese Plattform werden keine Kerne mitgeliefert';

  @override
  String get settingsInternalsCoreMissing => 'nicht gefunden';

  @override
  String get settingsInternalsVersionFromEngines => 'aus dem Quellcode gebaut';

  @override
  String get settingsInternalsRoleCore => 'Proxy-Engine und TUN';

  @override
  String get settingsInternalsRoleProxy => 'Proxy-Engine';

  @override
  String get settingsInternalsRoleTun => 'TUN-Gerät';

  @override
  String settingsInternalsGeoCodes(int count) {
    return 'Codes: $count';
  }

  @override
  String get settingsInternalsGeoTrimmed => 'Gekürzte Länderdatenbank';

  @override
  String get settingsInternalsGeoTrimmedHint => 'Nur die Codes, die die Vorlagen der App brauchen; eine Regel mit einem anderen Land wird verworfen.';

  @override
  String get settingsInternalsGeoDownload => 'Vollständige Datenbank laden';

  @override
  String settingsInternalsGeoDownloadFailed(String error) {
    return 'Download fehlgeschlagen: $error';
  }

  @override
  String get settingsInternalsStatus => 'Status';

  @override
  String get settingsInternalsStatusError => 'Fehler';

  @override
  String get settingsInternalsEngine => 'Engine';

  @override
  String get settingsInternalsMode => 'Modus';

  @override
  String get settingsInternalsPorts => 'Lokale Ports';

  @override
  String get settingsInternalsClashPort => 'Clash-API-Port';

  @override
  String get settingsInternalsUptime => 'Laufzeit';

  @override
  String get settingsInternalsCorePids => 'Kernprozesse';

  @override
  String get settingsInternalsElevated => 'Administrator';

  @override
  String get settingsInternalsYes => 'ja';

  @override
  String get settingsInternalsNo => 'nein';

  @override
  String get settingsInternalsAppVersion => 'App-Version';

  @override
  String get settingsInternalsPackage => 'Paket';

  @override
  String get settingsInternalsOs => 'System';

  @override
  String get settingsInternalsAbi => 'Architektur';

  @override
  String get settingsInternalsDart => 'Dart';

  @override
  String get settingsInternalsBuildMode => 'Build';

  @override
  String get settingsInternalsUnavailable => '—';

  @override
  String get appearanceCustomColorTitle => 'Eigene Farbe';

  @override
  String get appearanceCustomColorSheetTitle => 'Eigene Farbe';

  @override
  String get appearanceCustomColorHue => 'Farbton';

  @override
  String get appearanceCustomColorSaturation => 'Sättigung';

  @override
  String get appearanceCustomColorBrightness => 'Helligkeit';

  @override
  String get appearanceCustomColorHex => 'HEX-Code';

  @override
  String get appearanceCustomColorInvalid => 'Sechs Hex-Ziffern, zum Beispiel 7B2CBF';

  @override
  String get appearanceCustomColorApply => 'Übernehmen';

  @override
  String get appearanceCustomColorVariant => 'Palette';

  @override
  String get appearanceCustomColorVariantCalm => 'Ruhig';

  @override
  String get appearanceCustomColorVariantVibrant => 'Kräftig';

  @override
  String get appearanceCustomColorVariantExact => 'Exakt';

  @override
  String get appearanceCustomColorVariantHint => 'Sättigung und Helligkeit wirken nur bei „Exakt“ – die anderen beiden wählen sie selbst.';

  @override
  String get appearanceUiScaleTitle => 'Oberflächengröße';

  @override
  String get appearanceUiScaleSubtitle => 'Die gesamte Oberfläche, zusätzlich zur Skalierung des Systems.';

  @override
  String get appearanceIconShapeTitle => 'Symbolform';

  @override
  String get appearanceIconShapeCircle => 'Kreis';

  @override
  String get subscriptionCardThemeTitle => 'Hintergrund';

  @override
  String get subscriptionCardThemeNone => 'Ohne';

  @override
  String get subscriptionCardThemeInServers => 'In der Serverliste zeigen';

  @override
  String get subscriptionCardLookTitle => 'Kartendesign';

  @override
  String get subscriptionCardVeilTitle => 'Bild abdunkeln';

  @override
  String get subscriptionCardVeilNone => 'Aus';

  @override
  String get subscriptionCardVeilLight => 'Leicht';

  @override
  String get subscriptionCardVeilMedium => 'Mittel';

  @override
  String get subscriptionCardVeilStrong => 'Stark';

  @override
  String get subscriptionCardAutoSelect => 'Auto-Schalter in der Serverliste';

  @override
  String get subscriptionCardAutoSelectHint => 'Fügt der Gruppenkopfzeile einen Schalter „Auto“ hinzu. Ist er an, wählt die App den Server selbst und wechselt, sobald der aktuelle nicht mehr funktioniert.';

  @override
  String get subscriptionCardContentTitle => 'Was angezeigt wird';

  @override
  String get subscriptionCardPresetFull => 'Vollständig';

  @override
  String get subscriptionCardPresetCompact => 'Kompakt';

  @override
  String get subscriptionCardPresetMinimal => 'Minimal';

  @override
  String get subscriptionCardPresetCustom => 'Eigen';

  @override
  String get subscriptionCardElementAnnounce => 'Ankündigung des Anbieters';

  @override
  String get subscriptionCardElementUsage => 'Datenvolumen';

  @override
  String get subscriptionCardElementMeta => 'Ablauf und Aktualisierung';

  @override
  String get subscriptionCardElementActions => 'Schaltflächen';

  @override
  String get subscriptionCardContentHint => 'Warnungen werden immer angezeigt: abgelaufenes Abonnement, unsicherer Link, fehlgeschlagene Aktualisierung.';

  @override
  String get appearanceIconShapeSquare => 'Quadrat';

  @override
  String get appearanceIconShapeArch => 'Bogen';

  @override
  String get appearanceSectionServers => 'Serverliste';

  @override
  String get appearanceSectionUnderButton => 'Unter der Verbinden-Schaltfläche';

  @override
  String get appearanceSectionConnectPanel => 'Hauptbildschirm';

  @override
  String get appearanceConnectPanelLegacy => 'Klassisch';

  @override
  String get appearanceConnectPanelModern => 'Modern';

  @override
  String get appearanceBarMainland => 'Festland';

  @override
  String get appearanceBarIslands => 'Inseln';

  @override
  String get appearancePartTop => 'Oberer Bereich';

  @override
  String get appearancePartBottom => 'Untere Leiste';

  @override
  String get appearanceSectionFeel => 'Touch-Feedback';

  @override
  String get appearanceIconShapeClover => 'Kleeblatt';

  @override
  String get appearanceIconShapeCookie => 'Keks';

  @override
  String get appearanceIconShapeFlower => 'Blume';

  @override
  String get appearanceIconShapeSlanted => 'Schräg';

  @override
  String get appearanceIconShapePill => 'Pille';

  @override
  String get appearanceIconShapeGem => 'Kristall';

  @override
  String get appearanceIconShapeSunny => 'Sonne';

  @override
  String get appearanceIconShapePuffy => 'Wolke';

  @override
  String get appearanceIconShapePebble => 'Kiesel';

  @override
  String get cardImageRejectAspect => 'Das Bild ist zu hoch für eine Karte. Nimm ein breites, etwa 3:2 bis 5:1.';

  @override
  String cardImageRejectSmall(int width) {
    return 'Bild zu klein: mindestens $width px breit.';
  }

  @override
  String cardImageRejectLarge(int width) {
    return 'Bild zu groß: höchstens $width px breit.';
  }

  @override
  String get cardImageRejectUnreadable => 'Bild konnte nicht gelesen werden.';
}
