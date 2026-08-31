<p align="center">
  <img src="assets/icon.png" width="88" alt="KEQDIS">
</p>

<h1 align="center" id="keqdis">KEQDIS</h1>

<p align="center">˚ʚ♡ɞ˚</p>

<p align="center">
  <strong>English</strong> · <a href="#русский">Русский</a>
</p>

<p align="center">
  Proxy and VPN client: subscriptions, standalone configs, routing.<br>
  Android · Windows · Linux
</p>

<p align="center">
  <a href="https://github.com/Lemonochka/keqdroid/releases"><img src="https://img.shields.io/github/v/release/Lemonochka/keqdroid?label=release&style=flat-square&color=f5a9b8" alt="release"></a>
  <a href="https://github.com/Lemonochka/keqdroid/releases"><img src="https://img.shields.io/github/downloads/Lemonochka/keqdroid/total?label=downloads&style=flat-square&logo=github&color=b5e8d5" alt="downloads"></a>
  <a href="https://github.com/Lemonochka/keqdroid/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/Lemonochka/keqdroid/ci.yml?branch=master&label=build&style=flat-square" alt="build"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-c9b8f5?style=flat-square" alt="license"></a>
  <img src="https://img.shields.io/badge/made%20with-Flutter-9bc7f0?style=flat-square" alt="flutter">
  <a href="https://t.me/keqdroid"><img src="https://img.shields.io/badge/Telegram-chat-8ec5e6?style=flat-square&logo=telegram&logoColor=white" alt="Telegram chat"></a>
</p>

<p align="center">
  <a href="https://github.com/Lemonochka/keqdroid/releases"><strong>Download</strong></a>
  &nbsp;·&nbsp;
  <a href="https://t.me/keqdroid">Telegram chat</a>
  &nbsp;·&nbsp;
  <a href="docs/README.md">Developer docs</a>
</p>

---

<h2 id="screenshots">Screenshots</h2>

| Android | Windows |
|:-------:|:-------:|
| <img src="docs/readme/android.png" width="280" alt="Android"> | <img src="docs/readme/windows.png" width="480" alt="Windows"> |

---

## Download

Pre-built binaries are on [Releases](https://github.com/Lemonochka/keqdroid/releases).  
Every asset ships with a `.sha256` next to it. The built-in updater checks the hash and refuses to install when the sidecar is missing or does not match.

| Platform | Files in release |
|----------|------------------|
| **Android** 7.0+ | `keqdroid-<version>-android.apk` |
| **Windows** x64 | `keqdroid-windows-x64-<version>.zip` (portable) |
| **Linux** x64 | `keqdroid-<version>-linux-x64.tar.gz` · `keqdroid-<version>-x86_64.AppImage` · `keqdroid_<version>_amd64.deb` · `PKGBUILD` for Arch |

The app **does not provide servers**. Bring your own subscription or configs. Comply with the laws of your country.

---

## Features

**Servers and subscriptions**
- subscription URLs with scheduled auto-update; `keqdroid://` and `keqdis://` deep links from provider panels
- manual entry, config import, QR code scan (Android)
- proxy chains: traffic passes through several servers in the order you set
- device identity per subscription — what the panel sees when the app fetches it
- checks: TCP, HTTP, ICMP, speed test; sorting by ping, name or speed

**Routing and tunnel**
- three lists — direct, through the VPN, blocked — plus ready-made presets to start from
- split tunnel: per-app on Android, per-program on Windows and Linux (TUN mode)
- **Connections** — a live list of where traffic is going and which rule sent it there

**Appearance and data**
- color presets, dark and light, Material You palette on Android
- interface size, on top of the system text size
- backup and restore: settings, servers, subscriptions with their images, split-tunnel lists
- share the local proxy over LAN
- hotkeys for connect/disconnect, TUN mode, best-ping server, show/hide window — system-wide on Windows, while the window is focused on Linux
- English, Русский, Deutsch, 中文, فارسی
- updates from GitHub Releases

---

## Cores

Four cores ship inside the app. Which one runs a given server is decided by the server's format, not by preference — a ready-made config only makes sense to the core it was written for:

| Server format | Runs on |
|---------------|---------|
| Links: `vless://` `vmess://` `trojan://` `ss://` `hy2://` | Xray or mihomo — your pick |
| Ready-made Xray config (`.json`) | Xray |
| Ready-made Clash / mihomo config | mihomo |
| Proxy chain | Xray |
| AmneziaWG profile (`.conf`) | amneziawg-go |

The choice lives in **Settings → About** and applies to links, where both cores fit. **Automatic** leaves it to the format. When a server cannot run on the core you picked, the app says so on the spot instead of quietly switching — a silent fallback is exactly what makes "I selected mihomo and it says Xray" impossible to debug.

---

## Protocols

| Protocol | Link format / import |
|----------|----------------------|
| VLESS | `vless://` |
| VMess | `vmess://` |
| Trojan | `trojan://` |
| Shadowsocks | `ss://` |
| Hysteria 2 | `hysteria2://`, `hy2://` |
| AmneziaWG | `.conf` profile |
| Ready-made Xray config | whole `.json` (paste, file, subscription) |
| Ready-made Clash config | whole config (paste, file, subscription) |

Hysteria v1 is not supported.

A ready-made config runs as its author wrote it — routing, DNS and outbound chains included; only the inbounds are replaced with the app's own. The name comes from the config's root `remarks`. The author's rules decide first, and your own direct / proxy / block lists only see what those rules did not already match — if the config ends with a catch-all, and most do, they never come into play at all.

---

## Platforms

### Android

| Mode | What it does |
|------|--------------|
| **VPN** | Everything on the device goes through the tunnel. VPN permission on first connect. |
| **Proxy** | SOCKS and HTTP on `127.0.0.1`, nothing captured on its own — point an app or the Wi-Fi proxy settings at it. |

Per-app routing and DNS interception belong to VPN mode; AmneziaWG servers always run as VPN. Notification shade icon and a Quick Settings tile; subscriptions update in the background.

### Windows

| Mode | What it does |
|------|--------------|
| **Proxy** | System proxy — browsers and most apps. No administrator rights. |
| **TUN** | All traffic through a VPN adapter. Run as administrator. |

The window minimizes to the tray and remembers its size and position. Launch at system startup with optional auto-connect. Global hotkeys are in Settings → Advanced → Hotkeys. Subscriptions refresh while the app is open.

**Settings location:** `%APPDATA%\com.keqdroid\keqdroid\` — not next to the exe. To move to another PC, use backup and restore in settings.

### Linux

Debian/Arch, x86_64. Releases ship tar.gz, AppImage and deb; Arch users get a `PKGBUILD` among the release assets.

| Mode | What it does |
|------|--------------|
| **Proxy** | No root |
| **TUN** | Root via `pkexec` (polkit) on connect |

The window remembers its size and position; hotkeys work while the app window is focused.

---

## Getting started

1. **Subscriptions** — paste the URL, then «Add and fetch».
2. **Servers** — pick a node.
3. Connect.
4. If needed — **Settings**: routing, split tunnel, hotkeys, connection mode.

---

## Development

Full docs in [`docs/`](docs/README.md): onboarding, architecture, project map, glossary, pitfalls.

### Build

```bash
flutter pub get
flutter build apk --release      # Android
flutter build windows --release  # Windows
```

The Windows plugin list (`windows/flutter/app_plugins.cmake`) is checked in with Firebase (Android-only) already stripped, so a normal build just works. Re-run `powershell -File tool/sync_windows_plugins.ps1` only after adding or removing plugins.

**Linux** — build on Linux or WSL only, the Windows SDK cannot target Linux:

```bash
wsl -e bash /mnt/c/.../keqdroid/tool/build_linux_wsl.sh
# binary: build/linux/x64/release/bundle/keqdroid
```

Place the required core binaries in `assets/bin/windows/` before a Windows build — see [`assets/bin/windows/README.md`](assets/bin/windows/README.md).

### Releases

```powershell
# APK + Windows zip, SHA-256, output to release\<version>\
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1

# same + publish GitHub Release (requires gh CLI)
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1 -Publish -NotesFile notes.md
```

Version and tag `vX.Y.Z` come from `pubspec.yaml`. When uploading manually, attach a `.sha256` for every asset — the updater treats a missing one as a reason to refuse.

---

## License

[GPL-3.0](LICENSE). The bundled cores keep their upstream licenses: Xray-core (MPL-2.0), mihomo (GPL-3.0), sing-box (GPL-3.0), amneziawg-go (MIT).

---

<h2 id="русский">Русский</h2>

<p align="center">˚ʚ♡ɞ˚</p>

<p align="center">
  <a href="#keqdis">English</a> · <strong>Русский</strong>
</p>

<p align="center">
  Клиент прокси и VPN: подписки, отдельные конфиги, маршрутизация.<br>
  Android · Windows · Linux
</p>

<p align="center">
  <a href="https://github.com/Lemonochka/keqdroid/releases"><img src="https://img.shields.io/github/v/release/Lemonochka/keqdroid?label=%D1%80%D0%B5%D0%BB%D0%B8%D0%B7&style=flat-square&color=f5a9b8" alt="релиз"></a>
  <a href="https://github.com/Lemonochka/keqdroid/releases"><img src="https://img.shields.io/github/downloads/Lemonochka/keqdroid/total?label=%D1%81%D0%BA%D0%B0%D1%87%D0%B8%D0%B2%D0%B0%D0%BD%D0%B8%D1%8F&style=flat-square&logo=github&color=b5e8d5" alt="скачивания"></a>
  <a href="https://github.com/Lemonochka/keqdroid/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/Lemonochka/keqdroid/ci.yml?branch=master&label=%D1%81%D0%B1%D0%BE%D1%80%D0%BA%D0%B0&style=flat-square" alt="сборка"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/%D0%BB%D0%B8%D1%86%D0%B5%D0%BD%D0%B7%D0%B8%D1%8F-GPL--3.0-c9b8f5?style=flat-square" alt="лицензия"></a>
  <img src="https://img.shields.io/badge/сделано%20на-Flutter-9bc7f0?style=flat-square" alt="flutter">
  <a href="https://t.me/keqdroid"><img src="https://img.shields.io/badge/Telegram-%D1%87%D0%B0%D1%82-8ec5e6?style=flat-square&logo=telegram&logoColor=white" alt="Чат в Telegram"></a>
</p>

<p align="center">
  <a href="https://github.com/Lemonochka/keqdroid/releases"><strong>Скачать</strong></a>
  &nbsp;·&nbsp;
  <a href="https://t.me/keqdroid">Чат в Telegram</a>
  &nbsp;·&nbsp;
  <a href="docs/README.md">Документация для разработчиков</a>
</p>

---

## Скачать

Скриншоты — [выше](#screenshots).

Готовые сборки — в [Releases](https://github.com/Lemonochka/keqdroid/releases).  
К каждому файлу приложен `.sha256`: встроенный апдейтер сверяет хеш и не ставит обновление, если файла с хешем нет или он не сошёлся.

| Платформа | Файлы в релизе |
|-----------|----------------|
| **Android** 7.0+ | `keqdroid-<версия>-android.apk` |
| **Windows** x64 | `keqdroid-windows-x64-<версия>.zip` (portable) |
| **Linux** x64 | `keqdroid-<версия>-linux-x64.tar.gz` · `keqdroid-<версия>-x86_64.AppImage` · `keqdroid_<версия>_amd64.deb` · `PKGBUILD` для Arch |

Приложение **не раздаёт серверы** — нужна своя подписка или конфиги. Соблюдайте законы вашей страны.

---

## Возможности

**Серверы и подписки**
- подписки по URL с автообновлением по расписанию; deep-ссылки `keqdroid://` и `keqdis://` из панелей провайдеров
- ручное добавление, импорт конфигов, сканирование QR-кодов (Android)
- цепочки прокси: трафик проходит через несколько серверов в заданном порядке
- идентичность устройства для каждой подписки — то, каким приложение представляется панели при загрузке
- проверки: TCP, HTTP, ICMP, тест скорости; сортировка по пингу, имени или скорости

**Маршрутизация и туннель**
- три списка — напрямую, через VPN, блокировать — и готовые пресеты, чтобы начать
- split tunnel: на Android по приложениям, на Windows и Linux по программам (режим TUN)
- **Соединения** — живой список того, куда идёт трафик и какое правило его туда отправило

**Оформление и данные**
- цветовые пресеты, тёмная и светлая тема, палитра Material You на Android
- размер интерфейса, поверх системного размера текста
- резервная копия и восстановление: настройки, серверы, подписки вместе с их картинками, списки split tunnel
- раздача локального прокси в локальную сеть
- хоткеи на подключение, режим TUN, сервер с лучшим пингом, показать/скрыть окно — глобальные на Windows, в фокусе окна на Linux
- English, Русский, Deutsch, 中文, فارسی
- обновление из GitHub Releases

---

## Ядра

Внутри приложения четыре ядра. Какое исполняет конкретный сервер, решает формат этого сервера, а не предпочтение: готовый конфиг понятен только тому ядру, для которого он написан.

| Формат сервера | Исполняет |
|----------------|-----------|
| Ссылки: `vless://` `vmess://` `trojan://` `ss://` `hy2://` | Xray или mihomo — на выбор |
| Готовый конфиг Xray (`.json`) | Xray |
| Готовый конфиг Clash / mihomo | mihomo |
| Цепочка прокси | Xray |
| Профиль AmneziaWG (`.conf`) | amneziawg-go |

Выбор живёт в **Настройки → О приложении** и касается ссылок — там подходят оба ядра. **Автоматически** отдаёт решение формату. Если сервер не может поехать на выбранном ядре, приложение скажет об этом сразу, а не переключится молча: именно тихий откат превращает «включила mihomo, а пишет Xray» в неразрешимую загадку.

---

## Протоколы

| Протокол | Формат ссылки / импорт |
|----------|------------------------|
| VLESS | `vless://` |
| VMess | `vmess://` |
| Trojan | `trojan://` |
| Shadowsocks | `ss://` |
| Hysteria 2 | `hysteria2://`, `hy2://` |
| AmneziaWG | профиль `.conf` |
| Готовый конфиг Xray | `.json` целиком (вставка, файл, подписка) |
| Готовый конфиг Clash | конфиг целиком (вставка, файл, подписка) |

Hysteria v1 не поддерживается.

Готовый конфиг исполняется так, как его написал автор: роутинг, DNS и цепочки аутбаундов остаются его, подменяются только инбаунды на собственные. Имя берётся из корневого `remarks`. Первыми решают авторские правила, и до списков обход / прокси / блок доходит только то, что они не поймали, — а если конфиг кончается catch-all-правилом, как бывает почти всегда, не доходит вовсе.

---

## Платформы

### Android

| Режим | Что делает |
|-------|------------|
| **VPN** | Через туннель идёт всё устройство. При первом подключении — разрешение VPN. |
| **Proxy** | SOCKS и HTTP на `127.0.0.1`, сам по себе не перехватывает ничего — на него нужно направить программу или настройки прокси в Wi-Fi. |

Маршрутизация по приложениям и перехват DNS живут в режиме VPN; серверы AmneziaWG всегда идут как VPN. Значок в шторке и плитка в быстрых настройках; подписки обновляются в фоне.

### Windows

| Режим | Что делает |
|-------|------------|
| **Proxy** | Системный прокси — браузеры и большинство программ. Без прав администратора. |
| **TUN** | Весь трафик через VPN-адаптер. Запуск от имени администратора. |

Окно сворачивается в трей и запоминает свой размер и позицию. Автозапуск вместе с системой, при желании с автоподключением. Глобальные хоткеи — в Настройки → Расширенные → Горячие клавиши. Подписки обновляются, пока приложение открыто.

**Где лежат настройки:** `%APPDATA%\com.keqdroid\keqdroid\` — не в папке с exe. Перенос на другой ПК: резервная копия и восстановление в настройках.

### Linux

Debian/Arch, x86_64. В релизе — tar.gz, AppImage, deb; для Arch среди файлов релиза есть `PKGBUILD`.

| Режим | Что делает |
|-------|------------|
| **Proxy** | Без root |
| **TUN** | Root через `pkexec` (polkit) при подключении |

Окно запоминает размер и позицию; хоткеи работают, пока окно приложения в фокусе.

---

## Начало работы

1. **Подписки** — вставить URL, затем «Добавить и загрузить».
2. **Серверы** — выбрать узел.
3. Подключиться.
4. При необходимости — **Настройки**: маршрутизация, split tunnel, хоткеи, режим подключения.

---

## Разработка

Полная документация — в [`docs/`](docs/README.md): онбординг, архитектура, карта проекта, словарь, грабли.

### Сборка

```bash
flutter pub get
flutter build apk --release      # Android
flutter build windows --release  # Windows
```

Список Windows-плагинов (`windows/flutter/app_plugins.cmake`) лежит в репозитории уже без Firebase (он только для Android), так что обычная сборка работает сразу. Перезапускать `powershell -File tool/sync_windows_plugins.ps1` нужно только после добавления или удаления плагинов.

**Linux** — только на Linux или в WSL, Windows SDK для Linux не подходит:

```bash
wsl -e bash /mnt/c/.../keqdroid/tool/build_linux_wsl.sh
# бинарь: build/linux/x64/release/bundle/keqdroid
```

Для Windows перед сборкой нужно положить бинарники ядер в `assets/bin/windows/` — см. [`assets/bin/windows/README.md`](assets/bin/windows/README.md).

### Релизы

```powershell
# APK + Windows-zip, SHA-256, папка release\<версия>\
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1

# то же + GitHub Release (нужен gh CLI)
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1 -Publish -NotesFile notes.md
```

Версия и тег `vX.Y.Z` берутся из `pubspec.yaml`. При ручной заливке к каждому файлу нужен `.sha256` — без него апдейтер откажется ставить обновление.

---

## Лицензия

[GPL-3.0](LICENSE). Встроенные ядра — под своими лицензиями: Xray-core (MPL-2.0), mihomo (GPL-3.0), sing-box (GPL-3.0), amneziawg-go (MIT).

---

<p align="center">✦ ˚ · . &nbsp; ˚ʚ♡ɞ˚ &nbsp; . · ˚ ✦</p>
<p align="center"><sub>made with ♡ · Flutter + Xray + mihomo + sing-box</sub></p>
