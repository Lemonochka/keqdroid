# Архитектура

Карта файлов — в [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md), термины — в
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

Главный принцип: Dart-слой только генерирует конфиги и оркеструет, трафик гоняют нативные
ядра. Один и тот же Dart-код управляет тремя платформами через интерфейс `TunnelBackend`.

## 2. Слои

### UI (`lib/screens`, `lib/ui`, `lib/shared`)
- Три вкладки: **Servers**, **Subscriptions**, **Settings** (`lib/screens/*_tab.dart`);
  под-экраны настроек разложены по `lib/screens/settings/` (роутинг, split tunnel, хоткеи,
  ядро, бэкап, LAN и т.д.), виджеты списка серверов — по `lib/screens/servers/`.
- На мобильном — `VpnHomeScreen` (PageView, `lib/main.dart`), на десктопе —
  `DesktopHomeScreen` (`lib/ui/desktop/`) с сайдбаром и трей-меню
  (`tray_menu_screen.dart` — это то же окно, суженное, см. [PITFALLS.md](PITFALLS.md)).
- Тема и общие виджеты — `lib/shared/ui/`. Material 3, светлая/тёмная, dynamic color.

### State (`lib/providers`)
Riverpod 3. Ключевые провайдеры (`providers.dart`):

| Провайдер | За что отвечает |
|-----------|-----------------|
| `storageProvider` | доступ к `StorageService` (переопределяется в `main.dart`) |
| `serversProvider` | список серверов, активный сервер, пинги |
| `subscriptionsProvider` | подписки и их авто-обновление (таймер + WorkManager/onResume) |
| `vpnStateProvider` | статус подключения (`VpnStatus`), режим, статистика |
| `settingsNotifierProvider` | `AppSettings` (режим, порты, DNS, kill switch…) |
| `routingRulesProvider` | правила маршрутизации |
| `splitTunnelingProvider` | include/exclude приложений/процессов |
| `updateInfoProvider` | проверка обновлений из GitHub |
| `vpnEngineProvider` | синглтон `VpnEngine` |

Чисто UI-состояние (свёрнутость групп, индексы вкладок, идёт ли пинг) вынесено в
`ui_state_providers.dart` — оно не переживает перезапуск и не должно тащить за собой
rebuild'ы тяжёлых поддеревьев.

### Services / Domain (`lib/services`, `lib/utils`, `lib/models`)
- **`StorageService`** — персист в `SharedPreferences`. Читает списки устойчиво к битым
  записям (одна повреждённая запись пропускается с логом, а не уносит весь список);
  read-modify-write циклы сериализованы, чтобы фоновые изоляты не откатывали кэш.
- **`SubscriptionService`** — скачивание и парсинг подписок (подробно в §6).
- **`UpdateService`** — GitHub Releases: сравнение версий и дат публикации, скачивание,
  проверка SHA-256 (fail-closed), на Windows — обновление zip на месте
  (`WindowsZipUpdater`).
- **`PingService`** / **`EphemeralXrayPing`** — TCP/ICMP/URL/speed-пинг; URL-пинг ходит
  через эфемерный экземпляр ядра с HTTP-инбаундом (не SOCKS — Dart его не умеет,
  см. [PITFALLS.md](PITFALLS.md)).
- **`VpnEngine`** — фасад над `TunnelBackend`; **`TunnelSessionBuilder`** собирает
  `TunnelSessionRequest` из настроек.
- **`HotkeyService`** — диспетчер хоткеев (глобальные на Windows через нативный
  `windows_hotkeys.cpp`, внутриоконные на Linux); **`DebugLogService`** — экспорт логов.
- Фон: `BackgroundService` (Android WorkManager), `DesktopBackgroundService` /
  `LinuxBackgroundService` (таймер, пока приложение открыто), `NotificationService`.
- **`lib/utils/`** — чистые функции: генераторы конфигов и парсеры (§4).
- **`lib/models/`** — данные с `fromJson`/`toJson`: `AppSettings`, `ServerItem`,
  `Subscription`, `RoutingRule`, `XrayCoreSettings`, `HotkeyConfig` и т.д.

### Native + Cores
- **Android**: Kotlin `KeqdisVpnService` (VpnService + tun2socks), `MainActivity`
  (MethodChannel/EventChannel `keqdis_vpn_channel`), Quick Settings tile, статус-провайдер.
- **Windows**: C++ runner — системный прокси, трей, глобальные хоткеи, позиция окна,
  список процессов, жизненный цикл ядра, счётчики трафика.
- **Linux**: запуск ядер процессами, TUN через `pkexec`, список процессов из `/proc`.

## 3. Абстракция туннеля

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

Контракт `TunnelBackend`: `startSession(TunnelSessionRequest)` / `stopSession()`,
`stateStream` (поток `VpnState`), `fetchSocksCredentials()`, `requestTunnelPermission()`
(VPN-разрешение на Android / проверка админ-прав на десктопе), `xrayUrlTestBatch` /
`xraySpeedTestBatch` (пинг через ядро), `getInstalledApps` / `getAppIcon` (split tunnel).

**`TunnelSessionRequest`** — всё, что нужно для запуска: режим (`ConnectionMode`), бэкенд
(`VpnBackend`), `xrayConfig`, опционально `singboxConfig`/`awgConfig`, порты,
split-списки, `systemProxy`, `killSwitch`, `coreEngine`. На Android сериализуется в
аргументы MethodChannel.

### Три «измерения» режима

1. **`ConnectionMode`**: `proxy` | `tun`.
   - `proxy` — локальный SOCKS/HTTP + (Windows) системный прокси. Без админ-прав.
   - `tun` — виртуальный адаптер, весь трафик ОС в туннеле. Админ/root на десктопе.
     **Android — всегда tun** (VpnService), выбора там нет.
2. **`VpnBackend`**: `xray` | `awg`. AmneziaWG идёт мимо xray-пайплайна — ядро само
   владеет TUN/SOCKS.
3. **`coreEngine`**: `keqrnel` (дефолт) | `chain`.
   - **`keqrnel`** — единый бинарь: sing-box-хост со встроенным xray-движком.
     `KeqrnelConfig.fromChain()` берёт sing-box TUN-конфиг и подменяет socks-outbound
     `proxy` на `{"type":"xray","xray": <xrayConfig>}`. Один процесс вместо двух, меньше
     RAM — ради этого ядра и слили.
   - **`chain`** — классическая связка из двух процессов: `xray` (аплинк) → `sing-box`
     (TUN). На Linux оба бинарника в бандле; на Windows в поставке их **нет** — chain
     заработает, только если положить `xray.exe`/`sing-box.exe` рядом с приложением.

## 4. Генерация конфигов (`lib/utils`)

Здесь ссылка сервера + настройки превращаются в JSON для ядра — сюда чаще всего и
приходится лезть при багах совместимости с провайдерами.

| Файл | Что генерирует |
|------|----------------|
| `config_gen.dart` (`ConfigGeneratorV2`) | xray-конфиг из `vless://`/`vmess://`/`trojan://`/`ss://`/`hysteria2://`: outbound по протоколу, SOCKS/HTTP-инбаунды, DNS, routing rules |
| `proxy_chain.dart` (`ProxyChainConfig`) | цепочка серверов: формат `keqchain://` и разбор узлов (§4.1) |
| `singbox_tun_config.dart` | sing-box TUN-конфиг для десктопного TUN: TUN-inbound, sniffing, split tunnel по процессам |
| `keqrnel_config.dart` | единый keqrnel-конфиг из chain |
| `wireproxy_config.dart` | wireproxy-конфиг (AmneziaWG в proxy-режиме) |
| `routing_entry.dart` | разбор смешанных списков правил: домены / IP-CIDR / `geoip:` |
| `routing_presets.dart` | готовые списки direct/proxy/block |
| `awg_profile.dart`, `hysteria_uri.dart` | парсинг AmneziaWG `.conf` и Hysteria-ссылок |
| `subscription_url.dart`, `subscription_diff.dart` | нормализация URL подписок, дифф серверов между обновлениями |

### 4.1. Цепочки прокси

Цепочка — несколько серверов подряд: устройство подключается к первому узлу, он
дотягивается до второго, и так до последнего; последний и есть тот, чей адрес
видят сайты.

В списке серверов цепочка лежит обычным `ServerItem`, у которого в `config`
строка `keqchain://<base64url(json)>` со ссылками узлов и id серверов, из которых
они скопированы (`protocol == 'chain'`). Так она бесплатно получает всё, что уже
умеет список: выбор активного, закрепление, пинг, сортировку, меню трея,
хранение. Ссылки узлов подтягиваются заново при каждой загрузке списка
(`ServersNotifier._syncChains`) — иначе обновление подписки оставляло бы цепочку
на протухшем конфиге; узел, которого в списке больше нет, живёт снимком.

Исполняется цепочка **целиком внутри xray-части конфига**: каждому узлу свой
outbound, узел `i` дозванивается до своего сервера через `i-1` полем
`streamSettings.sockopt.dialerProxy`. Выходной узел сохраняет тег `proxy`,
поэтому весь роутинг и sing-box-часть про цепочку вообще не знают. Отсюда же и
одинаковость платформ: на Android конфиг исполняет libxray, на десктопе —
встроенный в keqrnel xray-инстанс. Подводные камни (снифинг на промежуточном
узле, `udphop` у hysteria) — в [PITFALLS.md](PITFALLS.md).

Целевое ядро — **xray 26.x**, у него свои причуды, уже учтённые в `config_gen.dart`:
пустой `fingerprint` отвергается, hysteria2 использует network `"hysteria"` (не `"quic"`),
reality требует валидный utls-fingerprint, GeoIP задаётся только внутри поля `ip`
(`ip: ["geoip:ru"]` — отдельного поля `geoip` нет). Если в Direct-списке есть свои
IP/CIDR-диапазоны, `domainStrategy` поднимается `AsIs → IPIfNonMatch`, чтобы
CONNECT-по-имени, чей адрес резолвится в диапазон, ушёл direct.

## 5. Что происходит при нажатии «Подключить»

`VpnStateNotifier.connect()` в `lib/providers/providers.dart`:

1. Защита от двойного коннекта (`_connectInFlight`).
2. Берёт активный сервер; нет сервера — состояние `error`.
3. `serversProvider.setActive(server)`, статус → `connecting`.
4. Читает `AppSettings` и split-списки, считает `routingMode` и список процессов (Windows).
5. Android — запрашивает VPN-разрешение; Windows TUN — проверяет админ-права (при
   автостарте без прав тихо откатывается в Proxy).
6. `engine.fetchSocksCredentials()` — креды локального SOCKS из нативного сервиса.
7. Резолвит домен сервера в IP, чтобы direct-правило для него работало по IP.
8. `ConfigGeneratorV2.generateConfig(...)` → xray-конфиг (для AWG шаг пропускается).
9. `TunnelSessionBuilder.build(...)` → `TunnelSessionRequest`; для десктопного TUN здесь
   же генерится sing-box/keqrnel-конфиг.
10. `engine.startSession(request)` — платформенный бэкенд поднимает ядро/VpnService.
11. `engine.getCurrentState()` → `connected`, `vpnStateProvider` обновляется.
12. Ошибки логируются, состояние → `error`, исключение пробрасывается наверх.

Дальше UI живёт на `stateStream` бэкенда. Важно: статус приходит из нескольких
независимых источников (поток из натива, snapshot при resume, QS-плитка на Android,
onRevoke от системы) — при правках синхронизации статуса проверяй все пути, они уже
не раз расходились.

## 6. Подписки

`SubscriptionService.fetchRaw(url, userAgent: ...)` — конвейер с несколькими уровнями
фолбэков, потому что панели провайдеров ведут себя очень по-разному:

1. **URL-фильтр** (`isSafeUrl`): только http/https, отсекаются localhost, приватные
   диапазоны и облачные metadata-адреса — защита от SSRF через подписку.
2. **Первый запрос** идёт с сохранённым для этой подписки User-Agent, а если его нет — с
   UA приложения (`keqdroid/<версия>`). Многие панели маршрутизируют ответ по UA:
   клиентам отдают payload, браузерам — HTML-страницу подписки.
3. **Ответ 200 + payload** — парсинг: plain-список URI, base64, варианты вперемешку
   (`_parseBody` гоняется в отдельном изоляте — тела бывают большими, а обновление
   дёргается на onResume). Лимиты трафика и срок — из заголовка
   `X-Subscription-Userinfo`, с фолбэком на «служебные ноды» в теле.
4. **Ответ 200 + HTML** — перебор известных клиентских UA (свой первым, браузерный —
   последним резервом); если payload так и не отдали, конфиги выковыриваются из самого
   HTML или страница краулится на прямые ссылки подписки.
5. **HTTP-ошибка (4xx/5xx)** — сначала попытка распарсить тело ошибки (некоторые панели
   кладут payload в не-200 ответ), затем тот же UA-перебор, затем запрос нативным
   `HttpClient` с браузерными заголовками (часть CDN/WAF режет именно Dio) и HWID-фолбэк
   через query-параметр.
6. **Успех** — сработавший UA сохраняется в `Subscription.userAgent`, и следующее
   обновление обходится одним запросом. Если сохранённый UA перестал работать, перебор
   запускается заново и перезаписывает его.

Дедуп серверов между обновлениями — по «стабильному ключу» (`_stableKey`: схема +
uuid/пароль + host + port), устойчивому к ротации reality-параметров (`sid`/`spx`/`pbk`)
и смене имени — иначе при каждом обновлении терялись бы пинги и избранное.

Авто-обновление: Android — WorkManager (работает и после убийства приложения) + onResume;
десктоп — таймер, пока приложение открыто (свёрнутое в трей считается открытым). Батчи по
3 подписки, чтобы не упереться в сеть и rate-limit панелей.

## 7. Обновления приложения и хранение

- `UpdateService.checkForUpdate()` ходит в GitHub API (без `User-Agent` тот отвечает 403),
  сравнивает версии **и даты публикации**, качает ассет своей платформы, сверяет SHA-256 с
  сайдкаром (нет сайдкара или не совпал — обновление не ставится). Windows-zip
  распаковывается на место с перезапуском (`WindowsZipUpdater`). При активном VPN на
  десктопе трафик апдейтера заворачивается в локальный **HTTP**-прокси — SOCKS Dart-овский
  `HttpClient` не умеет.
- `StorageService` — поверх `SharedPreferences`; на Windows файлы лежат в
  `%APPDATA%\com.keqdroid\keqdroid\`, не рядом с exe.

## 8. Точки входа

`lib/main.dart` → `main()`:
- всё обёрнуто в `runZonedGuarded` — необработанные ошибки уходят в Crashlytics (Android);
- Android: Firebase, `BackgroundService` (WorkManager), `NotificationService`;
- Windows: `PlatformBootstrap.initialize()` — окно (с восстановлением позиции/размера),
  трей, автозапуск, регистрация глобальных хоткеев;
- Linux: `DesktopBackgroundService`, single-instance, очистка stale-прокси, окно + трей;
- создаётся `StorageService`, выбирается home-экран (desktop/mobile), запускается
  `ProviderScope`.
