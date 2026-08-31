# Карта проекта

«Где что лежит». Как это связано между собой — в [ARCHITECTURE.md](ARCHITECTURE.md).

## Верхний уровень

```
keqdroid/
├── lib/                 ← весь Dart-код (см. ниже)
├── android/             ← нативный Android (Kotlin VpnService + Gradle)
├── windows/             ← нативный Windows runner (C++)
├── linux/               ← нативный Linux runner + CMake
├── ios/                 ← заготовка iOS (не поддерживается)
├── assets/              ← иконки, сплэш, нативные ядра (assets/bin/*)
├── test/                ← тесты (зеркалят lib/)
├── tool/                ← скрипты сборки ядер и релиза
├── tools/               ← сборка AmneziaWG .so под Android
├── release/             ← релизные скрипты (Linux-сборка в WSL, SHA-256) и артефакты
├── docs/                ← эта документация
├── l10n.yaml            ← конфиг генерации локализаций
├── pubspec.yaml         ← зависимости, версия, ассеты
└── analysis_options.yaml← правила линтера
```

## `lib/` — Dart-код

```
lib/
├── main.dart            ← bootstrap, ProviderScope, выбор home-экрана
├── split_tunneling_screen.dart ← выбор приложений/процессов для split tunnel
│
├── app/
│   └── app.dart           MaterialApp: тема, пресеты, локаль
│
├── core/                ← инфраструктура без UI
│   ├── app_logger.dart    единый логгер (developer.log + Crashlytics)
│   ├── exceptions.dart    доменные исключения (StorageException, VpnException…)
│   └── crashlytics_reporter*.dart  репортер крэшей (android/io/stub — условный импорт)
│
├── models/              ← данные + (де)сериализация
│   ├── app_settings.dart      все настройки приложения (режим, порты, DNS, kill switch)
│   ├── xray_core_settings.dart настройки ядра xray (DNS, log level, domain strategy, xmux)
│   ├── server_item.dart       один сервер: raw-ссылка + метаданные + парсинг имени/адреса
│   ├── subscription.dart      подписка: url, имя, трафик, даты, рабочий User-Agent
│   ├── routing_rule.dart      правило маршрутизации
│   ├── hotkey_config.dart     привязки хоткеев
│   ├── ping_test_config.dart  настройки и пресеты URL/speed-пинга
│   ├── server_name_utils.dart страна/флаг/чистое имя из названия сервера
│   └── app_info.dart          установленное приложение (для split tunnel)
│
├── providers/           ← состояние (Riverpod)
│   ├── providers.dart         servers, subscriptions, vpnState, settings, routing…
│   └── ui_state_providers.dart  чисто UI-состояние (свёрнутость, вкладки, флаги пинга)
│
├── services/            ← бизнес-логика
│   ├── vpn_engine.dart          фасад над TunnelBackend — то, с чем говорит UI
│   ├── tunnel_session_builder.dart  сборка TunnelSessionRequest из настроек
│   ├── storage_service.dart     персист в SharedPreferences, устойчивый к битым записям
│   ├── subscription_service.dart  скачивание/парсинг/дедуп подписок, UA-перебор, SSRF-фильтр, HWID
│   ├── update_service.dart      обновления из GitHub: версии, SHA-256 (fail-closed)
│   ├── windows_zip_updater.dart портативное обновление Windows на месте
│   ├── ping_service.dart        TCP/ICMP/URL/speed-пинг
│   ├── ephemeral_xray_ping.dart эфемерный xray с HTTP-инбаундом для URL-пинга (десктоп)
│   ├── hotkey_service.dart      диспетчер хоткеев (Windows — глобальные, Linux — в окне)
│   ├── debug_log_service.dart   сбор/экспорт отладочных логов
│   ├── settings_backup_service.dart  экспорт/импорт настроек (.json/.keqdis)
│   ├── file_dialog_service.dart  системные диалоги файла (Linux: портал XDG → zenity/kdialog)
│   ├── notification_service.dart локальные уведомления (Android)
│   ├── background_service.dart  WorkManager: фоновое обновление подписок (Android)
│   ├── desktop_background_service.dart / linux_background_service.dart  десктоп-фон
│   └── windows_desktop_service.dart  окно/трей/автозапуск Windows
│
├── tunnel/              ← абстракция туннеля + платформенные реализации
│   ├── tunnel_backend.dart        интерфейс TunnelBackend + константы спидтеста
│   ├── tunnel_backend_factory.dart  createTunnelBackend() по Platform
│   ├── android_tunnel_backend.dart  MethodChannel → Kotlin VpnService
│   ├── windows_tunnel_backend.dart  процессы ядра + системный прокси (C++ runner)
│   ├── linux_tunnel_backend.dart    процессы ядра + pkexec (TUN), /proc (процессы)
│   ├── tunnel_session_request.dart  параметры запуска сессии
│   ├── tunnel_state.dart            VpnState + enum VpnStatus
│   ├── connection_mode.dart / vpn_backend.dart / app_routing_mode.dart  enum'ы режимов
│   ├── windows_core_paths.dart / linux_core_paths.dart  резолв путей к ядрам/geo
│   ├── socks_credential_generator.dart  генерация кредов локального SOCKS
│   └── xray_session_stats.dart      разбор статистики xray StatsService (legacy: живые счётчики берутся из clash_api ядра)
│
├── utils/               ← чистые функции (легко тестируются)
│   ├── config_gen.dart        генератор xray-конфига (ConfigGeneratorV2) — правится чаще всего
│   ├── singbox_tun_config.dart  генератор sing-box TUN-конфига
│   ├── keqrnel_config.dart    keqrnel-конфиг: sing-box TUN со встроенным xray-фрагментом
│   ├── wireproxy_config.dart  wireproxy-конфиг (AmneziaWG proxy)
│   ├── routing_entry.dart     разбор смешанных списков правил (домены/IP/geoip)
│   ├── routing_presets.dart   готовые списки direct/proxy/block
│   ├── awg_profile.dart / hysteria_uri.dart  парсинг AWG .conf и Hysteria-ссылок
│   ├── awg_uri.dart           wg://-ссылка → .conf (разворачивается на импорте)
│   ├── subscription_url.dart / subscription_diff.dart  нормализация URL, дифф серверов
│   ├── socks5_credentials.dart  кеш кредов локального SOCKS
│   ├── clipboard_import.dart  импорт конфигов из буфера
│   ├── split_tunnel_routing.dart / process_name_utils.dart  логика split tunnel
│   ├── local_vpn_proxy.dart   настройка Dio на локальный HTTP-прокси при активном VPN
│   ├── error_messages.dart    человекочитаемые ошибки
│   └── app_locale.dart        утилиты локали
│
├── screens/             ← экраны
│   ├── servers_tab.dart       список серверов, подключение, пинг
│   ├── servers/               виджеты вкладки: server_tile, server_groups,
│   │                          connection_stats, wave_header
│   ├── subscriptions_tab.dart подписки: добавление/обновление/лимиты
│   ├── settings_tab.dart      корневой экран настроек
│   ├── settings/              под-экраны: advanced, routing, split_tunneling, hotkeys,
│   │                          xray_core, ping, theme, backup_restore, lan_sharing,
│   │                          local_proxy_ports, share_hwid, debug_and_logs,
│   │                          windows_desktop
│   └── qr_scan_screen.dart    сканер QR (импорт серверов/подписок, Android)
│
├── ui/                  ← платформо-специфичный UI
│   ├── desktop/
│   │   ├── desktop_home_screen.dart   десктопная оболочка (сайдбар + контент)
│   │   ├── tray_menu_screen.dart      меню в трее (то же окно, суженное)
│   │   └── desktop_connection_mode.dart  переключатель Proxy/TUN
│   └── responsive/desktop_page_layout.dart  адаптивный лейаут узкое/широкое окно
│
├── shared/              ← переиспользуемый UI
│   ├── ui/app_theme.dart      цвета/тема (light/dark, dynamic color)
│   ├── ui/bottom_nav.dart     нижняя навигация (mobile)
│   ├── ui/update_dialog.dart  диалог обновления
│   ├── ui/smooth_scroll.dart  плавный скролл
│   └── extensions/build_context_l10n.dart  хелпер локализации
│
├── platform/
│   ├── platform_bootstrap.dart  инициализация Windows (окно/трей/автозапуск/хоткеи)
│   └── vpn_native_bridge.dart   тонкий мост к нативным методам
│
└── l10n/
    ├── app_en.arb / app_ru.arb / app_de.arb / app_zh.arb   источник строк
    └── app_localizations*.dart  генерируемые — не править руками
```

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
├── flutter_window.* / win32_window.*  окно Flutter
├── window_placement.*        сохранение/восстановление позиции и размера окна
├── windows_hotkeys.*         глобальные хоткеи (RegisterHotKey)
├── tunnel_channel_handler.*  системный прокси (per-connection options), elevation, TUN
├── windows_core_lifecycle.*  запуск/останов процессов ядра
├── windows_tray.*            трей-иконка и меню
├── windows_apps_list.*       список процессов для split tunneling
├── windows_traffic_stats.*   счётчики трафика адаптера
├── single_instance.h         single-instance
└── proxy_debug_log.*         отладочные логи прокси
```

## `assets/bin/` — нативные ядра

```
assets/bin/windows/   keqrnel.exe, wireproxy.exe, wintun.dll, geoip.dat, geosite.dat
assets/bin/linux/     keqrnel, wireproxy, geoip.dat, geosite.dat
```

Отдельных `xray` / `sing-box` нет ни там, ни там: keqrnel несёт оба движка внутри и
на десктопе запускается всегда. В `pubspec.yaml` как Flutter-ассеты
объявлены только geo-базы — сами ядра раскладываются рядом с exe через `windows/` /
`linux/` CMakeLists, Android берёт их из `jniLibs`. Иначе Flutter паковал бы десктопные
бинарники во все платформы (в APK когда-то уезжало ~150 МБ мусора).

## `tool/`, `tools/`, `release/` — скрипты

| Файл | Назначение |
|------|------------|
| `tool/make_release.ps1` | APK + Windows-zip + SHA-256, опц. публикация релиза через gh |
| `tool/sync_windows_plugins.ps1` | пересоздать список Windows-плагинов без Firebase — нужен только после изменения списка плагинов |
| `tool/build_amneziawg.ps1` | AmneziaWG-ядро для Windows |
| `tool/build_linux_wsl.sh` | первичная Linux-сборка в WSL: ставит тулчейн и нативный Flutter |
| `tool/build_linux_native.sh` | Linux-сборка на нативном Linux |
| `tool/package_linux.sh` | упаковка в .deb/AppImage/tar.gz + PKGBUILD |
| `tool/fetch_xray_geo.ps1` | обновить geoip.dat/geosite.dat |
| `tool/prepare_windows_icon.dart` | иконка Windows |
| `tools/amneziawg_android/` | AmneziaWG .so под Android |

В `release/` скриптов нет — только каталоги собранных версий и файлы ноутов
`<версия>-notes.md`. Сайдкары `.sha256` пишет `tool/make_release.ps1` для
Windows и Android, `tool/package_linux.sh` — для Linux-артефактов.

## `test/` — тесты (зеркалят `lib/`)

```
test/
├── utils/       config_gen, awg_profile, hysteria_uri, routing_entry,
│                singbox_tun_config, subscription_url, subscription_diff
├── services/    storage, subscription (UA-перебор, парсинг), update,
│                ping_hysteria, windows_zip_updater
├── models/      xray_core_settings, server_name_utils, ping_test_config
├── providers/   subscriptions_reorder
├── tunnel/      xray_session_stats
├── widgets/     home_navigation, subscriptions_flow, vpn_state_actions
├── shared/      update_prompt
├── keqrnel_config_test.dart
└── helpers/     pump_app.dart (рендер виджета), test_storage.dart (мок prefs)
```
