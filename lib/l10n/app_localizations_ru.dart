// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'KEQDIS';

  @override
  String vpnConnectedTo(Object serverName) {
    return 'Подключено к: $serverName';
  }

  @override
  String get vpnConnecting => 'Подключение...';

  @override
  String get vpnDisconnecting => 'Отключение...';

  @override
  String vpnTapToConnect(Object serverName) {
    return 'Нажмите для подключения к $serverName';
  }

  @override
  String get vpnSelectServer => 'Выберите сервер ниже';

  @override
  String get vpnSelectServerFirst => 'Сначала выберите сервер';

  @override
  String get updateTitle => 'Доступно обновление';

  @override
  String get updateWhatsNew => 'Что нового:';

  @override
  String get updateActionLater => 'Позже';

  @override
  String get updateActionNow => 'Обновить';

  @override
  String get updateApplying => 'Установка обновления...';

  @override
  String get errorSubscriptionTitle => 'Ошибка подписки';

  @override
  String get errorConnectionPermission => 'Ошибка подключения: разрешение';

  @override
  String get errorConnectionNetwork => 'Ошибка подключения: сеть';

  @override
  String get errorConnectionConfig => 'Ошибка подключения: конфигурация';

  @override
  String get errorConnectionAuth => 'Ошибка подключения: авторизация';

  @override
  String get errorConnectionGeneric => 'Ошибка подключения';

  @override
  String get errorProviderConfigTitle => 'Требуется настройка у провайдера';

  @override
  String get errorProviderNoHostsMessage => 'У провайдера не назначены hosts для этой подписки.';

  @override
  String get errorProviderNoHostsAction => 'Откройте панель провайдера, добавьте или назначьте hosts, затем обновите подписку.';

  @override
  String errorActionLabel(Object action) {
    return 'Действие: $action';
  }

  @override
  String get splitTunnelingTitle => 'Раздельное туннелирование';

  @override
  String get splitModeAllApps => 'Все приложения';

  @override
  String get splitModeSelectedOnly => 'Только выбранные';

  @override
  String get splitModeAllExceptSelected => 'Все кроме выбранных';

  @override
  String get splitSearchHint => 'Поиск приложений...';

  @override
  String get splitNoAppsFound => 'Приложения не найдены';

  @override
  String splitFailedLoadApps(Object error) {
    return 'Не удалось загрузить приложения: $error';
  }

  @override
  String splitSelectedAppsCount(int count) {
    return 'Выбрано приложений: $count';
  }

  @override
  String get splitHideSystemApps => 'Скрыть системные';

  @override
  String get splitShowSystemApps => 'Показать системные';

  @override
  String get splitAddRussianAppsBypass => 'Добавить российские приложения в обход';

  @override
  String get splitClear => 'Очистить';

  @override
  String get splitNoRussianAppsFound => 'Российские приложения не найдены в списке установленных';

  @override
  String get splitRussianAppsAlreadyAdded => 'Все российские приложения уже в списке обхода';

  @override
  String splitAddedRussianApps(int count) {
    return 'Добавлено российских приложений в обход: $count';
  }

  @override
  String get navServers => 'Серверы';

  @override
  String get navSubscriptions => 'Подписки';

  @override
  String get navSettings => 'Настройки';

  @override
  String get serversEmptyTitle => 'Серверов пока нет';

  @override
  String get serversEmptyHint => 'Добавьте подписку во вкладке Подписки';

  @override
  String get subscriptionsTitle => 'Подписки';

  @override
  String get subscriptionsAddButton => 'Добавить подписку';

  @override
  String get subscriptionsEmptyTitle => 'Нет подписок';

  @override
  String get subscriptionsEmptyHint => 'Нажмите + чтобы добавить URL подписки';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsThemeTitle => 'Внешний вид';

  @override
  String get settingsSplitTitle => 'Раздельное туннелирование';

  @override
  String get settingsRoutingTitle => 'Правила маршрутизации';

  @override
  String settingsSplitConfigured(int count) {
    return 'Настроено приложений: $count';
  }

  @override
  String get settingsRoutingSubtitle => 'Правила direct / proxy / block и пресеты';

  @override
  String get settingsResetRoutingTitle => 'Сбросить настройки маршрутизации';

  @override
  String get settingsRoutingResetDone => 'Правила маршрутизации сброшены';

  @override
  String get settingsRoutingHeaderDesc => 'Выберите, какие сайты идут напрямую мимо VPN, какие принудительно через него, а какие блокируются. Начните с пресета, затем при необходимости отредактируйте списки ниже.';

  @override
  String get settingsRoutingPresetsTitle => 'Быстрые пресеты';

  @override
  String get settingsRoutingPresetsHint => 'Выберите готовый список и добавьте его в соответствующее поле ниже. После этого его можно отредактировать.';

  @override
  String get settingsRoutingPresetChoose => 'Выберите пресет…';

  @override
  String get settingsRoutingPresetAdd => 'Добавить';

  @override
  String get settingsRoutingPresetRuTitle => 'Российские сайты — напрямую';

  @override
  String get settingsRoutingPresetRuDesc => 'Все домены .ru / .рф и крупные сервисы РФ идут мимо VPN (добавляет домены в «Напрямую»)';

  @override
  String get settingsRoutingPresetRuGeoipTitle => 'IP России (GeoIP) — напрямую';

  @override
  String get settingsRoutingPresetRuGeoipDesc => 'Все российские диапазоны IP идут мимо VPN через GeoIP — работает в режиме Proxy';

  @override
  String get settingsRoutingPresetRuGeositeTitle => 'Сайты РФ (GeoSite) — Direct';

  @override
  String get settingsRoutingPresetRuGeositeDesc => 'Российские домены из базы GeoSite идут мимо VPN';

  @override
  String get settingsRoutingPresetBanksTitle => 'Банки и госуслуги — напрямую';

  @override
  String get settingsRoutingPresetBanksDesc => 'Банки, платежи и госпорталы идут мимо VPN';

  @override
  String get settingsRoutingPresetLanIpsTitle => 'Локальная сеть — напрямую';

  @override
  String get settingsRoutingPresetLanIpsDesc => 'Приватные диапазоны IP локальной сети (192.168.x, 10.x, …) идут мимо VPN';

  @override
  String get settingsRoutingPresetAdsTitle => 'Реклама и трекеры — блок';

  @override
  String get settingsRoutingPresetAdsDesc => 'Блокировать частые рекламные и аналитические домены';

  @override
  String get settingsRoutingPresetAdsGeositeTitle => 'Реклама (GeoSite) — Block';

  @override
  String get settingsRoutingPresetAdsGeositeDesc => 'Блокировать широкий список рекламы/трекеров из базы GeoSite';

  @override
  String get settingsRoutingPresetStreamingTitle => 'Стриминг — через VPN';

  @override
  String get settingsRoutingPresetStreamingDesc => 'YouTube, Netflix, Twitch принудительно через VPN';

  @override
  String get settingsRoutingPresetMessengersTitle => 'Мессенджеры — через VPN';

  @override
  String get settingsRoutingPresetMessengersDesc => 'Telegram, Discord, WhatsApp принудительно через VPN';

  @override
  String settingsRoutingPresetApplied(String name) {
    return 'Добавлено: «$name»';
  }

  @override
  String get settingsRoutingDirectTitle => 'Напрямую (мимо VPN)';

  @override
  String get settingsRoutingDirectDesc => 'Домены и IP из этого списка подключаются напрямую, без VPN.';

  @override
  String get settingsRoutingProxyTitle => 'Через VPN';

  @override
  String get settingsRoutingProxyDesc => 'Домены и IP из этого списка всегда идут через VPN.';

  @override
  String get settingsRoutingBlockTitle => 'Заблокировано';

  @override
  String get settingsRoutingBlockDesc => 'Домены и IP из этого списка блокируются и не подключаются.';

  @override
  String get settingsRoutingSyntaxHint => 'Каждое поле принимает домены и IP вместе, через запятую или с новой строки:\n• ru — любой хост *.ru (слово без точки = суффикс домена)\n• vk.com — этот домен и его поддомены\n• .example.com — только поддомены\n• 10.0.0.0/8 или 1.2.3.4 — IP-адрес или диапазон CIDR\n• geoip:ru / geosite:refilter — коды GeoIP/Geosite из поставляемых баз\nПриватные IP локальной сети и ваш сервер всегда идут напрямую автоматически.';

  @override
  String get settingsRoutingValuesHint => 'По одному в строке или через запятую';

  @override
  String get settingsRoutingFinalTitle => 'Остальной трафик';

  @override
  String get settingsRoutingFinalDesc => 'Действие по умолчанию для трафика вне правил.';

  @override
  String get settingsRoutingFinalProxy => 'Прокси';

  @override
  String get settingsRoutingFinalDirect => 'Обход';

  @override
  String get settingsRoutingFinalBlock => 'Блок';

  @override
  String get settingsRoutingAdvancedTitle => 'Свои правила';

  @override
  String get settingsRoutingAdvancedHint => 'Отдельные правила с собственным переключателем. Применяются поверх списков выше.';

  @override
  String get settingsRoutingAdvancedEmpty => 'Пока нет своих правил';

  @override
  String get settingsRoutingAdvancedAdd => 'Добавить правило';

  @override
  String get settingsRoutingRuleNewTitle => 'Новое правило';

  @override
  String get settingsRoutingRuleEditTitle => 'Изменить правило';

  @override
  String get settingsRoutingRuleName => 'Название';

  @override
  String get settingsRoutingRuleNameHint => 'напр. Стриминг';

  @override
  String get settingsRoutingRuleValues => 'Значения';

  @override
  String get settingsRoutingRuleValuesHint => 'По одному в строке или через запятую';

  @override
  String get settingsRoutingRuleMatchBy => 'Сопоставлять по';

  @override
  String get settingsRoutingRuleTypeDomain => 'Домен';

  @override
  String get settingsRoutingRuleTypeIp => 'IP / CIDR';

  @override
  String get settingsRoutingRuleTypeGeoip => 'GeoIP';

  @override
  String get settingsRoutingRuleTypeGeosite => 'GeoSite';

  @override
  String get settingsRoutingRuleAction => 'Действие';

  @override
  String get settingsRoutingRuleSave => 'Сохранить';

  @override
  String get settingsRoutingRuleDeleteConfirm => 'Удалить это правило?';

  @override
  String get routingCheatSheetTitle => 'Как писать правила';

  @override
  String get routingCheatSheetBody => 'Правила — это просто список: что куда отправить. Каждая строка — домен, IP или гео-метка, а рядом действие: напрямую (обход), через VPN (прокси) или в блок.\n\n## Домены\nvk.com — сам домен и все его поддомены\nru — всё, что оканчивается на .ru (просто слово без точки)\n.example.com — только поддомены, без самого домена\nfull:example.com — ровно этот адрес, без поддоменов\nregexp:… — если совсем надо, можно регуляркой\n\n## IP-адреса\n1.2.3.4 — один адрес\n10.0.0.0/8 — целый диапазон (CIDR)\n\n## GeoIP — по стране\ngeoip:ru — все российские IP. Вместо ru любая страна: us, de, cn, ua, kz…\nПлюс готовые пачки: geoip:private (локалка), geoip:telegram, geoip:google.\nНужно «по стране» — это сюда, geoip знает все.\n\n## GeoSite — готовые списки\ngeosite:google, geosite:netflix, geosite:telegram, geosite:category-ads-all…\nЭто не страны, а категории сервисов, которые уже собрали за тебя.\nСтран тут почти нет (только geolocation-cn и geolocation-!cn), так что «по стране» — всё-таки geoip.\n\n## На ПК (ядро keqrnel)\nГео работает так же, как на телефоне: его считает встроенный в keqrnel xray. Нужно лишь, чтобы рядом с keqdroid.exe лежали geoip.dat и geosite.dat — в релизе они уже там. Если гео-правила будто не работают, первым делом проверь эти два файла.\n\n## Порядок\nСверху вниз: сначала блок, потом твой сервер (он всегда напрямую, иначе будет петля), потом обход, потом прокси. Всё, что не подошло, идёт по переключателю «Остальной трафик» вверху.';

  @override
  String get settingsRoutingSavedToast => 'Маршрутизация обновлена';

  @override
  String settingsRoutingItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count записи',
      many: '$count записей',
      few: '$count записи',
      one: '1 запись',
      zero: 'пусто',
    );
    return '$_temp0';
  }

  @override
  String settingsAndroidColorsSubtitle(Object mode) {
    return 'Цвета Android · $mode';
  }

  @override
  String settingsSystemColorsSubtitle(Object mode) {
    return 'Системные цвета · $mode';
  }

  @override
  String get themeModeDark => 'Тёмная';

  @override
  String get themeModeLight => 'Светлая';

  @override
  String get themeCustomizationTitle => 'Внешний вид';

  @override
  String get themeUseDynamicColors => 'Использовать тему Android';

  @override
  String get themeUseDynamicColorsSubtitle => 'Использовать цветовую тему Android';

  @override
  String get themeDynamicPaletteHint => 'Активна динамическая палитра Android. Светлая/тёмная работают независимо.';

  @override
  String get themeSystemPaletteHint => 'Активна системная палитра. Светлая/тёмная работают независимо.';

  @override
  String get themeUseSystemColors => 'Использовать системные цвета';

  @override
  String get themeUseSystemColorsSubtitle => 'Цвета из акцента Windows или Linux, если доступны';

  @override
  String get themeCustomPaletteHint => 'Активна пользовательская палитра. Светлая/тёмная работают независимо.';

  @override
  String get themeColorThemesTitle => 'Цветовые темы';

  @override
  String get serversTwoColumnsTitle => 'Список серверов в две колонки';

  @override
  String get serversTwoColumnsSubtitle => 'Показывать серверы в две колонки — на экране помещается больше';

  @override
  String get settingsLanProxyTitle => 'LAN прокси';

  @override
  String get settingsOff => 'Выкл';

  @override
  String settingsLanSharingOnIp(Object ip) {
    return 'Раздача на $ip';
  }

  @override
  String get settingsHwidTitle => 'Отправлять HWID устройства';

  @override
  String get settingsHwidEnabledRecommended => 'Включено (рекомендуется)';

  @override
  String get settingsHwidDisabled => 'Выключено';

  @override
  String get settingsHwidEnabledHint => 'Некоторые провайдеры требуют HWID для обновления подписок и лимитов устройств.';

  @override
  String get settingsHwidDisabledHint => 'Заголовки HWID не отправляются. Некоторые подписки могут не работать, если провайдер требует привязку устройства.';

  @override
  String get settingsDeviceIpListTitle => 'IP-адреса устройства в сети:';

  @override
  String get settingsIpCopied => 'IP скопирован';

  @override
  String get settingsSetupAnotherDeviceTitle => 'Настройка на другом устройстве:';

  @override
  String get settingsSocks5PortLabel => 'Порт SOCKS5';

  @override
  String get settingsHttpPortLabel => 'Порт HTTP';

  @override
  String get settingsLanUsernameLabel => 'Логин';

  @override
  String get settingsLanPasswordLabel => 'Пароль';

  @override
  String get settingsLanAuthHint => 'Оба поля заполнены — устройства подключаются к прокси по ним. Пусто — без пароля (прокси открыт для всех в вашей сети).';

  @override
  String get settingsLocalPortsTitle => 'Локальные порты прокси';

  @override
  String get settingsLocalPortsHint => 'Порты прослушивания локальных прокси SOCKS5 и HTTP (по умолчанию 2080 / 2081). Применяются при следующем подключении. Порты должны отличаться друг от друга.';

  @override
  String get settingsPortInvalid => 'Введите порт от 1 до 65535';

  @override
  String get settingsPortsMustDiffer => 'Порты SOCKS и HTTP должны отличаться';

  @override
  String get settingsTurnOffToChange => 'Выключите для изменения настройки';

  @override
  String settingsProxyCopied(Object label, Object address) {
    return '$label $address скопирован';
  }

  @override
  String get settingsXrayCoreTitle => 'Настройки ядра';

  @override
  String get settingsXrayCoreSubtitle => 'Порты, DNS, XMUX, TUN, лог и маршрутизация';

  @override
  String get settingsXrayDnsSection => 'DNS';

  @override
  String get settingsXrayDnsCustom => 'Свои DNS-серверы';

  @override
  String get settingsXrayDnsCustomHint => 'Один адрес на строку (DoH, DoT или обычный)';

  @override
  String get settingsXrayDnsServers => 'DNS-серверы';

  @override
  String get settingsXrayDnsSplitDirect => 'Отдельный резолвер для direct-доменов';

  @override
  String get settingsXrayDnsSplitDirectHint => 'Первый сервер — для доменов из списка direct';

  @override
  String get settingsXrayDnsQueryStrategy => 'Стратегия запросов';

  @override
  String get settingsXrayDnsDisableCache => 'Отключить кэш DNS';

  @override
  String get settingsXrayXmuxSection => 'XMUX (XHTTP)';

  @override
  String get settingsXrayXmuxEnable => 'Включить XMUX';

  @override
  String get settingsXrayXmuxEnableHint => 'Мультиплексирование для транспорта XHTTP (только клиент)';

  @override
  String get settingsXrayGeneralSection => 'Общие';

  @override
  String get settingsXrayLogLevel => 'Уровень логов';

  @override
  String get settingsXrayDomainStrategy => 'Стратегия доменов';

  @override
  String get settingsXraySniffing => 'Sniffing на inbound';

  @override
  String get settingsXraySniffingRouteOnly => 'Sniffing route only';

  @override
  String get settingsXrayCoreIntro => 'Параметры попадают в конфиг Xray при подключении. Меняйте и добавляйте свои значения только если знаете для чего они используются';

  @override
  String get settingsXrayDnsDefaultNote => 'По умолчанию: DoH Cloudflare и Google';

  @override
  String get settingsXrayXmuxParamsTitle => 'Тонкая настройка';

  @override
  String get settingsXrayXmuxParamsHint => 'Пустое поле — значение по умолчанию Xray. Можно число или диапазон (например 16-32).';

  @override
  String get settingsXraySniffingHint => 'Определять протокол и домен назначения по входящему трафику';

  @override
  String get settingsXraySniffingRouteOnlyHint => 'Sniffing только для маршрутизации, без подмены адреса';

  @override
  String get settingsXrayResetDefaults => 'Сбросить настройки';

  @override
  String get settingsXrayResetDone => 'Настройки ядра Xray восстановлены';

  @override
  String get settingsXrayXmuxMaxConcurrency => 'Макс. параллельность';

  @override
  String get settingsXrayXmuxMaxConnections => 'Макс. соединений';

  @override
  String get settingsXrayXmuxCMaxReuseTimes => 'Лимит переиспользования';

  @override
  String get settingsXrayXmuxHMaxRequestTimes => 'Макс. запросов на поток';

  @override
  String get settingsXrayXmuxHMaxReusableSecs => 'Время жизни потока (сек)';

  @override
  String get settingsXrayXmuxHKeepAlivePeriod => 'Keep-alive (сек)';

  @override
  String get settingsTunSection => 'TUN-режим';

  @override
  String get settingsTunSectionNote => 'Опции TUN-интерфейса sing-box (десктоп). Применяются при следующем подключении.';

  @override
  String get settingsTunStackTitle => 'Сетевой стек';

  @override
  String get settingsTunStackSystemHint => 'Стек ядра ОС — самый быстрый, по умолчанию';

  @override
  String get settingsTunStackGvisorHint => 'Userspace-стек — лучше совместимость, чуть медленнее. Нужно ядро, собранное с gVisor (ядра из приложения 0.7.1 и старше падают с кодом 1)';

  @override
  String get settingsTunStackMixedHint => 'system для TCP, gVisor для UDP. Нужно ядро, собранное с gVisor (ядра из приложения 0.7.1 и старше падают с кодом 1)';

  @override
  String get settingsTunMtu => 'MTU';

  @override
  String get settingsTunMtuHint => '576–65535, по умолчанию 1400';

  @override
  String get settingsTunUdpTimeout => 'UDP-таймаут (сек)';

  @override
  String get settingsTunUdpTimeoutHint => 'Время жизни NAT-записи простаивающей UDP-сессии, по умолчанию 300';

  @override
  String get settingsTunStrictRouteTitle => 'Strict route';

  @override
  String get settingsTunStrictRouteHint => 'Не даёт трафику утекать мимо TUN. На Windows может ломать маршруты при другом активном VPN (например, Tailscale)';

  @override
  String get settingsTunStrictRouteAuto => 'Авто';

  @override
  String get settingsTunStrictRouteAutoHint => 'Linux: включён, Windows: выключен';

  @override
  String get settingsTunStrictRouteOn => 'Включён';

  @override
  String get settingsTunStrictRouteOff => 'Выключен';

  @override
  String get settingsTunEin => 'Endpoint-independent NAT';

  @override
  String get settingsTunEinHint => 'Full-cone NAT для UDP — помогает P2P и играм. Только стек gVisor/mixed';

  @override
  String get settingsTunAutoRoute => 'Auto route';

  @override
  String get settingsTunAutoRouteHint => 'Автоматически добавляет системные маршруты в туннель. Выключайте только при ручном управлении маршрутами — без него трафик в TUN не попадает';

  @override
  String get settingsPingTitle => 'Пинг серверов';

  @override
  String get settingsPingMethodTitle => 'Метод пинга';

  @override
  String get settingsPingMethodTcp => 'TCP пинг';

  @override
  String get settingsPingMethodTcpHint => 'Быстрая проверка доступности';

  @override
  String get settingsPingMethodIcmp => 'ICMP пинг';

  @override
  String get settingsPingMethodIcmpHint => 'Эхо до IP сервера (некоторые серверы его блокируют)';

  @override
  String get settingsPingMethodUrl => 'HTTP пинг через прокси';

  @override
  String get settingsPingMethodUrlHint => 'Замеряет пинг через GET запрос к серверу';

  @override
  String get settingsPingMethodSpeed => 'Тест скорости';

  @override
  String get settingsPingMethodSpeedHint => 'Качает некоторый объём данных через сервер и показывает скорость в Мбит/с';

  @override
  String get settingsPingTargetTitle => 'URL для HTTP-пинга';

  @override
  String get settingsPingTargetGstatic => 'Google (generate_204)';

  @override
  String get settingsPingTargetCloudflare => 'Cloudflare (trace)';

  @override
  String get settingsPingTargetMicrosoft => 'Microsoft (connect test)';

  @override
  String get settingsPingTargetCustom => 'Свой URL';

  @override
  String get settingsPingCustomUrl => 'Адрес';

  @override
  String get settingsPingCustomUrlHint => 'Адрес для GET-запроса (https:// или http://)';

  @override
  String get settingsPingCustomUrlInvalid => 'Некорректный или небезопасный URL (без localhost и локальных сетей)';

  @override
  String get subscriptionNameLabel => 'Название';

  @override
  String get subscriptionNameHint => 'Моя подписка';

  @override
  String get subscriptionUrlLabel => 'URL';

  @override
  String get subscriptionUrlHint => 'https://example.com/sub?token=...';

  @override
  String get subscriptionsAddSubscription => 'Добавить подписку';

  @override
  String get subscriptionsAddAndFetch => 'Добавить и загрузить';

  @override
  String get subscriptionsEditSubscription => 'Редактировать подписку';

  @override
  String get subscriptionsCopyUrl => 'Копировать URL';

  @override
  String get subscriptionsUrlCopied => 'URL скопирован';

  @override
  String get subscriptionsShareButton => 'Поделиться (QR + ссылка)';

  @override
  String get subscriptionsShareAction => 'Поделиться';

  @override
  String subscriptionsShareFailed(Object error) {
    return 'Не удалось поделиться: $error';
  }

  @override
  String get subscriptionsDeleteSubscription => 'Удалить подписку';

  @override
  String subscriptionsDeleteConfirm(Object name) {
    return 'Вы уверены, что хотите удалить \"$name\"?\n\nЭто также удалит все связанные серверы.';
  }

  @override
  String get subscriptionsRetry => 'Повторить';

  @override
  String get subscriptionsCancel => 'Отмена';

  @override
  String get subscriptionsDelete => 'Удалить';

  @override
  String get subscriptionsSave => 'Сохранить';

  @override
  String get subscriptionsMoveUp => 'Переместить вверх';

  @override
  String get subscriptionsMoveDown => 'Переместить вниз';

  @override
  String get subscriptionsAutoUpdate => 'Обновление';

  @override
  String get subscriptionsOn => 'ВКЛ';

  @override
  String get subscriptionsOff => 'ВЫКЛ';

  @override
  String get subscriptionsExpired => 'Истекла';

  @override
  String get subscriptionsRefreshFailed => 'Ошибка обновления';

  @override
  String get subscriptionsEveryHour => 'Каждый час';

  @override
  String subscriptionsEveryHours(int hours) {
    return 'Каждые $hours часа';
  }

  @override
  String get subscriptionsEveryDay => 'Каждый день';

  @override
  String subscriptionsEveryDays(int days) {
    return 'Каждые $days дня';
  }

  @override
  String get subscriptionsAutoUpdateInterval => 'Интервал автообновления';

  @override
  String subscriptionsCurrentInterval(int hours) {
    return 'каждые $hoursч';
  }

  @override
  String subscriptionsIntervalShort(int hours) {
    return '$hoursч';
  }

  @override
  String get subscriptionsJustNow => 'только что';

  @override
  String subscriptionsMinutesAgo(int minutes) {
    return '$minutesм назад';
  }

  @override
  String subscriptionsHoursAgo(int hours) {
    return '$hoursч назад';
  }

  @override
  String subscriptionsDaysAgo(int days) {
    return '$daysд назад';
  }

  @override
  String subscriptionsInDays(int days) {
    return 'через $daysд';
  }

  @override
  String subscriptionsInHours(int hours) {
    return 'через $hoursч';
  }

  @override
  String get subscriptionsSoon => 'скоро';

  @override
  String get serversAddServer => 'Добавить сервер';

  @override
  String get serversPasteLinks => 'Вставить ссылку(и)';

  @override
  String get serversImportFile => 'Импорт из файла';

  @override
  String get serversNotSupported => 'Не поддерживается в этой сборке';

  @override
  String get serversAddServerTitle => 'Добавить сервер';

  @override
  String get serversPasteVlessHint => 'Вставьте vless://, vmess://, trojan://, ss://, hysteria2:// или hy2:// (по одному на строку)';

  @override
  String get serversPasteHint => 'vless://… или hy2://host:port?auth=…';

  @override
  String get serversAdd => 'Добавить';

  @override
  String get serversManualServers => 'Ручные серверы';

  @override
  String get serversRefreshSubscription => 'Обновить подписку';

  @override
  String get serversPingAll => 'Пинговать все';

  @override
  String get settingsAdvanced => 'Дополнительно';

  @override
  String get settingsAdvancedSubtitle => 'Настройки ядра, пинг, маршрутизация, HWID и отладка';

  @override
  String get settingsBackupRestore => 'Резервное копирование';

  @override
  String get settingsBackupRestoreSubtitle => 'Экспорт/импорт раздельного туннелирования, подписок и серверов';

  @override
  String get settingsSelectAtLeastOne => 'Выберите хотя бы один раздел для экспорта';

  @override
  String get settingsBackupSaved => 'Резервная копия успешно сохранена';

  @override
  String get settingsSelectLocation => 'Выберите место для сохранения';

  @override
  String get settingsExportFile => 'Экспорт в файл';

  @override
  String get settingsImportFile => 'Импорт из файла';

  @override
  String get settingsImportBackup => 'Импорт резервной копии';

  @override
  String get settingsChooseWhatToImport => 'Выберите что импортировать (выбранные разделы заменят текущие данные).';

  @override
  String get settingsSplitTunnelingApps => 'Приложения раздельного туннелирования';

  @override
  String get settingsSubscriptions => 'Подписки';

  @override
  String get settingsServersActive => 'Серверы (и активный сервер)';

  @override
  String get settingsImport => 'Импорт';

  @override
  String get settingsExport => 'Экспорт';

  @override
  String get settingsCreateFileToSave => 'Создайте файл, который можно сохранить и импортировать на другом устройстве.';

  @override
  String get settingsPickExportedFile => 'Выберите ранее экспортированный файл и восстановите выбранные разделы.';

  @override
  String get settingsWorking => 'Работаем...';

  @override
  String settingsImportedSections(int count) {
    return 'Импортировано: $count раздел(ов)';
  }

  @override
  String get settingsDebugMode => 'Режим отладки';

  @override
  String get settingsDebugModeOn => 'Расширенная диагностика включена';

  @override
  String get settingsDebugModeOff => 'Выключен';

  @override
  String get settingsDebugModeHint => 'Показывает живые метрики VPN на карточках серверов и позволяет просматривать логи ядра.';

  @override
  String get settingsOpenXrayLogs => 'Открыть логи ядра';

  @override
  String get settingsXrayCoreLogs => 'Логи ядра';

  @override
  String get settingsRefresh => 'Обновить';

  @override
  String get settingsCopyLogs => 'Скопировать логи';

  @override
  String get settingsAppVersion => 'Версия приложения';

  @override
  String get settingsChecking => 'Проверка...';

  @override
  String get settingsCheckFailed => 'Ошибка проверки';

  @override
  String get settingsUpdateAvailable => 'Доступно обновление';

  @override
  String get settingsUpToDate => 'Актуальная версия';

  @override
  String get settingsNewVersionAvailable => 'Доступна новая версия';

  @override
  String settingsSize(Object size) {
    return 'Размер: $size';
  }

  @override
  String get settingsDownloading => 'Загрузка...';

  @override
  String get settingsCheckForUpdates => 'Проверить обновления';

  @override
  String get settingsShareDeviceHwid => 'Делиться HWID устройства';

  @override
  String get settingsHwidWillBeSent => 'HWID будет отправляться с запросами подписок';

  @override
  String get settingsHwidNotShared => 'HWID не передаётся';

  @override
  String get settingsHwidHint => 'Когда включено, уникальный ID вашего устройства (HWID) отправляется серверам подписок. Требуется некоторыми провайдерами для привязки HWID. Отключите для большей приватности.';

  @override
  String get settingsRoutingRules => 'Правила маршрутизации';

  @override
  String get settingsNoRules => 'Нет правил';

  @override
  String get settingsAddCustomRule => 'Добавить своё правило';

  @override
  String get settingsAddRule => 'Добавить правило';

  @override
  String get settingsEditRule => 'Редактировать правило маршрутизации';

  @override
  String get settingsRuleName => 'Название правила';

  @override
  String get settingsType => 'Тип';

  @override
  String get settingsAction => 'Действие';

  @override
  String get settingsValues => 'Значения (что сопоставлять)';

  @override
  String get settingsOrder => 'Порядок (приоритет правила)';

  @override
  String get settingsEnabled => 'Включено';

  @override
  String get settingsNameAndValuesRequired => 'Название и значения обязательны';

  @override
  String get settingsUseOnePerLine => 'По одному значению на строку или через запятую.';

  @override
  String get settingsSmallerOrderFirst => 'Меньшее число = проверяется раньше (например 1 перед 50)';

  @override
  String get settingsSmallerOrderWins => 'Если два правила могут совпасть с одним трафиком, побеждает правило с меньшим порядковым номером.';

  @override
  String get settingsSaveChanges => 'Сохранить изменения';

  @override
  String get settingsDeleteRule => 'Удалить правило';

  @override
  String get settingsAddRuleTooltip => 'Добавить правило';

  @override
  String get settingsDomain => 'Домен';

  @override
  String get settingsIpCidr => 'IP CIDR';

  @override
  String get settingsGeoIp => 'GeoIP';

  @override
  String get settingsGeosite => 'Geosite';

  @override
  String get settingsProcess => 'Процесс';

  @override
  String get settingsProxy => 'Прокси';

  @override
  String get settingsDirect => 'Direct';

  @override
  String get settingsBlock => 'Блокировка';

  @override
  String get settingsEgDomain => 'напр. youtube.com, +google';

  @override
  String get settingsEgIpCidr => 'напр. 1.1.1.1/32, 192.168.0.0/16';

  @override
  String get settingsEgGeoip => 'напр. RU, US, DE';

  @override
  String get settingsEgGeosite => 'напр. category-ads-all';

  @override
  String get settingsEgProcess => 'напр. com.telegram.messenger';

  @override
  String settingsExportFailed(Object error) {
    return 'Ошибка экспорта: $error';
  }

  @override
  String settingsImportFailed(Object error) {
    return 'Ошибка импорта: $error';
  }

  @override
  String settingsDownloadFailed(Object error) {
    return 'Ошибка загрузки: $error';
  }

  @override
  String settingsCheckFailedError(Object error) {
    return 'Ошибка проверки: $error';
  }

  @override
  String get settingsNoXrayLogsYet => 'Логов ядра пока нет';

  @override
  String get settingsLanguageTitle => 'Язык';

  @override
  String settingsLanguageSubtitle(Object language) {
    return '$language';
  }

  @override
  String get settingsLanguageSystem => 'Как в системе';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageGerman => 'Deutsch';

  @override
  String get settingsLanguageChinese => '中文';

  @override
  String get settingsLanguageSheetTitle => 'Выберите язык';

  @override
  String get splitAddApp => 'Добавить';

  @override
  String get splitAddAppTitle => 'Добавить приложение';

  @override
  String get splitAddAppHint => 'Путь к .exe или имя (например chrome.exe)';

  @override
  String get splitAddAppPickFile => 'Обзор…';

  @override
  String get splitAddAppInvalid => 'Укажите имя или путь к .exe';

  @override
  String splitAddAppAdded(Object name) {
    return 'Добавлено: $name';
  }

  @override
  String get splitRunningApps => 'Запущены';

  @override
  String get splitInstalledApps => 'Установлены';

  @override
  String get splitCustomApps => 'Вручную';

  @override
  String get splitClearAll => 'Очистить всё';

  @override
  String get splitProxyModeWarning => 'В режиме Proxy раздельное туннелирование не применяется — весь трафик идёт через системный прокси. Переключите режим подключения на TUN (в боковой панели), чтобы правила для процессов работали.';

  @override
  String get settingsLatestVersionInstalled => 'У вас последняя версия';

  @override
  String get serversPingServer => 'Пропинговать сервер';

  @override
  String get serversHealthCheck => 'Проверка работоспособности';

  @override
  String get serversCopyAddress => 'Копировать адрес сервера';

  @override
  String get serversCopiedToClipboard => 'Скопировано в буфер обмена';

  @override
  String get serversCopyConfig => 'Копировать конфигурацию';

  @override
  String get serversConfigCopied => 'Конфигурация скопирована';

  @override
  String get serversDeleteServer => 'Удалить сервер';

  @override
  String get serversHealthCheckDesc => 'Проверка DNS, TCP и конфигурации';

  @override
  String get settingsDebugHintDesktop => 'Показывает логи сессии Xray. Живые метрики VPN отображаются под кнопкой подключения.';

  @override
  String get settingsDebugHintMobile => 'Показывает живые метрики VPN в карточках серверов и логи Xray.';

  @override
  String serversErrorLoadingApps(Object error) {
    return 'Ошибка загрузки приложений: $error';
  }

  @override
  String get desktopConnectionMode => 'Режим подключения';

  @override
  String get desktopModeShort => 'Режим';

  @override
  String get desktopDisconnectBeforeModeChange => 'Отключитесь перед сменой режима подключения';

  @override
  String get settingsDesktopTitle => 'Windows';

  @override
  String get settingsDesktopSubtitle => 'Трей, автозапуск, автоподключение';

  @override
  String get settingsMinimizeToTray => 'Сворачивать в трей при закрытии';

  @override
  String get settingsMinimizeToTrayHint => 'Если выключено, закрытие окна завершает приложение';

  @override
  String get settingsLaunchAtStartup => 'Запускать с Windows';

  @override
  String get settingsLaunchAtStartupHint => 'Запуск при входе в систему';

  @override
  String get settingsAutoConnectOnAutostart => 'Подключаться при автозапуске';

  @override
  String get settingsAutoConnectOnAutostartHint => 'Подключение к последнему серверу в режиме из боковой панели. Если для TUN нет прав администратора, используется Proxy';

  @override
  String get settingsAutoConnectRequiresAutostart => 'Сначала включите «Запускать с Windows»';

  @override
  String get desktopTunAdminTitle => 'Нужны права администратора';

  @override
  String get desktopTunAdminMessage => 'Режим TUN требует запуск от имени администратора. Перезапустите приложение с повышенными правами — выбранный в боковой панели режим сохранится.';

  @override
  String get desktopTunAdminRestart => 'Перезапустить от администратора';

  @override
  String get desktopTunAdminCancel => 'Отмена';

  @override
  String get desktopTunAdminRestartFailed => 'Не удалось перезапустить от администратора';

  @override
  String get trayMenuTitle => 'KeqDroid';

  @override
  String get trayCloseMenu => 'Закрыть меню';

  @override
  String get trayConnect => 'Подключить';

  @override
  String get trayDisconnect => 'Отключить';

  @override
  String get trayOpenApp => 'Открыть приложение';

  @override
  String get trayExit => 'Выход';

  @override
  String get trayServersSection => 'Серверы';

  @override
  String get trayPickServer => 'Выберите сервер…';

  @override
  String get trayModeProxy => 'Proxy';

  @override
  String get trayModeTun => 'TUN';

  @override
  String get trayStatusConnected => 'Подключено';

  @override
  String get trayStatusDisconnected => 'Отключено';

  @override
  String get trayStatusError => 'Ошибка';

  @override
  String get serversSortTitle => 'Сортировка серверов';

  @override
  String get serversSortDefault => 'По умолчанию';

  @override
  String get serversSortPing => 'Пинг (по возрастанию)';

  @override
  String get serversSortSpeed => 'Скорость (по убыванию)';

  @override
  String get serversSortName => 'Название (А → Я)';

  @override
  String get updateActionSkip => 'Пропустить версию';

  @override
  String updateSizeLabel(Object size) {
    return 'Размер: $size';
  }

  @override
  String get updateOpenDownload => 'Открыть загрузку';

  @override
  String get vpnConnectedGeneric => 'VPN подключён';

  @override
  String serversImportedSummary(Object added, Object total) {
    return 'Добавлено серверов: $added из $total';
  }

  @override
  String get serversManualGroup => 'Ручные серверы';

  @override
  String get serversEmptyGroupHint => 'В этой подписке нет серверов';

  @override
  String healthCheckChecksPassed(Object passed, Object total) {
    return 'Проверок пройдено: $passed/$total';
  }

  @override
  String get healthCheckServerFields => 'Поля сервера';

  @override
  String get healthCheckDnsResolve => 'DNS-резолв';

  @override
  String get healthCheckTcpHandshake => 'TCP-соединение';

  @override
  String get healthCheckConfigFormat => 'Формат конфига';

  @override
  String get healthCheckNoIpResolved => 'IP не получен';

  @override
  String healthCheckDnsFailed(Object error) {
    return 'Ошибка: $error';
  }

  @override
  String get healthCheckUriFormat => 'Формат URI распознан';

  @override
  String get healthCheckMissingScheme => 'Нет схемы URI';

  @override
  String get healthCheckConfigEmpty => 'Конфиг пуст';

  @override
  String get statsInLabel => 'Вх';

  @override
  String get statsTimeLabel => 'Время';

  @override
  String get qrScanTitle => 'Сканировать QR-код';

  @override
  String get qrScanHint => 'Наведите камеру на QR-код';

  @override
  String get qrScanCameraError => 'Камера недоступна';

  @override
  String get serversScanQrHint => 'Ссылка на сервер или подписку';

  @override
  String qrSubscriptionAdded(Object name) {
    return 'Подписка добавлена: $name';
  }

  @override
  String get qrNotSubscriptionLink => 'В QR-коде нет ссылки на подписку';

  @override
  String get settingsHotkeysTitle => 'Горячие клавиши';

  @override
  String get settingsHotkeysSubtitle => 'Сочетания для подключения, режима и серверов';

  @override
  String get hotkeysHintGlobal => 'Хоткеи работают глобально — даже когда окно свёрнуто в трей. Все хоткеи выключены, пока вы их не назначите.';

  @override
  String get hotkeysHintInApp => 'На Linux хоткеи работают, пока окно приложения в фокусе. Все хоткеи выключены, пока вы их не назначите.';

  @override
  String get hotkeyActionToggleConnection => 'Подключить / отключить';

  @override
  String get hotkeyActionToggleConnectionDesc => 'Переключить туннель для активного сервера';

  @override
  String get hotkeyActionToggleTun => 'Переключить режим TUN';

  @override
  String get hotkeyActionToggleTunDesc => 'Переключение между Proxy и TUN, при активном туннеле — с переподключением';

  @override
  String get hotkeyActionBestPing => 'Сервер с лучшим пингом';

  @override
  String get hotkeyActionBestPingDesc => 'Переключиться на сервер с наименьшим пингом';

  @override
  String get hotkeyActionToggleWindow => 'Показать / скрыть окно';

  @override
  String get hotkeyActionToggleWindowDesc => 'Развернуть окно из трея или спрятать его';

  @override
  String get hotkeyNotSet => 'Не задано';

  @override
  String get hotkeyPressKeys => 'Нажмите сочетание…';

  @override
  String get hotkeyRecordingHint => 'Esc — отмена, Backspace — очистить';

  @override
  String get hotkeyNeedsModifier => 'Нужен модификатор (Ctrl/Alt/Shift/Win) или F-клавиша';

  @override
  String hotkeyConflictTaken(Object combo) {
    return 'Сочетание $combo уже занято другим приложением';
  }

  @override
  String get hotkeyClearTooltip => 'Сбросить сочетание';

  @override
  String get hotkeyNoPingData => 'Нет результатов пинга — сначала запустите проверку';

  @override
  String get clipboardNoSubscriptionLink => 'В буфере нет ссылки подписки (http/https)';

  @override
  String get splitTunnelingReconnectHint => 'Изменения применятся после переподключения VPN';

  @override
  String serversDeleteConfirm(Object name) {
    return 'Удалить сервер «$name»?';
  }

  @override
  String get errorTunAdminMessage => 'Режим TUN на Windows требует прав администратора.';

  @override
  String get errorTunAdminAction => 'Запустите приложение от имени администратора или переключитесь на режим Proxy в настройках.';

  @override
  String get errorVpnPermissionMessage => 'Разрешение на VPN не было предоставлено.';

  @override
  String get errorVpnPermissionAction => 'Разрешите VPN в системном диалоге и повторите попытку.';

  @override
  String get errorHwidBindMessage => 'Провайдер требует привязку HWID для этого устройства.';

  @override
  String get errorHwidBindAction => 'Привяжите устройство в панели провайдера и обновите подписку.';

  @override
  String get errorDeviceLimitMessage => 'Провайдер отклонил подписку: достигнут лимит устройств.';

  @override
  String get errorDeviceLimitAction => 'Удалите старые устройства в панели провайдера или увеличьте лимит.';

  @override
  String get errorConfigInvalidMessage => 'Конфигурация подписки или сервера некорректна.';

  @override
  String get errorConfigInvalidAction => 'Проверьте формат ссылки/конфига и импортируйте корректную ссылку подписки.';

  @override
  String get errorAuthDeniedMessage => 'Провайдер отказал в доступе к подписке.';

  @override
  String get errorAuthDeniedAction => 'Проверьте токен/учётные данные и срок действия подписки.';

  @override
  String get errorSubUrlInvalidMessage => 'Ссылка подписки не найдена или устарела.';

  @override
  String get errorSubUrlInvalidAction => 'Запросите новую ссылку у провайдера и обновите её в приложении.';

  @override
  String get errorSubInsecureHttpMessage => 'Ссылка подписки использует открытый http, обновления заблокированы.';

  @override
  String get errorSubInsecureHttpAction => 'Замените ссылку на её https-версию.';

  @override
  String get subInsecureHttpWarning => 'http-ссылка — обновления заблокированы';

  @override
  String get subSwitchToHttps => 'Исправить на https';

  @override
  String get errorNetworkMessage => 'Сервер сейчас недоступен.';

  @override
  String get errorNetworkAction => 'Проверьте интернет, DNS и доступность сервера, затем повторите.';

  @override
  String get errorUnknownAction => 'Повторите операцию. Если ошибка повторяется, проверьте сервер и настройки приложения.';

  @override
  String get serversPin => 'Закрепить сервер';

  @override
  String get serversUnpin => 'Открепить сервер';

  @override
  String get serversPinDesc => 'Закреплённый сервер всегда наверху списка';

  @override
  String get serversRename => 'Переименовать';

  @override
  String get serversRenameTitle => 'Переименовать сервер';

  @override
  String get serversRenameHint => 'Имя сервера';

  @override
  String get serversRenameReset => 'Сбросить';

  @override
  String serversRenameOriginal(Object name) {
    return 'Исходное имя: $name';
  }

  @override
  String get serversEditConfig => 'Редактировать конфигурацию';

  @override
  String get serversEditConfigDesc => 'SNI, fingerprint, транспорт и другие параметры';

  @override
  String get serverEditorTitle => 'Конфигурация сервера';

  @override
  String get serverEditorSectionGeneral => 'Сервер';

  @override
  String get serverEditorSectionSecurity => 'Безопасность';

  @override
  String get serverEditorSectionTransport => 'Транспорт';

  @override
  String get serverEditorSectionProtocol => 'Параметры протокола';

  @override
  String get serverEditorAddress => 'Адрес';

  @override
  String get serverEditorPort => 'Порт';

  @override
  String get serverEditorPassword => 'Пароль';

  @override
  String get serverEditorMethod => 'Метод шифрования';

  @override
  String get serverEditorEncryption => 'Шифрование';

  @override
  String get serverEditorSecurityMode => 'Режим защиты';

  @override
  String get serverEditorFingerprint => 'Отпечаток (uTLS)';

  @override
  String get serverEditorAlpn => 'ALPN (через запятую)';

  @override
  String get serverEditorAllowInsecure => 'Разрешить небезопасный сертификат (insecure)';

  @override
  String get serverEditorPbk => 'Публичный ключ (pbk)';

  @override
  String get serverEditorSid => 'Short ID (sid)';

  @override
  String get serverEditorSpx => 'SpiderX (spx)';

  @override
  String get serverEditorTransportType => 'Тип';

  @override
  String get serverEditorPath => 'Путь';

  @override
  String get serverEditorServiceName => 'Имя gRPC-сервиса';

  @override
  String get serverEditorMode => 'Режим';

  @override
  String get serverEditorHeaderType => 'Тип заголовка';

  @override
  String get serverEditorAuth => 'Пароль (auth)';

  @override
  String get serverEditorObfs => 'Обфускация (obfs)';

  @override
  String get serverEditorObfsPassword => 'Пароль обфускации';

  @override
  String get serverEditorUp => 'Отдача, Мбит/с';

  @override
  String get serverEditorDown => 'Загрузка, Мбит/с';

  @override
  String get serverEditorMport => 'Диапазон портов (mport)';

  @override
  String get serverEditorHopInterval => 'Интервал смены порта, с';

  @override
  String get serverEditorPinSha256 => 'Пиннинг сертификата (SHA-256)';

  @override
  String get serverEditorRawConfig => 'Сырой конфиг';

  @override
  String get serverEditorRawToggle => 'Редактировать как текст';

  @override
  String get serverEditorRawOnlyNote => 'Этот формат редактируется как сырой текст';

  @override
  String get serverEditorPreview => 'Итоговая ссылка';

  @override
  String get serverEditorSubscriptionNote => 'Сервер из подписки: правки сохранятся при её обновлении.';

  @override
  String get serverEditorOverriddenNote => 'Конфиг изменён вручную — обновления подписки его больше не заменяют.';

  @override
  String get serverEditorRevert => 'Вернуть конфиг из подписки';

  @override
  String get serverEditorSaved => 'Конфигурация сохранена';

  @override
  String get serverEditorReconnecting => 'Конфигурация сохранена, переподключение…';

  @override
  String get serverEditorInvalidPort => 'Некорректный порт';

  @override
  String get serverEditorServerMissing => 'Сервер уже удалён';

  @override
  String get appearanceTabGeneral => 'Общие';

  @override
  String get appearanceTabThemes => 'Темы';

  @override
  String get appearanceAmoled => 'Чистый чёрный (AMOLED)';

  @override
  String get appearanceAmoledSubtitle => 'По-настоящему чёрный фон в тёмной теме — экономит заряд на OLED-экранах';

  @override
  String get appearanceAmoledNeedsDark => 'Доступно при включённой тёмной теме';

  @override
  String get appearanceHaptics => 'Тактильная отдача';

  @override
  String get appearanceHapticsSubtitle => 'Вибрация при подключении, смене вкладки и выборе сервера';

  @override
  String get appearanceShowTraffic => 'Показывать трафик';

  @override
  String get appearanceShowTrafficSubtitle => 'Чипы скорости и объёма трафика под кнопкой подключения';

  @override
  String get appearanceShowTime => 'Показывать время подключения';

  @override
  String get appearanceShowTimeSubtitle => 'Чип длительности сессии под кнопкой подключения';

  @override
  String get appearanceFontTitle => 'Шрифт';

  @override
  String get appearanceFontSystem => 'Системный';

  @override
  String get settingsResetConfirmTitle => 'Сбросить настройки?';

  @override
  String get settingsResetConfirmAction => 'Сбросить';

  @override
  String get settingsResetRoutingConfirm => 'Вернутся встроенные правила маршрутизации, ваши списки direct/proxy/block будут удалены. Действие нельзя отменить.';

  @override
  String get settingsXrayResetConfirm => 'Настройки ядра Xray, TUN и локальные порты вернутся к значениям по умолчанию. Действие нельзя отменить.';

  @override
  String get settingsPermissionsTitle => 'Разрешения';

  @override
  String get settingsPermissionsSubtitle => 'Разрешения приложения — посмотреть и отозвать';

  @override
  String get settingsPermNotifTitle => 'Уведомления';

  @override
  String get settingsPermNotifDesc => 'Строка статуса VPN и уведы об обновлении подписок';

  @override
  String get settingsPermStatusGranted => 'Разрешено';

  @override
  String get settingsPermStatusDenied => 'Запрещено';

  @override
  String get settingsPermCameraTitle => 'Камера';

  @override
  String get settingsPermCameraDesc => 'Сканирование QR-кодов конфигураций';

  @override
  String get settingsPermInstallTitle => 'Установка приложений';

  @override
  String get settingsPermInstallDesc => 'Установка обновлений приложения';

  @override
  String get settingsPermOpenAppSettings => 'Открыть настройки приложения';

  @override
  String get settingsPermRevokeHint => 'Отозвать любое разрешение можно в системных настройках приложения.';

  @override
  String get settingsPermTunHeader => 'РЕЖИМ TUN (LINUX)';

  @override
  String get settingsPermTunPasswordlessTitle => 'TUN без пароля';

  @override
  String get settingsPermTunPasswordlessSubtitle => 'Запускать режим TUN без ввода пароля polkit каждый раз';

  @override
  String get settingsPermTunDisabled => 'Беспарольный TUN выключен';

  @override
  String get appearanceNotifSectionTitle => 'УВЕДОМЛЕНИЕ';

  @override
  String get appearanceNotifSpeedTitle => 'Скорость соединения в уведомлении';

  @override
  String get appearanceNotifSpeedSubtitle => 'Показывать скорость ↓/↑ в уведомлении статуса VPN';

  @override
  String get appearanceNotifUptimeTitle => 'Время подключения в уведомлении';

  @override
  String get appearanceNotifUptimeSubtitle => 'Показывать длительность сессии в уведомлении статуса VPN';

  @override
  String get appearanceNotifSubUpdatesTitle => 'Уведомления об обновлении подписок';

  @override
  String get appearanceNotifSubUpdatesSubtitle => 'Показывать уведомление после фонового обновления подписок';

  @override
  String get tunRememberTitle => 'Запомнить авторизацию?';

  @override
  String get tunRememberMessage => 'Режим TUN требует root и спрашивает пароль при каждом запуске. Установить правило polkit, чтобы дальше запускалось без пароля? Один раз потребуется ввести пароль для установки.';

  @override
  String get tunRememberWarning => 'После этого любая программа под вашим пользователем сможет запускать ядро VPN под root без пароля. Отключить можно в «Дополнительно → Разрешения».';

  @override
  String get tunRememberEnable => 'Включить';

  @override
  String get tunRememberNotNow => 'Не сейчас';

  @override
  String get tunRememberInstalled => 'Беспарольный TUN включён';

  @override
  String get tunRememberFailed => 'Не удалось изменить авторизацию TUN';

  @override
  String get settingsRoutingPresetTelegramGeoTitle => 'Telegram (GeoIP+GeoSite) — через VPN';

  @override
  String get settingsRoutingPresetTelegramGeoDesc => 'Telegram по доменам и по диапазонам IP (MTProto ходит на голые IP)';

  @override
  String get settingsRoutingPresetRefilterTitle => 'Заблокировано в РФ (Re-filter) — через VPN';

  @override
  String get settingsRoutingPresetRefilterDesc => 'Домены и IP, заблокированные в России, идут через VPN, остальное — напрямую';

  @override
  String get settingsRoutingGeoUnknownTitle => 'Нет в гео-базах — будет проигнорировано';

  @override
  String get settingsRoutingGeoUnknownHint => 'На неизвестном гео-коде ядро роняет весь конфиг, поэтому такие записи выкидываются перед подключением. Выберите существующий код кнопкой с глобусом выше.';

  @override
  String get settingsRoutingGeoPickerTooltip => 'Вставить гео-код';

  @override
  String get settingsRoutingGeoPickerTitle => 'Гео-коды из поставляемых баз';

  @override
  String get settingsRoutingGeoPickerSearchHint => 'Поиск, например telegram';

  @override
  String get settingsRoutingGeoPickerEmpty => 'Ничего не найдено';

  @override
  String get settingsRoutingGeoPickerGeosite => 'Домены (geosite)';

  @override
  String get settingsRoutingGeoPickerGeoip => 'Диапазоны IP (geoip)';

  @override
  String get settingsOpenConnections => 'Соединения';

  @override
  String get settingsConnectionsTitle => 'Соединения';

  @override
  String get connectionsEmpty => 'Соединений пока не видно.';

  @override
  String get connectionsUnavailable => 'Список соединений недоступен.';

  @override
  String get connectionsFilterHint => 'Фильтр по домену, IP, процессу или правилу';

  @override
  String connectionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count соединений',
      few: '$count соединения',
      one: '1 соединение',
      zero: 'нет соединений',
    );
    return '$_temp0';
  }

  @override
  String get connectionsPause => 'Приостановить обновление';

  @override
  String get connectionsResume => 'Продолжить обновление';

  @override
  String get connectionsPaused => 'Пауза';

  @override
  String get connectionsSourceApi => 'живой снимок ядра';

  @override
  String get connectionsSourceLog => 'из лога ядра';

  @override
  String get connectionsSourceUnavailable => 'нет источника';

  @override
  String get connectionsRuleHint => 'Ядро пишет, какое правило сработало, только на уровне логов Info.';

  @override
  String get connectionsRuleHintAction => 'Включить Info';

  @override
  String get connectionsRuleHintApplied => 'Уровень логов ядра — Info. Переподключитесь, чтобы применить';

  @override
  String get connectionsRuleDefault => 'без правила (действие по умолчанию)';

  @override
  String get connectionsRuleViaCore => 'решает ядро (нужны логи Info)';

  @override
  String get connectionsVerdictCore => 'ЯДРО';

  @override
  String get connectionsVerdictProxy => 'ПРОКСИ';

  @override
  String get connectionsVerdictDirect => 'НАПРЯМУЮ';

  @override
  String get connectionsVerdictBlock => 'БЛОК';

  @override
  String get connectionsClosed => 'закрыто';

  @override
  String subscriptionsExpiredOn(String date) {
    return 'Подписка истекла $date';
  }

  @override
  String get subscriptionsExpiredHint => 'Провайдер больше не обновляет список серверов. Продлите подписку, чтобы она продолжала работать.';

  @override
  String get subscriptionsExpiredNotifTitle => 'Подписка истекла';

  @override
  String subscriptionsExpiredNotifBody(String name, String date) {
    return '«$name» истекла $date. Провайдер перестал обновлять список серверов — продлите подписку, чтобы серверы продолжали работать.';
  }
}
