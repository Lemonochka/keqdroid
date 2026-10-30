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
  String get settingsRoutingTitle => 'Маршрутизация';

  @override
  String settingsSplitConfigured(int count) {
    return 'Настроено приложений: $count';
  }

  @override
  String get settingsRoutingPresetsTitle => 'Готовые списки';

  @override
  String get settingsRoutingPresetRuTitle => 'Российские сайты';

  @override
  String get settingsRoutingPresetAdsTitle => 'Реклама и трекеры';

  @override
  String get settingsRoutingDirectTitle => 'Напрямую';

  @override
  String get settingsRoutingProxyTitle => 'Через VPN';

  @override
  String get settingsRoutingBlockTitle => 'Блокировать';

  @override
  String get settingsRoutingFinalTitle => 'Всё остальное';

  @override
  String get settingsRoutingReconnect => 'Переподключить';

  @override
  String get routingCheatSheetTitle => 'Как писать правила';

  @override
  String get routingCheatSheetBody => 'Маршрут читается как «кто → что → куда». В «Своих сайтах» каждая строка — домен, IP, гео-метка или ссылка на список, а куда они пойдут, выбирает сам маршрут: напрямую, через VPN или в блок.\n\n## Домены\nvk.com — сам домен и все его поддомены\nru — всё, что оканчивается на .ru (просто слово без точки)\n.example.com — только поддомены, без самого домена\nfull:example.com — ровно этот адрес, без поддоменов\nregexp:… — если совсем надо, можно регуляркой\n\n## IP-адреса\n1.2.3.4 — один адрес\n10.0.0.0/8 — целый диапазон (CIDR)\n\n## GeoIP: по стране\ngeoip:ru — все российские IP. Вместо ru любая страна: us, de, cn, ua, kz…\nПлюс готовые пачки: geoip:private (локалка), geoip:telegram, geoip:google.\nНужно «по стране»? Это сюда, geoip знает все.\n\n## GeoSite: готовые списки\ngeosite:google, geosite:netflix, geosite:telegram, geosite:category-ads-all…\nЭто не страны, а категории сервисов, которые уже собрали за вас.\nСтран тут почти нет (только geolocation-cn и geolocation-!cn), так что «по стране» всё-таки geoip.\n\n## На ПК\nГео работает так же, как на телефоне. Нужно лишь, чтобы рядом с keqdroid.exe лежали geoip.dat и geosite.dat. В релизе они уже там. Если гео-правила будто не работают, первым делом проверьте эти два файла.\n\n## Порядок\nКак на экране, сверху вниз: блокировка, отдельные приложения, все приложения. У всех приложений «Напрямую» проверяется раньше «Через VPN». Ваш сервер всегда идёт напрямую раньше всего, иначе будет петля. Всё, что не подошло ни под один маршрут, идёт по строке «Всё остальное».';

  @override
  String settingsRoutingItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count записи',
      many: '$count записей',
      few: '$count записи',
      one: '$count запись',
      zero: 'пусто',
    );
    return '$_temp0';
  }

  @override
  String get routePickEmpty => 'Нет серверов, которые текущее ядро возьмёт отдельным выходом. Готовый конфиг подходит только своему ядру, а цепочки только mihomo.';

  @override
  String settingsRoutingRouteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count маршрута',
      many: '$count маршрутов',
      few: '$count маршрута',
      one: '$count маршрут',
      zero: 'нет маршрутов',
    );
    return '$_temp0';
  }

  @override
  String get routesSectionBlock => 'Блокировка';

  @override
  String get routesSectionApps => 'Приложения';

  @override
  String get routesSectionAllApps => 'Все приложения';

  @override
  String get routesHint => 'Списки «Напрямую», «Через VPN» и «Блокировать» стали маршрутами. Нажмите на маршрут, чтобы изменить его.';

  @override
  String get routesHintDismiss => 'Понятно';

  @override
  String get routeNew => 'Новый маршрут';

  @override
  String get routeNewSubtitle => 'Приложение, сайты или готовый список';

  @override
  String get routeNewSubtitleSites => 'Сайты или готовый список';

  @override
  String get routeEditorTitle => 'Маршрут';

  @override
  String get routeWho => 'Кто';

  @override
  String get routeWhat => 'Что';

  @override
  String get routeWhere => 'Куда';

  @override
  String get routeWhoAllSubtitle => 'Всё, что идёт через VPN';

  @override
  String get routeWhoApps => 'Отдельные приложения';

  @override
  String routeWhoDone(int count) {
    return 'Готово · $count';
  }

  @override
  String get routeWhatAll => 'Весь трафик';

  @override
  String get routeWhatAllSubtitle => 'Всё, что открывает приложение';

  @override
  String get routeWhatSites => 'Свои сайты';

  @override
  String get routeWhatSitesSubtitle => 'Домены, IP и ссылки на списки';

  @override
  String routeWhatPresetValue(String name) {
    return 'Готовый список · $name';
  }

  @override
  String routeWhatSitesValue(String entries) {
    return 'Свои сайты · $entries';
  }

  @override
  String get routeWhereVpnSubtitle => 'Через сервер, к которому подключено приложение';

  @override
  String get routeWhereDirectSubtitle => 'Мимо VPN';

  @override
  String get routeWhereBlockSubtitle => 'Соединения не открываются';

  @override
  String get routeWhereServers => 'Другой сервер';

  @override
  String get routeToVpn => 'через VPN';

  @override
  String get routeToDirect => 'напрямую';

  @override
  String get routeToBlock => 'блокировать';

  @override
  String get routeAllTrafficShort => 'весь трафик';

  @override
  String get routeDisabledShort => 'выключен';

  @override
  String get routeEnabled => 'Маршрут включён';

  @override
  String get routeDeleteConfirm => 'Удалить маршрут?';

  @override
  String get routeServerMissing => 'сервера больше нет, идёт через VPN';

  @override
  String get routeServerUnsupported => 'текущее ядро не возьмёт этот сервер, идёт через VPN';

  @override
  String get routeAppsUnsupported => 'текущее ядро не различает приложения, маршрут не работает';

  @override
  String get routeAppsNeedTun => 'работает только в режиме TUN';

  @override
  String get routeAppsNeedVpn => 'работает только в режиме VPN';

  @override
  String get routingProfileMain => 'Основной';

  @override
  String get routingIgnoreProviderRules => 'Не учитывать правила провайдера';

  @override
  String get routingIgnoreProviderRulesHint => 'Работают только ваши маршруты';

  @override
  String get routingProfileScopeAll => 'Все подписки и свои серверы';

  @override
  String get routingProfileScopeRest => 'Остальные подписки и свои серверы';

  @override
  String routingProfileRouteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count маршрута',
      many: '$count маршрутов',
      few: '$count маршрута',
      one: '$count маршрут',
      zero: 'нет маршрутов',
    );
    return '$_temp0';
  }

  @override
  String routingProfileFinal(String target) {
    return 'всё остальное → $target';
  }

  @override
  String get routingProfileOff => 'Выключен: работает «Основной»';

  @override
  String get routingProfileNoSubscriptions => 'Не привязан ни к одной подписке';

  @override
  String get routingProfileNew => 'Новый профиль';

  @override
  String get routingProfileName => 'Название';

  @override
  String get routingProfileForSubscriptions => 'Для подписок';

  @override
  String routingProfileSubOnOther(String name) {
    return 'сейчас по профилю «$name»';
  }

  @override
  String get routingProfileStartFrom => 'Начать с';

  @override
  String get routingProfileStartCopy => 'Копии «Основного»';

  @override
  String get routingProfileStartCopyHint => 'Те же маршруты, дальше правите под подписку';

  @override
  String get routingProfileStartEmpty => 'Пустого профиля';

  @override
  String get routingProfileStartEmptyHint => 'Только «Всё остальное через VPN»';

  @override
  String get routingProfileCreate => 'Создать';

  @override
  String get routingProfileNoSubscriptionsYet => 'Подписок пока нет: профиль действует на серверы подписок';

  @override
  String get routingProfileRenameTitle => 'Переименовать профиль';

  @override
  String get routingProfileSubscriptions => 'Подписки';

  @override
  String routingProfileDeleteConfirm(String name) {
    return 'Удалить профиль «$name»? Его подписки перейдут на «Основной».';
  }

  @override
  String routeSplitExcluded(String apps) {
    return 'раздельное туннелирование ведёт мимо VPN: $apps';
  }

  @override
  String get routeRefilterUnmatched => '«Всё остальное» теперь идёт напрямую';

  @override
  String settingsRoutingLinkDomains(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted домена по ссылкам',
      many: '$formatted доменов по ссылкам',
      few: '$formatted домена по ссылкам',
      one: '$formatted домен по ссылкам',
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
      other: '$formatted домена',
      many: '$formatted доменов',
      few: '$formatted домена',
      one: '$formatted домен',
    );
    return '$_temp0';
  }

  @override
  String ruleListLoaded(String host, String domains, String when) {
    return '$host — $domains, обновлён $when';
  }

  @override
  String ruleListLoadedStale(String host, String domains, String when) {
    return '$host — $domains, обновлён $when, свежий не загрузился';
  }

  @override
  String ruleListLoading(String host) {
    return '$host — загружается…';
  }

  @override
  String ruleListFailedNetwork(String host) {
    return '$host — не загрузился, повтор при следующем подключении';
  }

  @override
  String ruleListFailedInsecure(String host) {
    return '$host — нужна ссылка, начинающаяся с https';
  }

  @override
  String ruleListFailedHttp(String host, int code) {
    return '$host — сервер ответил $code';
  }

  @override
  String ruleListFailedTooLarge(String host) {
    return '$host — файл больше 30 МБ';
  }

  @override
  String ruleListFailedEmpty(String host) {
    return '$host — в файле нет доменов';
  }

  @override
  String ruleListMemoryWarning(String limit) {
    return 'Больше $limit доменов по ссылкам: ядру понадобится заметно больше памяти, и в фоне система может его закрыть.';
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
  String get themePaletteHint => 'Светлая/тёмная переключается отдельно';

  @override
  String get themeUseSystemColors => 'Использовать системные цвета';

  @override
  String get themeColorThemesTitle => 'Цветовые темы';

  @override
  String get serversColumnsTitle => 'Показывать в несколько колонок';

  @override
  String get serversColumnsNoRoom => 'При таком размере интерфейса не помещаются';

  @override
  String serversColumnsOnlyFit(int count) {
    return 'При таком размере интерфейса помещаются только $count';
  }

  @override
  String get appearanceServerIconThemeColors => 'Красить значки серверов без флага в цвет темы';

  @override
  String get settingsLanProxyTitle => 'LAN прокси';

  @override
  String get settingsOff => 'Выкл';

  @override
  String settingsLanSharingOnIp(Object ip) {
    return 'Раздача на $ip';
  }

  @override
  String settingsLanFirewallHint(Object ports) {
    return 'Если другие устройства не подключаются, откройте порты $ports в межсетевом экране:';
  }

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
  String get settingsLanAuthHint => 'Если оба поля заполнены, устройства подключаются к прокси по ним. Если пусто, пароля нет: прокси открыт для всех в вашей сети.';

  @override
  String get settingsLocalPortsTitle => 'Локальные порты прокси';

  @override
  String get settingsLocalPortsHint => 'SOCKS5 и HTTP, по умолчанию 2080 / 2081, должны отличаться. Применятся при следующем подключении.';

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
  String get settingsXrayCoreSubtitle => 'DNS, Mux, фрагментация, TUN и логи';

  @override
  String get settingsXrayDnsSection => 'DNS';

  @override
  String get settingsXrayDnsCustom => 'Свои DNS-серверы';

  @override
  String get settingsXrayDnsCustomHint => 'Один адрес на строку (DoH, DoT или обычный)';

  @override
  String get settingsXrayDnsCustomHintXray => 'Один адрес на строку (DoH или обычный), DoT в Xray нет';

  @override
  String get settingsXrayDnsServers => 'DNS-серверы';

  @override
  String get settingsXrayDnsSplitDirect => 'Отдельный резолвер для direct-доменов';

  @override
  String get settingsXrayDnsSplitDirectHint => 'Первый сервер отвечает за домены из списка direct';

  @override
  String get settingsXrayDnsSplitDirectSystemHint => 'Домены из списка direct разрешает DNS системы';

  @override
  String get settingsXrayDnsHosts => 'Свои адреса для доменов';

  @override
  String get settingsXrayDnsPolicy => 'Резолвер для отдельных доменов';

  @override
  String get settingsXrayDnsQueryStrategy => 'Стратегия запросов';

  @override
  String get settingsXrayDnsDisableCache => 'Отключить кэш DNS';

  @override
  String get settingsXrayXmuxSection => 'XMUX (XHTTP)';

  @override
  String get settingsXrayXmuxEnable => 'Настраивать XMUX вручную';

  @override
  String get settingsXrayXmuxEnableHint => 'Иначе Xray держит до 3 соединений и меняет каждое через 600-900 запросов или 30-50 минут';

  @override
  String get settingsXrayMuxSection => 'Mux';

  @override
  String get settingsXrayMuxEnable => 'Включить Mux';

  @override
  String get settingsXrayMuxEnableHint => 'Несколько соединений внутри одного: меньше рукопожатий, но на загрузках и замерах скорости обычно хуже.';

  @override
  String get settingsXrayMuxParamsTitle => 'Потоков в одном соединении';

  @override
  String get settingsXrayMuxParamsHint => '-1 отключает мультиплексирование. TCP до 128, UDP до 1024.';

  @override
  String get settingsXrayMuxConcurrency => 'TCP-потоки';

  @override
  String get settingsXrayMuxXudpConcurrency => 'UDP-потоки (XUDP)';

  @override
  String get settingsXrayMuxUdp443Title => 'QUIC (UDP/443)';

  @override
  String get settingsXrayMuxUdp443Reject => 'Отклонять';

  @override
  String get settingsXrayMuxUdp443Allow => 'Пускать в Mux';

  @override
  String get settingsXrayMuxUdp443Skip => 'Мимо Mux';

  @override
  String get settingsXrayGeneralSection => 'Общие';

  @override
  String get settingsXrayLogLevel => 'Уровень логов';

  @override
  String get settingsXrayDomainStrategy => 'Стратегия доменов в правилах';

  @override
  String get settingsXrayConcurrentDial => 'Дозвон по всем адресам сразу';

  @override
  String get settingsXrayConcurrentDialHint => 'Помогает, когда часть адресов сервера заблокирована';

  @override
  String get settingsXraySniffing => 'Определять домены в трафике (sniffing)';

  @override
  String get settingsXraySniffingRouteOnly => 'Использовать домен только для правил';

  @override
  String get settingsXrayDnsDefaultNote => 'По умолчанию: DoH Cloudflare и Google';

  @override
  String get settingsXrayXmuxParamsTitle => 'Тонкая настройка';

  @override
  String get settingsXrayXmuxParamsHint => 'Пусто оставит дефолт Xray. Число или диапазон, например 16-32.';

  @override
  String get settingsXraySniffingHint => 'Определять протокол и домен назначения по входящему трафику';

  @override
  String get settingsXraySniffingRouteOnlyHint => 'Домен из снифера только выбирает правило, а соединение идёт на адрес от приложения.';

  @override
  String get settingsXrayUdpPerAddress => 'UDP по маршрутам для каждого адреса';

  @override
  String get settingsXrayUdpPerAddressHint => 'Выход выбирается по правилам для каждого адреса назначения, а не по первому пакету сокета. P2P через STUN (звонки, игры, торренты) может не установиться напрямую, если правила разводят STUN-сервер и пира по разным выходам.';

  @override
  String get settingsXrayResetDefaults => 'Сбросить настройки';

  @override
  String get settingsXrayResetDone => 'Настройки ядра Xray восстановлены';

  @override
  String get settingsXrayXmuxMaxConcurrency => 'Макс. параллельность';

  @override
  String get settingsXrayXmuxMaxConnections => 'Макс. соединений';

  @override
  String get settingsXrayXmuxOneOfTwo => 'Только одно из двух';

  @override
  String get settingsXrayXmuxConnectionsIgnored => 'Не учитывается, пока заполнена параллельность';

  @override
  String get settingsXrayXmuxCMaxReuseTimes => 'Лимит переиспользования';

  @override
  String get settingsXrayXmuxHMaxRequestTimes => 'Макс. запросов на поток';

  @override
  String get settingsXrayXmuxHMaxReusableSecs => 'Время жизни потока (сек)';

  @override
  String get settingsXrayXmuxHKeepAlivePeriod => 'Keep-alive (сек)';

  @override
  String get settingsXrayFragmentSection => 'Фрагментация';

  @override
  String get settingsXrayFragmentEnable => 'Резать TLS ClientHello';

  @override
  String get settingsXrayFragmentEnableHint => 'Первый пакет уходит кусками, и DPI не видит SNI.';

  @override
  String get settingsXrayNoiseSection => 'Шум перед UDP';

  @override
  String get settingsXrayNoiseEnable => 'Слать шум перед UDP';

  @override
  String get settingsXrayNoiseEnableHint => 'Перед первым настоящим пакетом к серверу уходит мусор. Для hysteria и mkcp, где резать ClientHello нечего.';

  @override
  String get settingsXrayNoiseKindTitle => 'Чем шуметь';

  @override
  String get settingsXrayNoiseKindRand => 'Случайный мусор';

  @override
  String get settingsXrayNoiseKindStr => 'Свой пакет: текстом';

  @override
  String get settingsXrayNoiseKindHex => 'Свой пакет: hex';

  @override
  String get settingsXrayNoiseKindBase64 => 'Свой пакет: base64';

  @override
  String get settingsXrayNoisePacket => 'Пакет';

  @override
  String get settingsXrayNoiseRandLength => 'Длина, байт';

  @override
  String get settingsXrayNoiseRandBytes => 'Значения байт (0-255)';

  @override
  String get settingsXrayNoiseDelay => 'Пауза, мс';

  @override
  String get settingsXrayNoiseReset => 'Повтор, сек';

  @override
  String get settingsXrayNoiseParamsHint => 'Число или диапазон, например 50-100. Пусто оставит выбор ядру.';

  @override
  String get settingsXrayFragmentPacketsTitle => 'Что резать';

  @override
  String get settingsXrayFragmentPacketsTlsHello => 'Только TLS ClientHello';

  @override
  String get settingsXrayFragmentPacketsFirst => 'Первые пакеты потока';

  @override
  String get settingsXrayFragmentParamsTitle => 'Размер куска и пауза';

  @override
  String get settingsXrayFragmentParamsHint => 'Число или диапазон, например 100-200.';

  @override
  String get settingsXrayFragmentLength => 'Размер, байты';

  @override
  String get settingsXrayFragmentInterval => 'Пауза, мс';

  @override
  String get settingsTunSection => 'TUN-режим';

  @override
  String get settingsTunSectionNote => 'Применяются при следующем подключении.';

  @override
  String get settingsTunStackTitle => 'Сетевой стек';

  @override
  String get settingsTunStackSystemHint => 'Стек ОС: самый быстрый, на Windows требует правило фаервола.';

  @override
  String get settingsTunStackGvisorHint => 'Userspace-стек: ни листенера, ни правил фаервола, чуть медленнее. Нужно ядро с gVisor.';

  @override
  String get settingsTunStackMixedHint => 'system для TCP, gVisor для UDP. Как и system, на Windows требует правило фаервола. Нужно ядро с gVisor.';

  @override
  String get settingsTunStackMipsHint => 'Свой userspace-стек mihomo вместо gVisor: легче, со своим контролем перегрузки TCP. Только на ядре mihomo.';

  @override
  String get settingsTunMtu => 'MTU';

  @override
  String get settingsTunMtuHint => '576–65535, по умолчанию 9000';

  @override
  String get settingsTunUdpTimeout => 'UDP-таймаут (сек)';

  @override
  String get settingsTunUdpTimeoutHint => 'Время жизни NAT-записи простаивающей UDP-сессии, по умолчанию 300';

  @override
  String get settingsTunStrictRouteTitle => 'Строгая маршрутизация (strict route)';

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
  String get settingsTunAutoRoute => 'Заворачивать трафик в туннель (auto route)';

  @override
  String get settingsTunAutoRouteHint => 'Добавляет системные маршруты в туннель. Без него трафик в TUN не попадает.';

  @override
  String get settingsTunIpv6 => 'Не выпускать IPv6 мимо туннеля';

  @override
  String get settingsTunIpv6Hint => 'Даёт TUN-интерфейсу IPv6-адрес, иначе весь IPv6 идёт мимо туннеля.';

  @override
  String get settingsFakeIp => 'Fake IP';

  @override
  String get settingsFakeIpHint => 'Мгновенный резолв подменными адресами. В режиме «Прокси» не работает.';

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
  String get settingsPingMethodUrlHint => 'Ходит GET-запросом через сервер и меряет ответ';

  @override
  String get settingsPingKeepAliveTitle => 'Как считать время';

  @override
  String get settingsPingKeepAlive => 'Мерить по прогретому соединению';

  @override
  String get settingsPingKeepAliveHint => 'Запрос уходит дважды, в счёт идёт второй, уже без рукопожатия. Выключено: один запрос со всем прогревом, как при первом открытии сайта.';

  @override
  String get settingsPingAutoTitle => 'Когда пинговать';

  @override
  String get settingsPingAuto => 'Пинговать автоматически';

  @override
  String get settingsPingAutoHint => 'При открытии приложения и сразу после обновления подписки';

  @override
  String get settingsPingMethodSpeed => 'Тест скорости';

  @override
  String get settingsPingMethodSpeedHint => 'Качает через сервер файл и показывает скорость в Мбит/с. Работает и без подключённого VPN.';

  @override
  String get settingsPingTargetTitle => 'Куда ходит пинг';

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
  String subscriptionsQrSaved(Object path) {
    return 'QR-код сохранён: $path';
  }

  @override
  String subscriptionsQrSaveFailed(Object error) {
    return 'Не удалось сохранить QR-код: $error';
  }

  @override
  String get subscriptionsQrSaveTitle => 'Сохранить QR-код';

  @override
  String get subscriptionIdentityTitle => 'Идентичность устройства';

  @override
  String get subscriptionIdentityHint => 'Каким панель видит клиента: HWID, User-Agent и device-заголовки. Действует только на эту подписку.';

  @override
  String get subscriptionIdentityEnable => 'Своя идентичность';

  @override
  String get subscriptionIdentityAppDefault => 'Как у приложения';

  @override
  String get subscriptionIdentityAppDefaultHint => 'Слать настоящее значение устройства';

  @override
  String get subscriptionIdentityHwid => 'HWID';

  @override
  String get subscriptionIdentityHwidOff => 'В дополнительных настройках выключено «Отдавать HWID устройства», поэтому никакой HWID не уходит, в том числе подставной.';

  @override
  String get subscriptionIdentityUserAgent => 'User-Agent';

  @override
  String get subscriptionIdentityDeviceOs => 'ОС устройства';

  @override
  String get subscriptionIdentityDeviceModel => 'Модель устройства';

  @override
  String get subscriptionIdentityOsVersion => 'Версия ОС';

  @override
  String get subscriptionIdentitySectionUsed => 'Уже используется';

  @override
  String get subscriptionIdentitySectionUaAndroid => 'Клиенты для Android';

  @override
  String get subscriptionIdentitySectionUaApple => 'Клиенты для iPhone и iPad';

  @override
  String get subscriptionIdentitySectionUaDesktop => 'Клиенты для компьютера';

  @override
  String get subscriptionIdentitySectionUaCores => 'Ядра и голый http';

  @override
  String get subscriptionIdentitySectionOs => 'Операционные системы';

  @override
  String get subscriptionIdentitySectionApple => 'iPhone и iPad';

  @override
  String get subscriptionIdentitySectionDesktop => 'Компьютеры';

  @override
  String get subscriptionIdentitySectionAndroidRelease => 'Версии Android';

  @override
  String get subscriptionIdentitySectionAndroidBuild => 'Сборки Android';

  @override
  String get subscriptionIdentitySectionIosRelease => 'Версии iOS';

  @override
  String get subscriptionIdentitySectionIosBuild => 'Сборки iOS';

  @override
  String get subscriptionIdentitySearchOrEnter => 'Искать или вписать своё';

  @override
  String get subscriptionIdentityUseTyped => 'Использовать это значение';

  @override
  String get subscriptionIdentityReset => 'Сбросить';

  @override
  String get subscriptionIdentityApply => 'Применить';

  @override
  String get subscriptionsDeleteSubscription => 'Удалить подписку';

  @override
  String subscriptionsDeleteConfirm(Object name) {
    return 'Удалить «$name»?\n\nСерверы этой подписки уйдут вместе с ней.';
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
  String get subscriptionsOff => 'ВЫКЛ';

  @override
  String get subscriptionsExpired => 'Истекла';

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
  String get serversPasteLinksHint => 'Ссылки на серверы или конфиг целиком';

  @override
  String get serversImportFile => 'Импорт из файла';

  @override
  String get serversImportFileHint => 'Файл со ссылками на серверы или конфигом';

  @override
  String get serversAddServerTitle => 'Добавить сервер';

  @override
  String get serversPasteVlessHint => 'По одной ссылке на строку либо конфиг целиком: Xray, Clash, sing-box, AmneziaWG';

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
  String get serverEditorJsonValid => 'Корректный конфиг Xray';

  @override
  String get serverEditorJsonFormat => 'Формат';

  @override
  String get subscriptionsCardMenu => 'Ещё';

  @override
  String get subscriptionsAutoUpdateOff => 'Не обновлять автоматически';

  @override
  String get subscriptionsProviderPage => 'Страница подписки';

  @override
  String get subscriptionsSupport => 'Поддержка';

  @override
  String get subscriptionsLinkOpenFailed => 'Не удалось открыть ссылку';

  @override
  String get settingsAdvancedGroupTraffic => 'Трафик и ядро';

  @override
  String get settingsAdvancedGroupSystem => 'Система';

  @override
  String get settingsAdvancedGroupDiagnostics => 'Диагностика';

  @override
  String get settingsBackupRestore => 'Резервное копирование';

  @override
  String get settingsBackupRestoreSubtitle => 'Экспорт/импорт раздельного туннелирования, подписок, серверов и настроек';

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
  String get settingsChooseWhatToImport => 'Выбранные разделы заменят текущие данные';

  @override
  String get settingsSplitTunnelingApps => 'Раздельное туннелирование';

  @override
  String get settingsSubscriptions => 'Подписки';

  @override
  String get settingsServersActive => 'Серверы, включая активный';

  @override
  String get settingsAppSettings => 'Настройки приложения';

  @override
  String get settingsImport => 'Импорт';

  @override
  String get settingsExport => 'Экспорт';

  @override
  String get settingsCreateFileToSave => 'Файл можно перенести на другое устройство';

  @override
  String get settingsPickExportedFile => 'Сначала файл, потом выбор, что из него восстановить';

  @override
  String get settingsWorking => 'Работаем...';

  @override
  String settingsImportedSections(int count) {
    return 'Импортировано: $count раздел(ов)';
  }

  @override
  String get settingsShareHwidTitle => 'Отдавать HWID устройства';

  @override
  String get settingsShareHwidOn => 'Уходит с запросами подписки';

  @override
  String get settingsShareHwidOff => 'Не передаётся';

  @override
  String get settingsDebugMode => 'Режим отладки';

  @override
  String get settingsDebugModeOn => 'Расширенная диагностика включена';

  @override
  String get settingsDebugModeOff => 'Выключен';

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
  String get settingsDownloading => 'Загрузка...';

  @override
  String get settingsCheckForUpdates => 'Проверить обновления';

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
  String get settingsLanguageFarsi => 'فارسی';

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
  String get splitAddAppHintLinux => 'Путь к программе или её имя (например firefox)';

  @override
  String get splitAddAppInvalidLinux => 'Укажите имя программы или путь к ней';

  @override
  String splitAddAppAdded(Object name) {
    return 'Добавлено: $name';
  }

  @override
  String get splitProxyModeWarning => 'В режиме Proxy раздельное туннелирование не применяется: весь трафик идёт через системный прокси. Переключите режим подключения на TUN (в боковой панели), чтобы правила для процессов работали.';

  @override
  String get settingsLatestVersionInstalled => 'У вас последняя версия';

  @override
  String get serversPingServer => 'Пропинговать сервер';

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
  String get settingsDebugHintDesktop => 'Показывает логи сессии ядра. Живые метрики VPN показываются под кнопкой подключения.';

  @override
  String get settingsDebugHintMobile => 'Показывает живые метрики VPN в карточках серверов и логи ядра.';

  @override
  String get desktopConnectionMode => 'Режим подключения';

  @override
  String get desktopModeShort => 'Режим';

  @override
  String get settingsDesktopTitle => 'Windows';

  @override
  String get settingsDesktopTitleLinux => 'Linux';

  @override
  String get settingsDesktopSubtitle => 'Трей, автозапуск, автоподключение';

  @override
  String get settingsMinimizeToTray => 'Сворачивать в трей при закрытии';

  @override
  String get settingsLaunchAtStartup => 'Запускать с Windows';

  @override
  String get settingsLaunchAtLogin => 'Запускать при входе в систему';

  @override
  String get settingsLaunchAtStartupAdmin => 'Запускать с правами администратора';

  @override
  String get settingsAutostartInTray => 'Запускать в трее, без окна';

  @override
  String get settingsAutostartAdminFailed => 'Права администратора не выданы';

  @override
  String get settingsAutoConnectOnAutostart => 'Подключаться при автозапуске';

  @override
  String get settingsAutoConnectRequiresAutostart => 'Сначала включите «Запускать с Windows»';

  @override
  String get settingsAutoConnectRequiresLogin => 'Сначала включите «Запускать при входе в систему»';

  @override
  String get desktopTunAdminTitle => 'Нужны права администратора';

  @override
  String get desktopTunAdminMessage => 'Для TUN нужны права администратора. Перезапустите приложение с ними, выбранный в боковой панели режим сохранится.';

  @override
  String get desktopTunAdminRestart => 'Перезапустить от администратора';

  @override
  String get desktopTunAdminCancel => 'Отмена';

  @override
  String get desktopTunAdminRestartFailed => 'Не удалось перезапустить от администратора';

  @override
  String get trayConnect => 'Подключить';

  @override
  String get trayDisconnect => 'Отключить';

  @override
  String get trayOpenApp => 'Открыть приложение';

  @override
  String get trayExit => 'Выход';

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
  String get sidebarJumpTitle => 'Быстрый переход';

  @override
  String get desktopRailCollapse => 'Свернуть панель';

  @override
  String get desktopRailExpand => 'Развернуть панель';

  @override
  String get serversScrollToEnd => 'К концу списка';

  @override
  String get serversScrollToTop => 'К началу списка';

  @override
  String get serversJumpToActive => 'Показать в списке';

  @override
  String get exitIpLabel => 'IP, который видят сайты';

  @override
  String get serversAutoSelect => 'Авто';

  @override
  String get serversAutoSelectTooltip => 'Сервер в этой подписке выбирает приложение и меняет его, когда текущий перестаёт работать';

  @override
  String get serversManualGroup => 'Ручные серверы';

  @override
  String get serversEmptyGroupHint => 'В этой подписке нет серверов';

  @override
  String get statsInLabel => 'Вх';

  @override
  String get statsTimeLabel => 'Время';

  @override
  String get statsDownloadLabel => 'Скорость приёма';

  @override
  String get statsUploadLabel => 'Скорость отдачи';

  @override
  String get statsSplitVpnTag => 'VPN';

  @override
  String get statsSplitDirectTag => 'обход';

  @override
  String get statsSplitVpnLabel => 'Через VPN';

  @override
  String get statsSplitDirectLabel => 'Мимо VPN';

  @override
  String get statsSplitTotalLabel => 'Прошло';

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
  String get tvReceiveTitle => 'Принять с телефона';

  @override
  String get tvReceiveSubtitle => 'Подписка с телефона по Wi-Fi';

  @override
  String get tvReceiveHint => 'Отсканируйте код в keqdroid на телефоне. Телефон и телевизор должны быть в одной сети Wi-Fi.';

  @override
  String get tvReceiveWaiting => 'Жду подписку…';

  @override
  String tvReceiveGot(Object name) {
    return 'Получено: $name';
  }

  @override
  String tvReceiveFailed(Object error) {
    return 'Не удалось добавить: $error';
  }

  @override
  String get tvReceiveNoNetwork => 'Телевизор не подключён к сети';

  @override
  String get tvSendTitle => 'Отправить на телевизор';

  @override
  String get tvSendPick => 'Какую подписку отправить?';

  @override
  String get tvSendAction => 'Отправить';

  @override
  String get tvSendDone => 'Подписка отправлена на телевизор';

  @override
  String get tvSendNothing => 'На телефоне нет подписок, отправлять нечего';

  @override
  String get tvSendUnreachable => 'Телевизор не отвечает. Проверьте, что телефон и телевизор в одной сети Wi-Fi и экран приёма на телевизоре открыт.';

  @override
  String get tvSendExpired => 'Код устарел. Откройте экран приёма на телевизоре заново и отсканируйте новый код.';

  @override
  String tvSendRejected(Object error) {
    return 'Телевизор не принял подписку: $error';
  }

  @override
  String get settingsHotkeysTitle => 'Горячие клавиши';

  @override
  String get settingsHotkeysSubtitle => 'Сочетания для подключения, режима и серверов';

  @override
  String get hotkeysHintGlobal => 'Работают из любого окна и даже когда приложение свёрнуто в трей. Пока в строке «Не задано», сочетание не срабатывает.';

  @override
  String get hotkeysHintInApp => 'На Linux ловятся, только пока окно приложения в фокусе. Пока в строке «Не задано», сочетание не срабатывает.';

  @override
  String get hotkeyActionToggleConnection => 'Подключить / отключить';

  @override
  String get hotkeyActionToggleTun => 'Переключить TUN и Proxy';

  @override
  String get hotkeyActionBestPing => 'Перейти на сервер с лучшим пингом';

  @override
  String get hotkeyActionToggleWindow => 'Показать / скрыть окно';

  @override
  String get hotkeyNotSet => 'Не задано';

  @override
  String get hotkeyPressKeys => 'Нажмите сочетание…';

  @override
  String get hotkeyRecordingHint => 'Esc отменяет, Backspace очищает';

  @override
  String get hotkeyNeedsModifier => 'Нужен модификатор (Ctrl/Alt/Shift/Win) или F-клавиша';

  @override
  String hotkeyConflictTaken(Object combo) {
    return 'Сочетание $combo уже занято другим приложением';
  }

  @override
  String get hotkeyClearTooltip => 'Сбросить сочетание';

  @override
  String get hotkeyNoPingData => 'Нет результатов пинга, сначала запустите проверку';

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
  String get errorTunAdapterRefusedTitle => 'Windows не создала адаптер';

  @override
  String get errorTunAdapterRefusedMessage => 'Windows трижды не дала поднять адаптер TUN, сервер ни при чём.';

  @override
  String get errorTunAdapterRefusedAction => 'Подключитесь через минуту или перезагрузите компьютер. Прокси работает.';

  @override
  String get errorPolkitMissingTitle => 'Нужен polkit';

  @override
  String get errorPolkitMissingMessage => 'Режим TUN запускает ядро от root через pkexec, а polkit в системе не установлен.';

  @override
  String get errorPolkitMissingAction => 'Установите polkit вместе с агентом аутентификации, запустите приложение от root (sudo -E keqdroid) или переключитесь на режим прокси в настройках.';

  @override
  String get errorPolkitNoAgentTitle => 'Нужен polkit';

  @override
  String get errorPolkitNoAgentMessage => 'Запрос прав root остался без ответа: агент аутентификации polkit не запущен.';

  @override
  String get errorPolkitNoAgentAction => 'Запустите агент polkit своей среды (polkit-gnome, lxqt-policykit и подобные) или переключитесь на режим прокси в настройках.';

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
  String get errorConfigInvalidAction => 'Проверьте ссылку или конфиг и импортируйте заново.';

  @override
  String get errorAuthDeniedMessage => 'Провайдер отказал в доступе к подписке.';

  @override
  String get errorAuthDeniedAction => 'Проверьте токен или логин с паролем и не истёк ли срок подписки.';

  @override
  String get errorSubUrlInvalidMessage => 'Ссылка подписки не найдена или устарела.';

  @override
  String get errorSubUrlInvalidAction => 'Запросите новую ссылку у провайдера и обновите её в приложении.';

  @override
  String get errorSubInsecureHttpMessage => 'Ссылка подписки использует открытый http, обновления заблокированы.';

  @override
  String get errorSubInsecureHttpAction => 'Замените ссылку на её https-версию.';

  @override
  String get subInsecureHttpWarning => 'http-ссылка, обновления заблокированы';

  @override
  String get subSwitchToHttps => 'Исправить на https';

  @override
  String get errorNetworkMessage => 'Сервер сейчас недоступен.';

  @override
  String get errorNetworkAction => 'Проверьте интернет, DNS и доступность сервера, затем повторите.';

  @override
  String get errorUnknownAction => 'Попробуйте ещё раз. Если повторяется, проверьте сервер и настройки приложения.';

  @override
  String get errorFileDialogMessage => 'В этой сессии нечем показать выбор файла: нет ни backend\'а портала XDG, ни zenity/kdialog.';

  @override
  String get errorFileDialogAction => 'Установите xdg-desktop-portal-gtk (или zenity) либо вставьте текст конфига вместо выбора файла.';

  @override
  String get errorTunAdminTitle => 'Требуется разрешение';

  @override
  String get errorVpnPermissionTitle => 'Требуется разрешение';

  @override
  String get errorHwidBindTitle => 'Требуется привязка устройства';

  @override
  String get errorDeviceLimitTitle => 'Достигнут лимит устройств';

  @override
  String get errorProviderNoHostsTitle => 'Требуется настройка у провайдера';

  @override
  String get errorConfigInvalidTitle => 'Ошибка конфигурации';

  @override
  String get errorAuthDeniedTitle => 'Ошибка авторизации';

  @override
  String get errorSubUrlInvalidTitle => 'Неверная ссылка подписки';

  @override
  String get errorSubInsecureHttpTitle => 'Небезопасная ссылка подписки';

  @override
  String get errorNetworkTitle => 'Ошибка сети';

  @override
  String get errorUnknownTitle => 'Не удалось выполнить';

  @override
  String get errorFileDialogTitle => 'Нет диалога выбора файла';

  @override
  String get serversPin => 'Закрепить сервер';

  @override
  String get serversUnpin => 'Открепить сервер';

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
  String get serverEditorPinnedCert => 'Закреплённый сертификат (SHA-256)';

  @override
  String get serverEditorVerifyCertName => 'Имя для проверки сертификата';

  @override
  String get serverEditorPqv => 'Постквантовый ключ (ML-DSA-65)';

  @override
  String get serverEditorEarlyData => 'Early data, байт';

  @override
  String get serverEditorPadding => 'Набивка, байт';

  @override
  String get serverEditorExtra => 'Extra (JSON)';

  @override
  String get serverEditorAuthority => 'Authority';

  @override
  String get serverEditorSeed => 'Seed';

  @override
  String get serverEditorHttpMethod => 'Метод HTTP';

  @override
  String get serverEditorIssueVision => 'Vision работает только на TCP с TLS или REALITY.';

  @override
  String get serverEditorIssueFlow => 'Такого flow ядро не знает и откажется от всего конфига.';

  @override
  String get serverEditorIssueRealityTransport => 'На этом транспорте REALITY не работает.';

  @override
  String get serverEditorIssueRealityKey => 'REALITY нужен публичный ключ сервера.';

  @override
  String get serverEditorIssueEncryption => 'В Encryption пишут none или ключ mlkem768x25519plus.';

  @override
  String get serverEditorIssueNoSecurity => 'Без TLS, REALITY и Encryption ядро пустит только в локальную сеть.';

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
  String get serverEditorOverriddenNote => 'Конфиг изменён вручную, обновления подписки его больше не заменяют.';

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
  String get appearanceAmoledNeedsDark => 'Доступно при включённой тёмной теме';

  @override
  String get appearanceHalloween => 'Показывать праздничное оформление';

  @override
  String get appearanceHalloweenUntil => 'До 2 ноября';

  @override
  String get appearanceHaptics => 'Отзываться вибрацией';

  @override
  String get appearanceShowTraffic => 'Показывать скорость и объём трафика';

  @override
  String get appearanceShowTime => 'Показывать, сколько длится подключение';

  @override
  String get appearanceShowTrafficSplit => 'Считать трафик VPN и обхода раздельно';

  @override
  String get appearanceWaveLatencyColor => 'Красить волну по пингу';

  @override
  String get appearanceFontTitle => 'Шрифт';

  @override
  String get appearanceFontSystem => 'Системный';

  @override
  String get settingsResetConfirmTitle => 'Сбросить настройки?';

  @override
  String get settingsResetConfirmAction => 'Сбросить';

  @override
  String get settingsXrayResetConfirm => 'Настройки ядра Xray, TUN и локальные порты вернутся к значениям по умолчанию. Действие нельзя отменить.';

  @override
  String get settingsPermissionsTitle => 'Разрешения';

  @override
  String get settingsPermissionsSubtitle => 'Посмотреть и отозвать разрешения приложения';

  @override
  String get settingsPermNotifTitle => 'Уведомления';

  @override
  String get settingsPermNotifDesc => 'Строка статуса VPN и уведы об обновлении подписок';

  @override
  String get settingsPermBatteryTitle => 'Работа в фоне без ограничений';

  @override
  String get settingsPermBatteryDesc => 'Без неё система может не дать включить VPN из шторки';

  @override
  String get settingsPermAutostartTitle => 'Автозапуск';

  @override
  String get settingsPermAutostartDesc => 'Настройка прошивки: без неё VPN может не включаться из шторки и отключаться в фоне';

  @override
  String get settingsPermAutostartHint => 'Найдите автозапуск и работу в фоне (обычно в разделе батареи) и разрешите их';

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
  String get settingsPermTunHeader => 'Режим TUN (Linux)';

  @override
  String get settingsPermTunPasswordlessTitle => 'TUN без пароля';

  @override
  String get settingsPermTunDisabled => 'Беспарольный TUN выключен';

  @override
  String get appearanceNotifSectionTitle => 'Уведомления';

  @override
  String get appearanceNotifSpeedTitle => 'Показывать скорость в уведомлении';

  @override
  String get appearanceNotifUptimeTitle => 'Показывать время подключения в уведомлении';

  @override
  String get appearanceNotifSubUpdatesTitle => 'Уведомлять об обновлении подписок';

  @override
  String get tunRememberInstalled => 'Беспарольный TUN включён';

  @override
  String get tunRememberFailed => 'Не удалось изменить авторизацию TUN';

  @override
  String get settingsRoutingPresetRefilterTitle => 'Заблокировано в РФ (Re-filter)';

  @override
  String get settingsRoutingPresetWhitelistTitle => 'Белые списки мобильной связи';

  @override
  String get settingsRoutingGeoUnknownTitle => 'Нет в гео-базах, будет проигнорировано';

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
      other: '$count соединения',
      many: '$count соединений',
      few: '$count соединения',
      one: '$count соединение',
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
  String get connectionsRuleHint => 'Домены и сработавшее правило ядро пишет только на уровне логов Info.';

  @override
  String get connectionsRuleHintAction => 'Включить Info';

  @override
  String get connectionsRuleHintApplied => 'Уровень логов ядра теперь Info. Переподключитесь, чтобы применить';

  @override
  String get connectionsRuleDefault => 'без правила (действие по умолчанию)';

  @override
  String get connectionsRuleViaCore => 'решает ядро (нужны логи Info)';

  @override
  String get connectionsRuleViaCoreUnseen => 'решает ядро, его решения нет в логе';

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
  String get connectionsAppNamesHint => 'Название приложения сообщает система, а она знает только живые соединения, поэтому у закрытых имени не будет.';

  @override
  String get connectionsSplitTunnelNote => 'Приложения, выведенные из туннеля, здесь не появятся: Android пускает их мимо. Строка с правилом outside-vpn значит, что такое приложение само полезло в туннель, и ядро его не пустило.';

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
    return '«$name» истекла $date. Провайдер перестал обновлять список серверов. Продлите подписку, чтобы серверы продолжали работать.';
  }

  @override
  String get chainTitle => 'Цепочка прокси';

  @override
  String get chainNew => 'Новая цепочка';

  @override
  String get chainCreate => 'Собрать цепочку';

  @override
  String get chainCreateDesc => 'Пустить трафик через несколько серверов подряд';

  @override
  String get chainGroupTitle => 'Цепочки';

  @override
  String get chainNameLabel => 'Название цепочки';

  @override
  String get chainNameHint => 'Оставьте пустым, назовём по маршруту';

  @override
  String get chainHint => 'Трафик идёт сверху вниз: устройство подключается к первому узлу, а адрес последнего видят сайты.';

  @override
  String get chainDeviceNode => 'Это устройство';

  @override
  String get chainInternetNode => 'Интернет';

  @override
  String get chainAddNode => 'Добавить узел';

  @override
  String get chainRemoveNode => 'Убрать узел';

  @override
  String get chainExitNodeHint => 'Выходной узел, его адрес видят сайты';

  @override
  String get chainNodeMissing => 'Сервера больше нет, работаем по сохранённой копии';

  @override
  String get chainSave => 'Сохранить цепочку';

  @override
  String get chainNeedsTwoNodes => 'В цепочке нужно хотя бы два узла';

  @override
  String get chainPickNode => 'Выберите сервер';

  @override
  String get chainPickSearch => 'Поиск по серверам';

  @override
  String chainPickEmpty(String core) {
    return 'Нет серверов, которые $core может поставить в цепочку. Другое ядро выбирается в «О приложении».';
  }

  @override
  String get chainEdit => 'Изменить цепочку';

  @override
  String get chainDelete => 'Удалить цепочку';

  @override
  String get chainRouteLabel => 'Маршрут';

  @override
  String chainMaxNodes(int max) {
    return 'В цепочке не больше $max узлов';
  }

  @override
  String chainDeleteConfirm(String name) {
    return 'Удалить цепочку «$name»? Серверы из неё останутся в списке.';
  }

  @override
  String chainNodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count узла',
      many: '$count узлов',
      few: '$count узла',
      one: '$count узел',
      zero: 'нет узлов',
    );
    return '$_temp0';
  }

  @override
  String get settingsInternalsTitle => 'О приложении';

  @override
  String get settingsInternalsSubtitle => 'Версия, ядра, geo-базы и текущая сессия';

  @override
  String get settingsCoreXraySubtitle => 'Ядро по умолчанию. Исполняет ссылки, цепочки и готовые конфиги Xray.';

  @override
  String get settingsCoreMihomoSubtitle => 'Ядро, совместимое с Clash. Готовые конфиги xray остаются на Xray.';

  @override
  String get settingsCoreHint => 'Применится на следующем подключении, текущая сессия не перезапускается.';

  @override
  String get settingsProxyAuthTitle => 'Пароль для локального прокси';

  @override
  String get settingsProxyAuthSubtitle => 'Выключите там, где пароль вписать некуда, например в поле прокси у Wi-Fi';

  @override
  String get settingsProxyAuthUser => 'Логин';

  @override
  String get settingsProxyAuthPass => 'Пароль';

  @override
  String get settingsTunnelModeSection => 'Режим подключения';

  @override
  String get settingsTunnelModeVpn => 'VPN';

  @override
  String get settingsTunnelModeVpnSubtitle => 'Весь трафик устройства идёт через туннель';

  @override
  String get settingsTunnelModeProxy => 'Прокси';

  @override
  String get settingsTunnelModeProxySubtitle => 'Только локальный прокси, системный VPN не включается';

  @override
  String get settingsTunnelModeHint => '«Прокси» поднимает SOCKS и HTTP на 127.0.0.1, направьте на них приложение или Wi-Fi. Прокси открыт любому приложению на устройстве. Маршрутизация по приложениям и перехват DNS работают только в VPN.';

  @override
  String get settingsCoreSkipClash => 'У активного сервера готовый конфиг Clash: его исполняет только mihomo, при любом выборе ядра.';

  @override
  String get settingsCoreSkipCustom => 'У активного сервера готовый JSON-конфиг Xray: он идёт через libxray при любом выборе ядра. Для mihomo нужна подписка с обычными ссылками.';

  @override
  String get settingsCoreSkipChainXrayOnly => 'У активного сервера цепочка, и часть её узлов mihomo связать не может: она исполняется на Xray при любом выборе ядра.';

  @override
  String get settingsCoreSkipChainMihomoOnly => 'В цепочке активного сервера есть узел, который связывает только mihomo, например профиль AmneziaWG: она исполняется на mihomo при любом выборе ядра.';

  @override
  String get settingsCoreSkipAwg => 'У активного сервера профиль AmneziaWG: его исполняет mihomo при любом выборе ядра.';

  @override
  String get settingsCoreSkipPlatform => 'Ядро mihomo не поставляется на этой платформе, поэтому подключение идёт через ядро Xray.';

  @override
  String get settingsCoreSkipLinkXrayOnly => 'Ссылка активного сервера на транспорте, которого у mihomo для этого протокола нет: она исполняется на Xray при любом выборе ядра.';

  @override
  String get settingsCoreSkipLinkMihomoOnly => 'Ссылка активного сервера на транспорте, который Xray 26 убрал: она исполняется на mihomo при любом выборе ядра.';

  @override
  String get settingsInternalsCores => 'Ядра';

  @override
  String get settingsInternalsGeo => 'Geo-базы';

  @override
  String get settingsInternalsSession => 'Текущая сессия';

  @override
  String get settingsInternalsExits => 'Почему закрывалось приложение';

  @override
  String get settingsInternalsExitsHint => 'Записи ведёт сама система. Если VPN отключился в фоне, скопируйте их кнопкой сверху и пришлите.';

  @override
  String get settingsInternalsExitSystem => 'Остановлено системой или прошивкой';

  @override
  String get settingsInternalsExitMemory => 'Системе не хватило памяти';

  @override
  String get settingsInternalsExitCrash => 'Сбой приложения';

  @override
  String get settingsInternalsExitUser => 'Закрыто вручную';

  @override
  String get settingsInternalsExitUserOrUpdate => 'Закрыто вручную или обновлением';

  @override
  String get settingsInternalsExitUpdate => 'Обновление или смена разрешений';

  @override
  String get settingsInternalsExitSelf => 'Приложение завершилось само';

  @override
  String get settingsInternalsExitVpnOn => 'VPN был включён';

  @override
  String get appLogTitle => 'Журнал приложения';

  @override
  String get appLogSubtitle => 'Что происходило и что упало — по частям приложения';

  @override
  String get appLogSourceApp => 'Приложение';

  @override
  String get appLogSourceAppDesc => 'Интерфейс, подписки, подключение';

  @override
  String get appLogSourceNative => 'Нативная часть';

  @override
  String get appLogSourceNativeDesc => 'Служба VPN, плитка в шторке, окно подключения';

  @override
  String get appLogSourceExitsDesc => 'Записи системы: когда и почему закрывалось приложение';

  @override
  String appLogProblems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count проблемы',
      many: '$count проблем',
      few: '$count проблемы',
      one: '$count проблема',
      zero: 'Без проблем',
    );
    return '$_temp0';
  }

  @override
  String get appLogOnlyProblems => 'Только проблемы';

  @override
  String get appLogEmpty => 'Здесь пока пусто';

  @override
  String get appLogCopyAll => 'Скопировать весь журнал';

  @override
  String get settingsInternalsBuild => 'Приложение и устройство';

  @override
  String get settingsInternalsCopyAll => 'Скопировать отчёт';

  @override
  String get settingsInternalsCopied => 'Отчёт скопирован';

  @override
  String get settingsInternalsNoCores => 'Для этой платформы ядра не поставляются';

  @override
  String get settingsInternalsCoreMissing => 'не найдено';

  @override
  String get settingsInternalsVersionFromEngines => 'собрано из исходников';

  @override
  String get settingsInternalsRoleCore => 'Прокси-движок и TUN';

  @override
  String get settingsInternalsRoleProxy => 'Прокси-движок';

  @override
  String get settingsInternalsRoleTun => 'TUN-устройство';

  @override
  String settingsInternalsGeoCodes(int count) {
    return 'кодов: $count';
  }

  @override
  String get settingsInternalsGeoTrimmed => 'База стран урезанная';

  @override
  String get settingsInternalsGeoTrimmedHint => 'Только коды для пресетов приложения; правило с другой страной отбрасывается.';

  @override
  String get settingsInternalsGeoDownload => 'Скачать полную базу';

  @override
  String settingsInternalsGeoDownloadFailed(String error) {
    return 'Не удалось скачать: $error';
  }

  @override
  String get settingsInternalsStatus => 'Состояние';

  @override
  String get settingsInternalsStatusError => 'Ошибка';

  @override
  String get settingsInternalsEngine => 'Движок';

  @override
  String get settingsInternalsMode => 'Режим';

  @override
  String get settingsInternalsPorts => 'Локальные порты';

  @override
  String get settingsInternalsClashPort => 'Порт Clash API';

  @override
  String get settingsInternalsUptime => 'Время сессии';

  @override
  String get settingsInternalsCorePids => 'Процессы ядра';

  @override
  String get settingsInternalsElevated => 'Права администратора';

  @override
  String get settingsInternalsYes => 'да';

  @override
  String get settingsInternalsNo => 'нет';

  @override
  String get settingsInternalsAppVersion => 'Версия приложения';

  @override
  String get settingsInternalsPackage => 'Пакет';

  @override
  String get settingsInternalsOs => 'Система';

  @override
  String get settingsInternalsAbi => 'Архитектура';

  @override
  String get settingsInternalsDart => 'Dart';

  @override
  String get settingsInternalsBuildMode => 'Сборка';

  @override
  String get settingsInternalsUnavailable => '—';

  @override
  String get appearanceCustomColorTitle => 'Свой цвет';

  @override
  String get appearanceCustomColorSheetTitle => 'Свой цвет';

  @override
  String get appearanceCustomColorHue => 'Оттенок';

  @override
  String get appearanceCustomColorSaturation => 'Насыщенность';

  @override
  String get appearanceCustomColorBrightness => 'Яркость';

  @override
  String get appearanceCustomColorHex => 'HEX-код';

  @override
  String get appearanceCustomColorInvalid => 'Шесть шестнадцатеричных цифр, например 7B2CBF';

  @override
  String get appearanceCustomColorApply => 'Применить';

  @override
  String get appearanceCustomColorVariant => 'Палитра';

  @override
  String get appearanceCustomColorVariantCalm => 'Спокойная';

  @override
  String get appearanceCustomColorVariantVibrant => 'Яркая';

  @override
  String get appearanceCustomColorVariantExact => 'Точная';

  @override
  String get appearanceCustomColorVariantHint => 'Насыщенность и яркость слышно только на «Точной»: остальные две подбирают их сами.';

  @override
  String get appearanceUiScaleTitle => 'Размер интерфейса';

  @override
  String get appearanceUiScaleSubtitle => 'Весь интерфейс целиком, поверх системного масштаба.';

  @override
  String get appearanceIconShapeTitle => 'Форма иконок';

  @override
  String get appearanceIconShapeCircle => 'Круг';

  @override
  String get subscriptionCardThemeTitle => 'Подложка';

  @override
  String get subscriptionCardThemeNone => 'Без темы';

  @override
  String get subscriptionCardThemeInServers => 'Показывать в списке серверов';

  @override
  String get subscriptionCardLookTitle => 'Оформление карточки';

  @override
  String get subscriptionCardVeilTitle => 'Затемнение картинки';

  @override
  String get subscriptionCardVeilNone => 'Нет';

  @override
  String get subscriptionCardVeilLight => 'Лёгкое';

  @override
  String get subscriptionCardVeilMedium => 'Среднее';

  @override
  String get subscriptionCardVeilStrong => 'Плотное';

  @override
  String get subscriptionCardAutoSelect => 'Переключатель «Авто» в списке серверов';

  @override
  String get subscriptionCardAutoSelectHint => 'Добавляет в шапку группы переключатель. Включённый — сервер выбирает приложение и само переезжает на другой, когда текущий перестаёт работать.';

  @override
  String get subscriptionCardContentTitle => 'Что показывать';

  @override
  String get subscriptionCardPresetFull => 'Полная';

  @override
  String get subscriptionCardPresetCompact => 'Компактная';

  @override
  String get subscriptionCardPresetMinimal => 'Минимальная';

  @override
  String get subscriptionCardPresetCustom => 'Своя';

  @override
  String get subscriptionCardElementAnnounce => 'Объявление провайдера';

  @override
  String get subscriptionCardElementUsage => 'Трафик';

  @override
  String get subscriptionCardElementMeta => 'Срок и обновление';

  @override
  String get subscriptionCardElementActions => 'Кнопки';

  @override
  String get subscriptionCardContentHint => 'Предупреждения показываются всегда: просроченная подписка, небезопасная ссылка, неудачное обновление.';

  @override
  String get appearanceIconShapeSquare => 'Квадрат';

  @override
  String get appearanceIconShapeArch => 'Арка';

  @override
  String get appearanceSectionServers => 'Список серверов';

  @override
  String get appearanceSectionUnderButton => 'Под кнопкой подключения';

  @override
  String get appearanceSectionConnectPanel => 'Главный экран';

  @override
  String get appearanceConnectPanelLegacy => 'Легаси';

  @override
  String get appearanceConnectPanelModern => 'Модерн';

  @override
  String get appearanceBarMainland => 'Материк';

  @override
  String get appearanceBarIslands => 'Острова';

  @override
  String get appearancePartTop => 'Верх экрана';

  @override
  String get appearancePartBottom => 'Нижняя панель';

  @override
  String get appearanceSectionFeel => 'Нажатия';

  @override
  String get appearanceIconShapeClover => 'Клевер';

  @override
  String get appearanceIconShapeCookie => 'Печенье';

  @override
  String get appearanceIconShapeFlower => 'Цветок';

  @override
  String get appearanceIconShapeSlanted => 'Наклонный';

  @override
  String get appearanceIconShapePill => 'Пилюля';

  @override
  String get appearanceIconShapeGem => 'Кристалл';

  @override
  String get appearanceIconShapeSunny => 'Солнце';

  @override
  String get appearanceIconShapePuffy => 'Облако';

  @override
  String get appearanceIconShapePebble => 'Галька';

  @override
  String get cardImageRejectAspect => 'Картинка слишком высокая для карточки. Нужна широкая, примерно от 3:2 до 5:1.';

  @override
  String cardImageRejectSmall(int width) {
    return 'Картинка мелкая: нужно от $width px по ширине.';
  }

  @override
  String cardImageRejectLarge(int width) {
    return 'Картинка слишком большая: не больше $width px по ширине.';
  }

  @override
  String get cardImageRejectUnreadable => 'Не удалось прочитать эту картинку.';
}
