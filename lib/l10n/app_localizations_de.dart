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
  String get errorProviderConfigTitle => 'Provider-Konfiguration erforderlich';

  @override
  String get errorProviderNoHostsMessage => 'Dem Provider sind für dieses Abonnement keine Hosts zugewiesen.';

  @override
  String get errorProviderNoHostsAction => 'Öffne das Provider-Panel, füge Hosts hinzu oder weise sie zu und aktualisiere dann das Abonnement.';

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
  String get splitAddRussianAppsBypass => 'Russische Apps zum Umgehen hinzufügen';

  @override
  String get splitClear => 'Löschen';

  @override
  String get splitNoRussianAppsFound => 'Keine russischen Apps in der Liste der installierten Apps gefunden';

  @override
  String get splitRussianAppsAlreadyAdded => 'Alle russischen Apps sind bereits in der Umgehungsliste';

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
  String get subscriptionsEmptyHint => 'Tippe auf +, um eine Abonnement-URL hinzuzufügen';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsThemeTitle => 'Erscheinungsbild';

  @override
  String get settingsSplitTitle => 'Split-Tunneling';

  @override
  String get settingsRoutingTitle => 'Routing-Regeln';

  @override
  String settingsSplitConfigured(int count) {
    return '$count Apps konfiguriert';
  }

  @override
  String get settingsRoutingSubtitle => 'Direct- / Proxy- / Block-Regeln und Presets';

  @override
  String get settingsResetRoutingTitle => 'Routing auf Standard zurücksetzen';

  @override
  String get settingsResetRoutingSubtitle => 'Integrierte Routing-Regeln wiederherstellen';

  @override
  String get settingsRoutingResetDone => 'Routing-Regeln zurückgesetzt';

  @override
  String get settingsRoutingHeaderDesc => 'Lege fest, welche Seiten direkt am VPN vorbei gehen, welche zwingend hindurch geleitet und welche blockiert werden. Beginne mit einem Preset und passe dann jede Liste unten an.';

  @override
  String get settingsRoutingPresetsTitle => 'Schnelle Presets';

  @override
  String get settingsRoutingPresetsHint => 'Wähle eine kuratierte Liste und füge sie zur passenden Liste unten hinzu. Einträge können danach bearbeitet oder entfernt werden.';

  @override
  String get settingsRoutingPresetChoose => 'Preset wählen…';

  @override
  String get settingsRoutingPresetAdd => 'Hinzufügen';

  @override
  String get settingsRoutingPresetRuTitle => 'Russische Seiten — Direkt';

  @override
  String get settingsRoutingPresetRuDesc => 'Alle .ru / .рф Domains und großen RU-Dienste umgehen das VPN (fügt Domains zu Direkt hinzu)';

  @override
  String get settingsRoutingPresetRuGeoipTitle => 'Russland-IPs (GeoIP) — Direkt';

  @override
  String get settingsRoutingPresetRuGeoipDesc => 'Alle russischen IP-Bereiche umgehen das VPN per GeoIP — funktioniert im Proxy-Modus';

  @override
  String get settingsRoutingPresetRuGeositeTitle => 'Russische Seiten (GeoSite) — Direkt';

  @override
  String get settingsRoutingPresetRuGeositeDesc => 'Russische Domains aus der GeoSite-Datenbank umgehen das VPN';

  @override
  String get settingsRoutingPresetBanksTitle => 'Banken & Behörden — Direkt';

  @override
  String get settingsRoutingPresetBanksDesc => 'Banken, Zahlungen und Behördenportale umgehen das VPN';

  @override
  String get settingsRoutingPresetLanIpsTitle => 'Lokales Netzwerk — Direkt';

  @override
  String get settingsRoutingPresetLanIpsDesc => 'Private LAN-IP-Bereiche (192.168.x, 10.x, …) umgehen das VPN';

  @override
  String get settingsRoutingPresetAdsTitle => 'Werbung & Tracker — Blockieren';

  @override
  String get settingsRoutingPresetAdsDesc => 'Gängige Werbe-/Analyse-Hosts verwerfen';

  @override
  String get settingsRoutingPresetAdsGeositeTitle => 'Werbung (GeoSite) — Blockieren';

  @override
  String get settingsRoutingPresetAdsGeositeDesc => 'Breite Werbe-/Tracker-Liste aus der GeoSite-Datenbank blockieren';

  @override
  String get settingsRoutingPresetStreamingTitle => 'Streaming — Proxy';

  @override
  String get settingsRoutingPresetStreamingDesc => 'YouTube, Netflix, Twitch zwingend über das VPN';

  @override
  String get settingsRoutingPresetMessengersTitle => 'Messenger — Proxy';

  @override
  String get settingsRoutingPresetMessengersDesc => 'Telegram, Discord, WhatsApp zwingend über das VPN';

  @override
  String settingsRoutingPresetApplied(String name) {
    return '\"$name\" hinzugefügt';
  }

  @override
  String get settingsRoutingDirectTitle => 'Direkt (VPN umgehen)';

  @override
  String get settingsRoutingDirectDesc => 'Domains und IPs hier verbinden sich direkt, ohne VPN.';

  @override
  String get settingsRoutingProxyTitle => 'Proxy (VPN erzwingen)';

  @override
  String get settingsRoutingProxyDesc => 'Domains und IPs hier gehen immer über das VPN.';

  @override
  String get settingsRoutingBlockTitle => 'Blockiert';

  @override
  String get settingsRoutingBlockDesc => 'Domains und IPs hier werden verworfen und verbinden nie.';

  @override
  String get settingsRoutingSyntaxHint => 'Jede Liste akzeptiert Domains und IPs zusammen, durch Komma oder Zeilenumbruch getrennt:\n• ru — jeder *.ru-Host (ein Wort ohne Punkt = Domain-Suffix)\n• vk.com — diese Domain und ihre Subdomains\n• .example.com — nur Subdomains\n• 10.0.0.0/8 oder 1.2.3.4 — IP-Adresse oder CIDR-Bereich\n• geoip:ru / geosite:category-ads-all — GeoIP/Geosite (nur Proxy-Modus)\nPrivate/LAN-IPs und dein Server bleiben automatisch direkt.';

  @override
  String get settingsRoutingValuesHint => 'Eine pro Zeile oder durch Komma getrennt';

  @override
  String get settingsRoutingFinalTitle => 'Übriger Datenverkehr';

  @override
  String get settingsRoutingFinalDesc => 'Standardaktion für Verkehr außerhalb der Regeln.';

  @override
  String get settingsRoutingFinalProxy => 'Proxy';

  @override
  String get settingsRoutingFinalDirect => 'Umgehen';

  @override
  String get settingsRoutingFinalBlock => 'Blockieren';

  @override
  String get settingsRoutingAdvancedTitle => 'Eigene Regeln';

  @override
  String get settingsRoutingAdvancedHint => 'Einzelne Regeln mit eigenem Ein/Aus-Schalter. Werden zusätzlich zu den Listen oben angewendet.';

  @override
  String get settingsRoutingAdvancedEmpty => 'Noch keine eigenen Regeln';

  @override
  String get settingsRoutingAdvancedAdd => 'Regel hinzufügen';

  @override
  String get settingsRoutingRuleNewTitle => 'Neue Regel';

  @override
  String get settingsRoutingRuleEditTitle => 'Regel bearbeiten';

  @override
  String get settingsRoutingRuleName => 'Name';

  @override
  String get settingsRoutingRuleNameHint => 'z. B. Streaming';

  @override
  String get settingsRoutingRuleValues => 'Werte';

  @override
  String get settingsRoutingRuleValuesHint => 'Eines pro Zeile oder durch Komma getrennt';

  @override
  String get settingsRoutingRuleMatchBy => 'Abgleich nach';

  @override
  String get settingsRoutingRuleTypeDomain => 'Domain';

  @override
  String get settingsRoutingRuleTypeIp => 'IP / CIDR';

  @override
  String get settingsRoutingRuleTypeGeoip => 'GeoIP';

  @override
  String get settingsRoutingRuleTypeGeosite => 'GeoSite';

  @override
  String get settingsRoutingRuleAction => 'Aktion';

  @override
  String get settingsRoutingRuleSave => 'Speichern';

  @override
  String get settingsRoutingRuleDeleteConfirm => 'Diese Regel löschen?';

  @override
  String get routingCheatSheetTitle => 'Regeln schreiben';

  @override
  String get routingCheatSheetBody => 'Regeln sind einfach eine Liste: was wohin geht. Jede Zeile ist eine Domain, eine IP oder ein Geo-Tag, daneben die Aktion: direkt raus (umgehen), über das VPN (Proxy) oder blockiert.\n\n## Domains\nvk.com — die Domain selbst und alle Subdomains\nru — alles, was auf .ru endet (einfach ein Wort ohne Punkt)\n.example.com — nur Subdomains, nicht die Domain selbst\nfull:example.com — genau dieser Host, keine Subdomains\nregexp:… — ein regulärer Ausdruck, wenn es kompliziert sein muss\n\n## IP-Adressen\n1.2.3.4 — eine einzelne Adresse\n10.0.0.0/8 — ein ganzer Bereich (CIDR)\n\n## GeoIP — nach Land\ngeoip:ru — alle russischen IPs. Statt ru jedes Land: us, de, cn, ua, kz…\nDazu fertige Pakete: geoip:private (LAN), geoip:telegram, geoip:google.\nNach Land? Genau dafür — geoip kennt sie alle.\n\n## GeoSite — fertige Listen\ngeosite:google, geosite:netflix, geosite:telegram, geosite:category-ads-all…\nDas sind keine Länder, sondern Dienst-Kategorien, die jemand schon zusammengestellt hat.\nLänder gibt es hier kaum (nur geolocation-cn und geolocation-!cn), nach Land ist also eher geoip.\n\n## Am PC (Kern keqrnel)\nGeo funktioniert wie am Handy: das in keqrnel eingebaute xray macht den Abgleich. Es braucht nur geoip.dat und geosite.dat neben keqdroid.exe — im Release liegen sie schon dort. Wenn Geo-Regeln ignoriert wirken, prüf zuerst diese zwei Dateien.\n\n## Reihenfolge\nVon oben nach unten: erst Block, dann dein Server (immer direkt, sonst gibt es eine Schleife), dann Umgehen, dann Proxy. Alles Übrige folgt dem Schalter Übriger Datenverkehr oben.';

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
  String get themeCustomizationTitle => 'Erscheinungsbild';

  @override
  String get themeUseDynamicColors => 'Dynamische Android-Farben verwenden';

  @override
  String get themeUseDynamicColorsSubtitle => 'Dynamische Android-Farben verwenden, wenn verfügbar';

  @override
  String get themeDynamicPaletteHint => 'Die dynamische Android-Palette ist aktiv. Hell/Dunkel funktioniert unabhängig.';

  @override
  String get themeSystemPaletteHint => 'Die System-Akzentpalette ist aktiv. Hell/Dunkel funktioniert unabhängig.';

  @override
  String get themeUseSystemColors => 'System-Akzentfarben verwenden';

  @override
  String get themeUseSystemColorsSubtitle => 'Akzentfarben von Windows oder Linux übernehmen, wenn verfügbar';

  @override
  String get themeCustomPaletteHint => 'Die benutzerdefinierte Palette ist aktiv. Hell/Dunkel funktioniert unabhängig.';

  @override
  String get themeColorThemesTitle => 'Farbthemen';

  @override
  String get serversTwoColumnsTitle => 'Serverliste in zwei Spalten';

  @override
  String get serversTwoColumnsSubtitle => 'Server zweispaltig anzeigen – mehr passt auf den Bildschirm';

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
  String get settingsHwidEnabledHint => 'Einige Provider benötigen die HWID für Abonnement-Updates und Gerätelimits.';

  @override
  String get settingsHwidDisabledHint => 'HWID-Header werden nicht gesendet. Manche Abonnements schlagen fehl, wenn der Provider eine Gerätebindung verlangt.';

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
  String get settingsLanAuthHint => 'Beide Felder gesetzt — Geräte melden sich damit am Proxy an. Leer — kein Passwort (jeder im Netzwerk kann ihn nutzen).';

  @override
  String get settingsLocalPortsTitle => 'Lokale Proxy-Ports';

  @override
  String settingsLocalPortsSubtitle(Object socks, Object http) {
    return 'SOCKS $socks · HTTP $http';
  }

  @override
  String get settingsLocalPortsHint => 'Listen-Ports der lokalen SOCKS5- und HTTP-Proxys (Standard 2080 / 2081). Werden bei der nächsten Verbindung angewendet. Die beiden Ports müssen sich unterscheiden.';

  @override
  String get settingsLocalPortsResetTitle => 'Auf Standard zurücksetzen';

  @override
  String get settingsPortInvalid => 'Geben Sie einen Port zwischen 1 und 65535 ein';

  @override
  String get settingsPortsMustDiffer => 'SOCKS- und HTTP-Port müssen sich unterscheiden';

  @override
  String get settingsTurnOffToChange => 'Zum Ändern der Einstellung ausschalten';

  @override
  String settingsProxyCopied(Object label, Object address) {
    return '$label $address kopiert';
  }

  @override
  String get settingsXrayCoreTitle => 'Kern & Protokolle';

  @override
  String get settingsXrayCoreSubtitle => 'Engine, DNS, XMUX, TUN, Log und Routing';

  @override
  String get settingsXrayDnsSection => 'DNS';

  @override
  String get settingsXrayDnsCustom => 'Eigene DNS-Server';

  @override
  String get settingsXrayDnsCustomHint => 'Eine Adresse pro Zeile (DoH, DoT oder einfach)';

  @override
  String get settingsXrayDnsServers => 'DNS-Server';

  @override
  String get settingsXrayDnsSplitDirect => 'Getrennter Resolver für Direct-Domains';

  @override
  String get settingsXrayDnsSplitDirectHint => 'Verwendet den ersten Server für Domains aus der Direct-Liste';

  @override
  String get settingsXrayDnsQueryStrategy => 'Abfragestrategie';

  @override
  String get settingsXrayDnsDisableCache => 'DNS-Cache deaktivieren';

  @override
  String get settingsXrayXmuxSection => 'XMUX (XHTTP)';

  @override
  String get settingsXrayXmuxEnable => 'XMUX aktivieren';

  @override
  String get settingsXrayXmuxEnableHint => 'Multiplexing für den XHTTP-Transport (clientseitig)';

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
  String get settingsXrayCoreIntro => 'Diese Optionen werden in die generierte Xray-Konfiguration eingefügt. Ändere sie nur, wenn du weißt, was sie bewirken.';

  @override
  String get settingsXrayDnsDefaultNote => 'Standard: Cloudflare und Google DoH';

  @override
  String get settingsXrayXmuxParamsTitle => 'Feineinstellung';

  @override
  String get settingsXrayXmuxParamsHint => 'Leer lassen, um die Xray-Standardwerte zu verwenden. Werte können eine Zahl oder ein Bereich sein (z. B. 16-32).';

  @override
  String get settingsXraySniffingHint => 'Zielprotokoll und Domain aus dem eingehenden Verkehr erkennen';

  @override
  String get settingsXraySniffingRouteOnlyHint => 'Sniffing nur für das Routing nutzen, ohne das Ziel zu überschreiben';

  @override
  String get settingsXrayResetDefaults => 'Auf Standard zurücksetzen';

  @override
  String get settingsXrayResetDone => 'Xray-Kerneinstellungen wiederhergestellt';

  @override
  String get settingsXrayXmuxMaxConcurrency => 'Max. Parallelität';

  @override
  String get settingsXrayXmuxMaxConnections => 'Max. Verbindungen';

  @override
  String get settingsXrayXmuxCMaxReuseTimes => 'Limit für Verbindungs-Wiederverwendung';

  @override
  String get settingsXrayXmuxHMaxRequestTimes => 'Max. Anfragen pro Stream';

  @override
  String get settingsXrayXmuxHMaxReusableSecs => 'Stream-Wiederverwendungszeit (Sek.)';

  @override
  String get settingsXrayXmuxHKeepAlivePeriod => 'Keep-Alive-Intervall (Sek.)';

  @override
  String get settingsTunSection => 'TUN-Modus';

  @override
  String get settingsTunSectionNote => 'Optionen der sing-box-TUN-Schnittstelle (Desktop). Gelten ab der nächsten Verbindung.';

  @override
  String get settingsTunStackTitle => 'Netzwerk-Stack';

  @override
  String get settingsTunStackSystemHint => 'Kernel-TCP/IP-Stack — am schnellsten, Standard';

  @override
  String get settingsTunStackGvisorHint => 'Userspace-Stack — bessere Kompatibilität, etwas langsamer. Erfordert einen mit gVisor gebauten Core (Cores aus App 0.7.1 und älter beenden sich mit Code 1)';

  @override
  String get settingsTunStackMixedHint => 'system für TCP, gVisor für UDP. Erfordert einen mit gVisor gebauten Core (Cores aus App 0.7.1 und älter beenden sich mit Code 1)';

  @override
  String get settingsTunMtu => 'MTU';

  @override
  String get settingsTunMtuHint => '576–65535, Standard 1400';

  @override
  String get settingsTunUdpTimeout => 'UDP-Timeout (Sek.)';

  @override
  String get settingsTunUdpTimeoutHint => 'NAT-Lebensdauer inaktiver UDP-Sitzungen, Standard 300';

  @override
  String get settingsTunStrictRouteTitle => 'Strict Route';

  @override
  String get settingsTunStrictRouteHint => 'Verhindert, dass Traffic am TUN vorbeiläuft. Unter Windows kann es das Routing stören, wenn ein anderes VPN (z. B. Tailscale) aktiv ist';

  @override
  String get settingsTunStrictRouteAuto => 'Auto';

  @override
  String get settingsTunStrictRouteAutoHint => 'Linux: an, Windows: aus';

  @override
  String get settingsTunStrictRouteOn => 'An';

  @override
  String get settingsTunStrictRouteOff => 'Aus';

  @override
  String get settingsTunEin => 'Endpoint-independent NAT';

  @override
  String get settingsTunEinHint => 'Full-Cone-NAT für UDP — hilft P2P und Spielen. Nur gVisor-/mixed-Stack';

  @override
  String get settingsTunAutoRoute => 'Auto Route';

  @override
  String get settingsTunAutoRouteHint => 'Fügt Systemrouten automatisch in den Tunnel ein. Nur deaktivieren, wenn Routen manuell verwaltet werden — sonst erreicht kein Traffic das TUN';

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
  String get settingsPingMethodSpeed => 'Geschwindigkeitstest';

  @override
  String get settingsPingMethodSpeedHint => 'Lädt eine feste Datenmenge über den Server herunter und zeigt den Durchsatz in Mbit/s an (funktioniert ohne VPN)';

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
  String get settingsPingCustomUrlHint => 'https:// oder http:// Adresse für die GET-Anfrage';

  @override
  String get settingsPingCustomUrlInvalid => 'Ungültige oder unsichere URL (kein localhost oder private Netzwerke)';

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
  String get subscriptionsShareButton => 'Teilen (QR + Link)';

  @override
  String get subscriptionsShareAction => 'Teilen';

  @override
  String subscriptionsShareFailed(Object error) {
    return 'Teilen fehlgeschlagen: $error';
  }

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
  String get serversPasteVlessHint => 'Füge vless://, vmess://, trojan://, ss://, hysteria2:// oder hy2:// ein (eine pro Zeile)';

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
  String get settingsBackupRestore => 'Sichern & wiederherstellen';

  @override
  String get settingsBackupRestoreSubtitle => 'Split-Tunneling, Abonnements und Server exportieren/importieren';

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
  String get settingsChooseWhatToImport => 'Wähle, was importiert werden soll (ausgewählte Abschnitte ersetzen deine aktuellen Daten).';

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
  String get settingsCreateFileToSave => 'Erstelle eine Datei, die du speichern und auf einem anderen Gerät importieren kannst.';

  @override
  String get settingsPickExportedFile => 'Wähle eine zuvor exportierte Datei und stelle ausgewählte Abschnitte wieder her.';

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
  String get settingsDebugModeHint => 'Zeigt Live-VPN-Metriken in Serverkarten an und ermöglicht das Anzeigen der Xray-Kern-Logs.';

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
  String get settingsHwidWillBeSent => 'Die HWID wird mit Abonnement-Anfragen gesendet';

  @override
  String get settingsHwidNotShared => 'HWID wird nicht geteilt';

  @override
  String get settingsHwidHint => 'Wenn aktiviert, wird die eindeutige ID deines Geräts (HWID) an Abonnement-Server gesendet. Von manchen Providern für die HWID-Bindung erforderlich. Deaktivieren, um die Privatsphäre zu erhöhen.';

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
  String get settingsNameAndValuesRequired => 'Name und Werte sind erforderlich';

  @override
  String get settingsUseOnePerLine => 'Verwende einen Wert pro Zeile oder trenne sie durch Kommas.';

  @override
  String get settingsSmallerOrderFirst => 'Kleinere Zahl = früher geprüft (z. B. 1 vor 50)';

  @override
  String get settingsSmallerOrderWins => 'Wenn zwei Regeln denselben Verkehr betreffen, gewinnt die Regel mit der kleineren Reihenfolge.';

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
  String get splitAddAppInvalid => 'Gib einen gültigen .exe-Namen oder Pfad ein';

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
  String get splitProxyModeWarning => 'Im Proxy-Modus wird Split-Tunneling nicht angewendet — der gesamte Verkehr läuft über den System-Proxy. Wechsle den Verbindungsmodus auf TUN (im Seitenpanel), damit die Regeln pro Prozess wirken.';

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
  String get settingsDebugHintDesktop => 'Zeigt Xray-Sitzungslogs an. Live-VPN-Metriken werden unter der Verbindungstaste angezeigt.';

  @override
  String get settingsDebugHintMobile => 'Zeigt Live-VPN-Metriken in Serverkarten und Xray-Logs an.';

  @override
  String serversErrorLoadingApps(Object error) {
    return 'Fehler beim Laden der Apps: $error';
  }

  @override
  String get desktopConnectionMode => 'Verbindungsmodus';

  @override
  String get desktopModeShort => 'Modus';

  @override
  String get desktopDisconnectBeforeModeChange => 'Trenne die Verbindung, bevor du den Verbindungsmodus änderst';

  @override
  String get settingsDesktopTitle => 'Windows';

  @override
  String get settingsDesktopSubtitle => 'Tray, Autostart, Auto-Connect';

  @override
  String get settingsMinimizeToTray => 'Beim Schließen in Tray minimieren';

  @override
  String get settingsMinimizeToTrayHint => 'Wenn aus, beendet Schließen die App';

  @override
  String get settingsLaunchAtStartup => 'Mit Windows starten';

  @override
  String get settingsLaunchAtStartupHint => 'App beim Anmelden starten';

  @override
  String get settingsAutoConnectOnAutostart => 'Bei Autostart verbinden';

  @override
  String get settingsAutoConnectOnAutostartHint => 'Verbindet mit dem zuletzt gewählten Server im Modus der Seitenleiste. Ohne Admin-Rechte für TUN wird Proxy verwendet';

  @override
  String get settingsAutoConnectRequiresAutostart => 'Zuerst „Mit Windows starten“ aktivieren';

  @override
  String get desktopTunAdminTitle => 'Administratorrechte erforderlich';

  @override
  String get desktopTunAdminMessage => 'Der TUN-Modus benötigt Administratorrechte. Starten Sie die App als Administrator neu — der Modus in der Seitenleiste bleibt erhalten.';

  @override
  String get desktopTunAdminRestart => 'Als Administrator neu starten';

  @override
  String get desktopTunAdminCancel => 'Abbrechen';

  @override
  String get desktopTunAdminRestartFailed => 'Neustart als Administrator fehlgeschlagen';

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
  String get serversManualGroup => 'Manuelle Server';

  @override
  String get serversEmptyGroupHint => 'Keine Server in diesem Abo';

  @override
  String healthCheckChecksPassed(Object passed, Object total) {
    return 'Bestanden: $passed/$total';
  }

  @override
  String get healthCheckServerFields => 'Serverfelder';

  @override
  String get healthCheckDnsResolve => 'DNS-Auflösung';

  @override
  String get healthCheckTcpHandshake => 'TCP-Handshake';

  @override
  String get healthCheckConfigFormat => 'Konfigurationsformat';

  @override
  String get healthCheckNoIpResolved => 'Keine IP aufgelöst';

  @override
  String healthCheckDnsFailed(Object error) {
    return 'Fehler: $error';
  }

  @override
  String get healthCheckUriFormat => 'URI-Format erkannt';

  @override
  String get healthCheckMissingScheme => 'URI-Schema fehlt';

  @override
  String get healthCheckConfigEmpty => 'Konfiguration ist leer';

  @override
  String get statsInLabel => 'In';

  @override
  String get statsTimeLabel => 'Zeit';

  @override
  String get qrScanTitle => 'QR-Code scannen';

  @override
  String get qrScanHint => 'Richten Sie die Kamera auf einen QR-Code';

  @override
  String get qrScanCameraError => 'Kamera nicht verfügbar';

  @override
  String get serversScanQrHint => 'Server- oder Abo-Link';

  @override
  String qrSubscriptionAdded(Object name) {
    return 'Abo hinzugefügt: $name';
  }

  @override
  String get qrNotSubscriptionLink => 'QR-Code enthält keinen Abo-Link';

  @override
  String get settingsHotkeysTitle => 'Tastenkürzel';

  @override
  String get settingsHotkeysSubtitle => 'Kürzel für Verbindung, Modus und Server';

  @override
  String get hotkeysHintGlobal => 'Kürzel funktionieren systemweit — auch wenn das Fenster im Tray versteckt ist. Alle Kürzel sind deaktiviert, bis Sie sie zuweisen.';

  @override
  String get hotkeysHintInApp => 'Unter Linux funktionieren Kürzel, solange das App-Fenster fokussiert ist. Alle Kürzel sind deaktiviert, bis Sie sie zuweisen.';

  @override
  String get hotkeyActionToggleConnection => 'Verbinden / Trennen';

  @override
  String get hotkeyActionToggleConnectionDesc => 'Tunnel für den aktiven Server umschalten';

  @override
  String get hotkeyActionToggleTun => 'TUN-Modus umschalten';

  @override
  String get hotkeyActionToggleTunDesc => 'Zwischen Proxy und TUN wechseln, bei Bedarf mit Neuverbindung';

  @override
  String get hotkeyActionBestPing => 'Server mit bestem Ping';

  @override
  String get hotkeyActionBestPingDesc => 'Zum Server mit dem niedrigsten Ping wechseln';

  @override
  String get hotkeyActionToggleWindow => 'Fenster zeigen / verstecken';

  @override
  String get hotkeyActionToggleWindowDesc => 'Fenster aus dem Tray holen oder verstecken';

  @override
  String get hotkeyNotSet => 'Nicht belegt';

  @override
  String get hotkeyPressKeys => 'Tasten drücken…';

  @override
  String get hotkeyRecordingHint => 'Esc — Abbrechen, Backspace — Löschen';

  @override
  String get hotkeyNeedsModifier => 'Modifikator (Strg/Alt/Umschalt/Win) oder F-Taste nötig';

  @override
  String hotkeyConflictTaken(Object combo) {
    return 'Kürzel $combo wird bereits von einer anderen App verwendet';
  }

  @override
  String get hotkeyClearTooltip => 'Kürzel entfernen';

  @override
  String get hotkeyNoPingData => 'Noch keine Ping-Ergebnisse — zuerst einen Ping-Test starten';

  @override
  String get clipboardNoSubscriptionLink => 'Zwischenablage enthält keinen Abo-Link (http/https)';

  @override
  String get splitTunnelingReconnectHint => 'Änderungen gelten nach dem erneuten Verbinden des VPN';

  @override
  String serversDeleteConfirm(Object name) {
    return 'Server \"$name\" wirklich löschen?';
  }

  @override
  String get errorTunAdminMessage => 'Der TUN-Modus unter Windows benötigt Administratorrechte.';

  @override
  String get errorTunAdminAction => 'Starte die App als Administrator oder wechsle in den Einstellungen in den Proxy-Modus.';

  @override
  String get errorVpnPermissionMessage => 'Die VPN-Berechtigung wurde nicht erteilt.';

  @override
  String get errorVpnPermissionAction => 'Erlaube die VPN-Berechtigung im Systemdialog und versuche es erneut.';

  @override
  String get errorHwidBindMessage => 'Der Anbieter verlangt eine HWID-Bindung für dieses Gerät.';

  @override
  String get errorHwidBindAction => 'Binde dieses Gerät im Anbieter-Panel und aktualisiere dann das Abo.';

  @override
  String get errorDeviceLimitMessage => 'Der Anbieter hat das Abo wegen des Gerätelimits abgelehnt.';

  @override
  String get errorDeviceLimitAction => 'Entferne alte Geräte im Anbieter-Panel oder erhöhe das Gerätelimit.';

  @override
  String get errorConfigInvalidMessage => 'Die Abo- oder Serverkonfiguration ist ungültig.';

  @override
  String get errorConfigInvalidAction => 'Prüfe das URL-/Konfigurationsformat und importiere einen gültigen Abo-Link.';

  @override
  String get errorAuthDeniedMessage => 'Der Zugriff auf das Abo wurde vom Anbieter verweigert.';

  @override
  String get errorAuthDeniedAction => 'Prüfe Token/Zugangsdaten und ob das Abo noch gültig ist.';

  @override
  String get errorSubUrlInvalidMessage => 'Der Abo-Link fehlt oder ist abgelaufen.';

  @override
  String get errorSubUrlInvalidAction => 'Fordere eine neue URL vom Anbieter an und aktualisiere sie in der App.';

  @override
  String get errorSubInsecureHttpMessage => 'Der Abo-Link nutzt unverschlüsseltes http, Updates sind blockiert.';

  @override
  String get errorSubInsecureHttpAction => 'Ersetze den Link durch seine https-Version.';

  @override
  String get subInsecureHttpWarning => 'http-Link — Updates blockiert';

  @override
  String get subSwitchToHttps => 'Auf https umstellen';

  @override
  String get errorNetworkMessage => 'Der Server ist derzeit nicht erreichbar.';

  @override
  String get errorNetworkAction => 'Prüfe Internet, DNS und Servererreichbarkeit und versuche es erneut.';

  @override
  String get errorUnknownAction => 'Versuche es erneut. Tritt der Fehler weiterhin auf, prüfe Server und App-Einstellungen.';

  @override
  String get serversPin => 'Server anheften';

  @override
  String get serversUnpin => 'Server lösen';

  @override
  String get serversPinDesc => 'Angeheftete Server bleiben oben in der Liste';

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
  String get serversEditConfigDesc => 'SNI, Fingerprint, Transport und weitere Parameter';

  @override
  String get serverEditorTitle => 'Serverkonfiguration';

  @override
  String get serverEditorSectionGeneral => 'Server';

  @override
  String get serverEditorSectionSecurity => 'Sicherheit';

  @override
  String get serverEditorSectionTransport => 'Transport';

  @override
  String get serverEditorSectionProtocol => 'Protokoll-Einstellungen';

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
  String get serverEditorSubscriptionNote => 'Server aus einem Abo: Änderungen bleiben beim Abo-Update erhalten.';

  @override
  String get serverEditorOverriddenNote => 'Konfiguration manuell geändert — Abo-Updates ersetzen sie nicht mehr.';

  @override
  String get serverEditorRevert => 'Abo-Konfiguration wiederherstellen';

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
  String get appearanceShowTraffic => 'Datenverkehr anzeigen';

  @override
  String get appearanceShowTrafficSubtitle => 'Chips für Geschwindigkeit und Datenvolumen unter dem Verbindungsknopf';

  @override
  String get appearanceShowTime => 'Verbindungsdauer anzeigen';

  @override
  String get appearanceShowTimeSubtitle => 'Chip mit Sitzungsdauer unter dem Verbindungsknopf';

  @override
  String get appearanceFontTitle => 'Schriftart';

  @override
  String get appearanceFontSystem => 'System';

  @override
  String get settingsResetConfirmTitle => 'Einstellungen zurücksetzen?';

  @override
  String get settingsResetConfirmAction => 'Zurücksetzen';

  @override
  String get settingsResetRoutingConfirm => 'Die integrierten Routing-Regeln werden wiederhergestellt und deine Direct-/Proxy-/Block-Listen verworfen. Das kann nicht rückgängig gemacht werden.';

  @override
  String get settingsLocalPortsResetConfirm => 'Die Standard-Ports des lokalen Proxys werden wiederhergestellt. Das kann nicht rückgängig gemacht werden.';

  @override
  String get settingsXrayResetConfirm => 'Die Standardeinstellungen für Xray-Core und TUN werden wiederhergestellt. Das kann nicht rückgängig gemacht werden.';

  @override
  String get settingsPermissionsTitle => 'Berechtigungen';

  @override
  String get settingsPermissionsSubtitle => 'App-Berechtigungen ansehen und widerrufen';

  @override
  String get settingsPermNotifTitle => 'Benachrichtigungen';

  @override
  String get settingsPermNotifDesc => 'VPN-Statusleiste und Abo-Update-Hinweise';

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
  String get settingsPermRevokeHint => 'Jede Berechtigung lässt sich in den System-App-Einstellungen widerrufen.';

  @override
  String get settingsPermTunHeader => 'TUN-MODUS (LINUX)';

  @override
  String get settingsPermTunPasswordlessTitle => 'TUN ohne Passwort';

  @override
  String get settingsPermTunPasswordlessSubtitle => 'TUN-Modus starten, ohne jedes Mal das polkit-Passwort einzugeben';

  @override
  String get settingsPermTunDisabled => 'TUN ohne Passwort deaktiviert';

  @override
  String get appearanceNotifSectionTitle => 'BENACHRICHTIGUNG';

  @override
  String get appearanceNotifSpeedTitle => 'Verbindungsgeschwindigkeit in Benachrichtigung';

  @override
  String get appearanceNotifSpeedSubtitle => '↓/↑-Geschwindigkeit in der VPN-Statusbenachrichtigung anzeigen';

  @override
  String get appearanceNotifUptimeTitle => 'Verbindungszeit in Benachrichtigung';

  @override
  String get appearanceNotifUptimeSubtitle => 'Sitzungsdauer in der VPN-Statusbenachrichtigung anzeigen';

  @override
  String get appearanceNotifSubUpdatesTitle => 'Benachrichtigungen zu Abo-Updates';

  @override
  String get appearanceNotifSubUpdatesSubtitle => 'Benachrichtigen, wenn Abos im Hintergrund aktualisiert werden';

  @override
  String get tunRememberTitle => 'Autorisierung merken?';

  @override
  String get tunRememberMessage => 'Der TUN-Modus benötigt Root und fragt jedes Mal nach deinem Passwort. Eine polkit-Regel installieren, damit er künftig ohne Passwort startet? Zur Installation wirst du einmal nach dem Passwort gefragt.';

  @override
  String get tunRememberWarning => 'Danach kann jedes unter deinem Benutzer laufende Programm den VPN-Core ohne Passwort als Root starten. Rückgängig jederzeit unter „Erweitert → Berechtigungen“.';

  @override
  String get tunRememberEnable => 'Aktivieren';

  @override
  String get tunRememberNotNow => 'Nicht jetzt';

  @override
  String get tunRememberInstalled => 'TUN ohne Passwort aktiviert';

  @override
  String get tunRememberFailed => 'TUN-Autorisierung konnte nicht geändert werden';
}
