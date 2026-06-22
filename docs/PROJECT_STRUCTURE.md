# Карта проекта

«Где что лежит» — чтобы быстро находить место для правки. Как это всё связано — в
[ARCHITECTURE.md](ARCHITECTURE.md).

## Верхний уровень

```
keqdroid/
├── lib/                 ← весь Dart-код приложения (см. ниже)
├── android/             ← нативный Android (Kotlin VpnService + Gradle)
├── windows/             ← нативный Windows runner (C++)
├── linux/               ← нативный Linux runner + CMake
├── ios/                 ← заготовка iOS (не поддерживается активно)
├── assets/              ← иконки, сплэш, нативные ядра (assets/bin/*)
├── test/               ← тесты (зеркалят lib/)
├── tool/                ← скрипты сборки/релиза (.ps1 и .sh)
├── tools/               ← вспомогательные сборки (amneziawg_android)
├── docs/                ← эта документация
├── l10n.yaml            ← конфиг генерации локализаций
├── pubspec.yaml         ← зависимости, версия, ассеты
└── analysis_options.yaml← правила линтера
```

> В корне валяются `*.log` файлы прошлых сборок — это мусор, не часть проекта.

## `lib/` — Dart-код

```
lib/
├── main.dart            ← точка входа: bootstrap, ProviderScope, выбор home-экрана
│
├── app/                 ← корневой MaterialApp
│   └── app.dart           тема, пресеты тем, локаль, маршрут home
│
├── core/                ← инфраструктура без UI
│   ├── app_logger.dart    единый логгер (developer.log + Crashlytics)
│   ├── exceptions.dart    доменные исключения (StorageException, VpnException...)
│   └── crashlytics_*.dart репортер крэшей (android/io/stub — условный импорт)
│
├── models/              ← данные + (де)сериализация
│   ├── app_settings.dart      ВСЕ настройки приложения (режим, порты, DNS, kill switch)
│   ├── xray_core_settings.dart настройки ядра xray (DNS, log level, domain strategy, xmux)
│   ├── server_item.dart       один сервер (raw config + метаданные + парсинг имени/адреса)
│   ├── subscription.dart      подписка (url, имя, трафик, даты)
│   ├── routing_rule.dart      правило маршрутизации
│   ├── ping_test_config.dart  настройки и пресеты URL/speed-пинга
│   ├── server_name_utils.dart извлечение страны/флага/чистого имени из названия сервера
│   └── app_info.dart          установленное приложение (для split tunnel)
│
├── providers/           ← состояние (Riverpod)
│   ├── providers.dart         основные провайдеры (servers, subscriptions, vpnState, settings…)
│   └── ui_state_providers.dart чисто UI-состояние (свёрнутость, индексы вкладок, флаги пинга)
│
├── services/            ← бизнес-логика
│   ├── vpn_engine.dart        фасад над TunnelBackend (то, с чем говорит UI)
│   ├── storage_service.dart   персист в SharedPreferences (устойчив к битым записям)
│   ├── subscription_service.dart скачивание/парсинг/дедуп подписок, SSRF-фильтр, HWID
│   ├── update_service.dart    проверка/скачивание/проверка SHA-256 обновлений из GitHub
│   ├── windows_zip_updater.dart  портативное обновление Windows на месте
│   ├── ping_service.dart      TCP/ICMP/URL/speed-пинг
│   ├── ephemeral_xray_ping.dart  эфемерный xray для URL-пинга на десктопе
│   ├── settings_backup_service.dart экспорт/импорт настроек (.json/.keqdis)
│   ├── notification_service.dart  локальные уведомления (Android)
│   ├── background_service.dart    WorkManager — фоновое обновление подписок (Android)
│   ├── desktop_background_service.dart / linux_background_service.dart  десктоп-фон/трей
│   ├── windows_desktop_service.dart  окно/трей/автозапуск Windows
│   └── firefox_proxy_helper.dart  правка Firefox user.js под системный прокси
│
├── tunnel/              ← абстракция туннеля + платформенные реализации
│   ├── tunnel_backend.dart        интерфейс TunnelBackend + константы спидтеста
│   ├── tunnel_backend_factory.dart createTunnelBackend() по Platform
│   ├── android_tunnel_backend.dart  MethodChannel → Kotlin VpnService
│   ├── windows_tunnel_backend.dart  процессы ядра + системный прокси (C++ runner)
│   ├── linux_tunnel_backend.dart    процессы ядра + pkexec (TUN), /proc (процессы)
│   ├── tunnel_session_request.dart  параметры запуска сессии
│   ├── tunnel_state.dart          VpnState + enum VpnStatus
│   ├── connection_mode.dart       enum proxy/tun
│   ├── vpn_backend.dart           enum xray/awg
│   ├── app_routing_mode.dart      enum allProxy/onlySelected/allExceptSelected
│   ├── windows_core_paths.dart / linux_core_paths.dart  пути к ядрам/geo
│   └── xray_session_stats.dart    разбор статистики xray (StatsService API)
│
├── utils/               ← чистые функции (легко тестируются)
│   ├── config_gen.dart        ⭐ генератор xray-конфига (ConfigGeneratorV2)
│   ├── singbox_tun_config.dart генератор sing-box TUN-конфига
│   ├── keqrnel_config.dart    сборка единого keqrnel-конфига из chain
│   ├── wireproxy_config.dart  генератор wireproxy-конфига (AmneziaWG proxy)
│   ├── routing_entry.dart     разбор смешанных списков правил (домены/IP/geoip)
│   ├── routing_presets.dart   готовые списки direct/proxy/block
│   ├── awg_profile.dart       парсинг AmneziaWG .conf
│   ├── hysteria_uri.dart      парсинг Hysteria-ссылок
│   ├── socks5_credentials.dart  кеш кредов локального SOCKS
│   ├── clipboard_import.dart  импорт конфигов из буфера
│   ├── split_tunnel_routing.dart / process_name_utils.dart  логика split tunnel
│   ├── local_vpn_proxy.dart   настройка Dio на локальный HTTP-прокси при активном VPN
│   ├── config_gen.dart / error_messages.dart  человекочитаемые ошибки
│   └── app_locale.dart        утилиты локали
│
├── screens/             ← основные экраны (вкладки)
│   ├── servers_tab.dart       список серверов, подключение, пинг
│   ├── subscriptions_tab.dart список подписок, добавление/обновление
│   └── settings_tab.dart      настройки (тема, режим, маршрутизация, ядро, язык, обновления)
│
├── split_tunneling_screen.dart  выбор приложений/процессов для split tunnel
│
├── ui/                  ← платформо-специфичный UI
│   ├── desktop/
│   │   ├── desktop_home_screen.dart  десктопная оболочка (сайдбар + контент)
│   │   ├── tray_menu_screen.dart     меню в трее (то же окно, суженное)
│   │   └── desktop_connection_mode.dart  переключатель Proxy/TUN
│   └── responsive/        адаптивные лейауты (узкое/широкое окно)
│
├── shared/              ← переиспользуемый UI
│   ├── ui/app_theme.dart      цвета/тема (light/dark, dynamic color)
│   ├── ui/bottom_nav.dart     нижняя навигация (mobile)
│   ├── ui/update_dialog.dart  диалог обновления
│   ├── ui/smooth_scroll.dart  плавный скролл
│   └── extensions/            расширения (например, l10n-хелпер)
│
├── platform/            ← платформенный bootstrap
│   ├── platform_bootstrap.dart  инициализация Windows (окно/трей/автозапуск)
│   └── vpn_native_bridge.dart   тонкий мост к нативным методам
│
└── l10n/                ← локализация
    ├── app_en.arb / app_ru.arb / app_de.arb / app_zh.arb   ⭐ источник строк
    └── app_localizations*.dart  ГЕНЕРИРУЕМЫЕ (не править руками)
```

⭐ — файлы, которые трогают чаще всего.

## `android/` — нативный Android (Kotlin)

```
android/app/src/main/kotlin/com/keqdroid/keqdroid/
├── MainActivity.kt        мост MethodChannel 'keqdis_vpn_channel' + EventChannel
├── KeqdisVpnService.kt    VpnService: TUN + запуск ядра + tun2socks + статистика
├── EphemeralXrayPing.kt   эфемерный xray для URL-пинга
├── NativeHelper.kt        вспомогательные нативные вызовы
├── VpnQuickTileService.kt плитка в быстрых настройках
├── VpnStatusProvider.kt   провайдер статуса VPN
└── XrayGeoAssets.kt       распаковка geoip/geosite для xray
android/app/src/main/jniLibs/<abi>/   нативные ядра (.so) — НЕ Flutter-ассеты
```

## `windows/runner/` — нативный Windows (C++)

```
windows/runner/
├── main.cpp                 точка входа
├── tunnel_channel_handler.* системный прокси (per-connection options), elevation, TUN
├── windows_core_lifecycle.* запуск/останов ядра
├── windows_tray.*           трей-иконка/меню
├── windows_apps_list.*      список процессов для split tunnel
├── windows_traffic_stats.*  счётчики трафика
├── single_instance.h        single-instance
└── proxy_debug_log.*        отладочные логи прокси
```

## `assets/bin/` — нативные ядра (бандлятся per-platform, НЕ в APK)

```
assets/bin/windows/   keqrnel.exe, wireproxy.exe, wintun.dll, geoip.dat, geosite.dat, README.md
assets/bin/linux/     keqrnel, xray, sing-box, wireproxy, geoip.dat, geosite.dat, README.md
```

> Почему не Flutter-ассеты: Flutter пакует ассеты во **все** платформы, и Windows-exe +
> Linux-ELF + geo тянулись в Android APK (~150 МБ мусора). Теперь их раскладывают рядом с
> исполняемым файлом через `windows/`/`linux/` CMakeLists, а Android берёт ядра из `jniLibs`.

## `tool/` и `tools/` — скрипты

| Файл | Назначение |
|------|------------|
| `tool/make_release.ps1` | собрать APK+zip, посчитать SHA-256, (опц.) опубликовать релиз |
| `tool/sync_windows_plugins.ps1` | вырезать Firebase из Windows-плагинов (перед сборкой Windows) |
| `tool/build_amneziawg.ps1` | собрать AmneziaWG-ядро для Windows |
| `tool/build_linux_wsl.sh` / `build_linux_native.sh` | собрать Linux-бандл + ядра |
| `tool/package_linux.sh` | упаковать в .deb/AppImage/tar.gz/PKGBUILD |
| `tool/fetch_xray_geo.ps1` | обновить geoip.dat/geosite.dat |
| `tool/prepare_windows_icon.dart` | подготовка иконки Windows |
| `tools/amneziawg_android/` | сборка AmneziaWG .so под Android |

## `test/` — тесты (зеркалят `lib/`)

```
test/
├── utils/       config_gen, awg_profile, hysteria_uri, routing_entry, singbox_tun_config
├── services/    storage, subscription, update, ping (hysteria), windows_zip_updater
├── models/      xray_core_settings, server_name_utils, ping_test_config
├── tunnel/      xray_session_stats
├── widgets/     home_navigation, subscriptions_flow, vpn_state_actions
└── helpers/     pump_app.dart (рендер виджета в тесте), test_storage.dart (мок prefs)
```
