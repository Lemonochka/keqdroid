# Архитектура

Документ объясняет, **как приложение устроено целиком** — чтобы понять поток данных, не
читая весь код. Карта файлов — в [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md), термины — в
[GLOSSARY.md](GLOSSARY.md).

## 1. Картина в одном экране

```
┌──────────────────────────────────────────────────────────────────────┐
│  UI (Flutter, Dart)                                                    │
│  lib/screens/*  lib/ui/*  lib/shared/*                                 │
│  вкладки Servers / Subscriptions / Settings, desktop-оболочка, трей    │
└───────────────▲───────────────────────────────────┬───────────────────┘
                │ watch/read                         │ вызовы методов
┌───────────────┴───────────────────────────────────▼───────────────────┐
│  State (Riverpod)  lib/providers/*                                     │
│  serversProvider, subscriptionsProvider, vpnStateProvider, settings... │
└───────────────▲───────────────────────────────────┬───────────────────┘
                │                                    │
┌───────────────┴───────────────────────────────────▼───────────────────┐
│  Services / Domain  lib/services/*  lib/utils/*  lib/models/*          │
│  StorageService, SubscriptionService, UpdateService, PingService,      │
│  VpnEngine (фасад), генераторы конфигов (config_gen, singbox, awg...)  │
└───────────────▲───────────────────────────────────┬───────────────────┘
                │ Stream<VpnState>                   │ TunnelSessionRequest
┌───────────────┴───────────────────────────────────▼───────────────────┐
│  Tunnel backends  lib/tunnel/*                                         │
│  TunnelBackend (абстракция) → Android / Windows / Linux реализации     │
└───────────────▲───────────────────────────────────┬───────────────────┘
                │ EventChannel / stdout              │ MethodChannel / spawn
┌───────────────┴───────────────────────────────────▼───────────────────┐
│  Native + Cores                                                        │
│  Android: Kotlin VpnService (android/.../*.kt)                         │
│  Windows: C++ runner (windows/runner/*.cpp)                            │
│  Linux:   процессы + pkexec                                            │
│  Ядра: keqrnel / xray / sing-box / wireproxy + geoip.dat/geosite.dat   │
└────────────────────────────────────────────────────────────────────────┘
```

Главный принцип: **Dart-слой только генерирует конфиги и оркеструет**, а трафик гоняют
нативные ядра. Один и тот же Dart-код управляет тремя платформами через единый интерфейс
`TunnelBackend`.

## 2. Слои подробнее

### UI (`lib/screens`, `lib/ui`, `lib/shared`)
- Три вкладки: **Servers**, **Subscriptions**, **Settings** (`lib/screens/*_tab.dart`).
- На мобильном — `VpnHomeScreen` (PageView с тремя вкладками, `lib/main.dart`).
- На десктопе — `DesktopHomeScreen` (`lib/ui/desktop/`) с сайдбаром, и **трей-меню**
  (`tray_menu_screen.dart`). Трей переиспользует то же окно (см. [PITFALLS.md](PITFALLS.md)).
- Общие виджеты и тема — `lib/shared/ui/` (`app_theme.dart`, `bottom_nav.dart`,
  `update_dialog.dart`). Material 3, светлая/тёмная тема, dynamic color.

### State (`lib/providers`)
Состояние — на **Riverpod 3**. Ключевые провайдеры (`providers.dart`):

| Провайдер | Тип | За что отвечает |
|-----------|-----|-----------------|
| `storageProvider` | `Provider` | доступ к `StorageService` (переопределяется в `main.dart`) |
| `serversProvider` | `NotifierProvider` | список серверов, активный сервер, пинги |
| `subscriptionsProvider` | `AsyncNotifierProvider` | подписки, авто-обновление (таймер + WorkManager/onResume) |
| `vpnStateProvider` | стрим состояния | статус подключения (`VpnStatus`), активный режим, статистика |
| `settingsNotifierProvider` | `NotifierProvider` | `AppSettings` (режим, порты, DNS, kill switch…) |
| `routingRulesProvider` | `NotifierProvider` | правила маршрутизации |
| `splitTunnelingProvider` | `NotifierProvider` | include/exclude приложений/процессов |
| `updateInfoProvider` | `FutureProvider` | проверка обновлений из GitHub |
| `vpnEngineProvider` | `Provider` | синглтон `VpnEngine` |

Чисто UI-состояние (какие группы свёрнуты, индексы вкладок, идёт ли пинг) вынесено в
`lib/providers/ui_state_providers.dart`.

### Services / Domain (`lib/services`, `lib/utils`, `lib/models`)
Бизнес-логика без UI:
- **`StorageService`** — персист в `SharedPreferences` (серверы, подписки, правила,
  настройки, активный сервер, HWID). Загрузка устойчива к битым записям — одна повреждённая
  запись не уносит весь список.
- **`SubscriptionService`** — скачивание/парсинг подписок, дедуп серверов, SSRF-фильтр URL,
  HWID-заголовки, лимиты трафика из `X-Subscription-Userinfo`.
- **`UpdateService`** — проверка GitHub Releases, скачивание, проверка SHA-256, портативное
  обновление Windows на месте.
- **`PingService`** / **`EphemeralXrayPing`** — TCP/ICMP/URL/speed-пинг серверов.
- **`VpnEngine`** — фасад над `TunnelBackend` (см. ниже).
- Фоновые сервисы: `BackgroundService` (Android WorkManager), `DesktopBackgroundService`,
  `LinuxBackgroundService`, `NotificationService`.
- **`lib/utils/`** — чистые функции: генерация конфигов и парсинг (см. раздел 4).
- **`lib/models/`** — данные: `AppSettings`, `ServerItem`, `Subscription`, `RoutingRule`,
  `XrayCoreSettings` и т.д. с `fromJson/toJson`.

### Tunnel (`lib/tunnel`)
Платформенная абстракция туннеля. См. раздел 3.

### Native + Cores
- **Android**: Kotlin `KeqdisVpnService` (VpnService + tun2socks), `MainActivity` (мост
  MethodChannel/EventChannel), Quick Settings tile, статус-провайдер.
- **Windows**: C++ runner `windows/runner/` — системный прокси, трей, список процессов,
  жизненный цикл ядра, счётчики трафика.
- **Linux**: запуск ядер процессами, TUN через `pkexec`.
- **Ядра** — внешние бинарники (см. [GLOSSARY.md](GLOSSARY.md)).

## 3. Абстракция туннеля (сердце приложения)

```
UI/providers
   │
   ▼
VpnEngine (lib/services/vpn_engine.dart)   ← синглтон-фасад
   │
   ▼
TunnelBackend (интерфейс, lib/tunnel/tunnel_backend.dart)
   │  createTunnelBackend() выбирает по Platform:
   ├── AndroidTunnelBackend   → MethodChannel 'keqdis_vpn_channel' → Kotlin VpnService
   ├── WindowsTunnelBackend   → спавн процессов ядра + C++ runner для системного прокси
   └── LinuxTunnelBackend     → спавн процессов ядра + pkexec для TUN
```

`TunnelBackend` (единый контракт для всех платформ):
- `startSession(TunnelSessionRequest)` / `stopSession()` — старт/стоп туннеля;
- `stateStream` — поток `VpnState` (статус, режим, статистика);
- `fetchSocksCredentials()` — креды локального SOCKS;
- `requestTunnelPermission()` — VPN-разрешение (Android) / проверка админ-прав (десктоп);
- `xrayUrlTestBatch` / `xraySpeedTestBatch` — пинг/спидтест через ядро;
- `getInstalledApps` / `getAppIcon` — для split tunneling.

**`TunnelSessionRequest`** (`lib/tunnel/tunnel_session_request.dart`) — всё, что нужно для
запуска: режим (`ConnectionMode`), бэкенд (`VpnBackend`), `xrayConfig`, опционально
`singboxConfig`/`awgConfig`, порты, split-списки, `systemProxy`, `killSwitch`, `coreEngine`.
На Android сериализуется в аргументы MethodChannel.

### Два «измерения» режима

1. **`ConnectionMode`** — `proxy` или `tun`.
   - `proxy`: локальный SOCKS/HTTP от xray + (Windows) системный прокси. Без админ-прав.
   - `tun`: sing-box владеет TUN-устройством, аплинк — локальный SOCKS xray. Весь трафик в
     туннель. Требует админ/root на десктопе. **Android — всегда tun** (через VpnService).

2. **`VpnBackend`** — `xray` или `awg`.
   - `xray`: обычный пайплайн (xray → SOCKS → tun2socks/sing-box).
   - `awg`: AmneziaWG, ядро само владеет TUN/SOCKS (без xray-обёртки).

### `coreEngine`: `chain` vs `keqrnel`
- **`chain`** (дефолт): два процесса — `xray` (аплинк) → `sing-box` (TUN).
- **`keqrnel`**: единый бинарь, заменяющий связку. `KeqrnelConfig.fromChain()` берёт
  sing-box TUN-конфиг и подменяет socks-outbound `proxy` на встроенный xray-движок
  (`{"type":"xray","xray": <xrayConfig>}`). Меньше RAM и размер — ради чего ядра и слили.

## 4. Генерация конфигов (`lib/utils`)

Это место, где Dart превращает ссылку сервера + настройки в JSON для ядра. Самая частая
область багов и правок.

| Файл | Что генерирует |
|------|----------------|
| `config_gen.dart` (`ConfigGeneratorV2`) | **xray-конфиг** из `vless://`/`vmess://`/`trojan://`/`ss://`/`hysteria2://`. Outbound по протоколу + inbounds (SOCKS/HTTP) + DNS + **routing rules**. |
| `singbox_tun_config.dart` | **sing-box TUN-конфиг** для десктопного TUN: TUN-inbound, sniffing, маршрутизация по процессам (split tunnel). |
| `keqrnel_config.dart` | **единый keqrnel-конфиг** из chain (sing-box + встроенный xray). |
| `wireproxy_config.dart` | **wireproxy-конфиг** для AmneziaWG proxy-режима на Windows. |
| `routing_entry.dart` | разбивает смешанные списки правил на домены / IP-CIDR / `geoip:`. |
| `routing_presets.dart` | готовые списки (direct/proxy/block). |
| `awg_profile.dart`, `hysteria_uri.dart` | парсинг AmneziaWG `.conf` и Hysteria-ссылок. |

Маршрутизация в xray: правила имеют поля `domain`, `ip`, `outboundTag` (`direct`/`proxy`/
`block`). **GeoIP в xray задаётся через `ip: ["geoip:ru"]`, отдельного поля `geoip` нет.**

> Целевое ядро — **xray 26.x**. У него свои причуды: пустой `fingerprint` отвергается,
> hysteria2 использует network `"hysteria"` (а не `"quic"`), reality требует валидный
> utls-fingerprint. Всё это уже учтено в `config_gen.dart` — см. комментарии там.

## 5. Сквозной пример: что происходит при нажатии «Подключить»

`VpnStateNotifier.connect()` в `lib/providers/providers.dart`:

1. Защита от двойного коннекта (`_connectInFlight`).
2. Берёт активный сервер; если его нет — состояние `error`.
3. `serversProvider.setActive(server)`, статус → `connecting`.
4. Читает `AppSettings`, split-списки, считает `routingMode` и список процессов (Windows).
5. Android — запрашивает VPN-разрешение; Windows TUN — проверяет админ-права (иначе fallback
   в Proxy при автостарте).
6. `engine.fetchSocksCredentials()` — креды локального SOCKS из нативного сервиса.
7. Резолвит домен сервера в IP (чтобы direct-правило шло по IP, а не по домену).
8. `ConfigGeneratorV2.generateConfig(...)` → xray-конфиг (для AWG пропускается).
9. `TunnelSessionBuilder.build(...)` → `TunnelSessionRequest`. Для десктопного TUN тут же
   генерится `singboxConfig`.
10. `engine.startSession(request)` → платформенный `TunnelBackend` поднимает ядро/VpnService.
11. `engine.getCurrentState()` → статус `connected`, обновляется `vpnStateProvider`.
12. Ошибки логируются, состояние → `error`, исключение пробрасывается наверх.

`vpnStateProvider` слушает `stateStream` бэкенда, и UI реактивно обновляется.

## 6. Подписки, обновления, хранение (коротко)

- **Подписки**: `SubscriptionService.fetchRaw()` качает URL (один retry, HWID-фолбэк),
  парсит конфиги, дедуп по «стабильному ключу» (`_stableKey`, устойчив к ротации
  reality-параметров). Авто-обновление: Android — WorkManager (фон) + onResume; десктоп —
  таймер, пока приложение открыто.
- **Обновления**: `UpdateService.checkForUpdate()` ходит в GitHub API (нужен `User-Agent`,
  иначе 403), сравнивает версии **и даты публикации**, скачивает ассет под платформу,
  **проверяет SHA-256** (fail-closed), на Windows применяет zip на месте
  (`WindowsZipUpdater`). При активном VPN на десктопе трафик идёт через локальный HTTP-прокси
  (Dart не умеет SOCKS в `HttpClient`).
- **Хранение**: `StorageService` поверх `SharedPreferences`. На Windows файлы — в
  `%APPDATA%\Roaming\com.keqdroid\keqdroid\`, не рядом с exe.

## 7. Точки входа и инициализация

`lib/main.dart` → `main()`:
- оборачивает всё в `runZonedGuarded` (ловит необработанные ошибки в Crashlytics);
- Android: Firebase, `BackgroundService` (WorkManager), `NotificationService`;
- Windows: `PlatformBootstrap.initialize()` (окно, трей, автозапуск);
- Linux: `DesktopBackgroundService`, single-instance, очистка stale-прокси, окно+трей;
- создаёт `StorageService`, выбирает `home` (desktop vs mobile), запускает `ProviderScope`.
