# Onboarding: окружение, сборка, запуск, тесты

Цель документа — за один присест довести нового разработчика до состояния
«собрал, запустил, прогнал тесты». Архитектуру здесь не объясняем — это
[ARCHITECTURE.md](ARCHITECTURE.md).

## 1. Что нужно установить

| Инструмент | Версия | Зачем |
|------------|--------|-------|
| **Flutter SDK** | stable, **3.41.x** (Dart `^3.11.3`) | основной тулчейн |
| **Android Studio** + Android SDK | Android 7.0+ (minSdk = Flutter default, см. `android/app/build.gradle`) | сборка/запуск Android |
| **JDK** | 17 | Gradle/Android |
| **Visual Studio 2022** + «Desktop development with C++» | — | сборка Windows (нативный runner на C++) |
| **Git Bash** или WSL | — | bash-скрипты сборки Linux/ядер |
| **gh CLI** | — | публикация релизов (необязательно) |

Проверка окружения:

```bash
flutter doctor
```

## 2. Первый запуск (любая платформа)

```bash
flutter pub get          # зависимости + кодоген локализаций (flutter: generate: true)
```

После `pub get` локализации (`lib/l10n/app_localizations*.dart`) генерируются автоматически
из ARB-файлов. Если правишь строки — см. раздел 6.

## 3. Сборка и запуск по платформам

### Android

```bash
flutter run                       # debug на подключённом устройстве/эмуляторе
flutter build apk --release       # релизный APK
```

- Минимум Android 7.0. При первом подключении система спросит **разрешение VPN**.
- Нативные ядра для Android лежат как **`jniLibs`** (`android/app/src/main/jniLibs/<abi>/*.so`),
  а не как Flutter-ассеты (см. [PITFALLS.md](PITFALLS.md) про размер APK).
- **Crashlytics** (Firebase) — только Android и только в release. Без
  `google-services.json` приложение спокойно работает, просто без репортинга крэшей.

### Windows

```bash
flutter pub get
powershell -File tool/sync_windows_plugins.ps1   # ОБЯЗАТЕЛЬНО перед сборкой Windows
flutter build windows --release
```

- `sync_windows_plugins.ps1` вырезает Firebase из сгенерированного списка Windows-плагинов
  (Firebase — Android-only; без этого шага линковка Windows падает).
- Нативные ядра Windows (`keqrnel.exe`/`xray.exe`, при необходимости `sing-box.exe`,
  `wireproxy.exe`, `wintun.dll`, `geoip.dat`, `geosite.dat`) кладутся **рядом с `keqdroid.exe`**
  через `windows/CMakeLists.txt`, а не пакуются в APK. Исходно они лежат в
  `assets/bin/windows/` — см. [`assets/bin/windows/README.md`](../assets/bin/windows/README.md).
- **TUN-режим требует прав администратора** (sing-box создаёт wintun-адаптер). Proxy-режим
  работает без админ-прав.

### Linux (Debian/Arch, x86_64)

Собирать **только на нативном Linux или в WSL** — Windows-SDK для Linux-таргета не годится.
Готовый скрипт ставит тулчейн + нативный Flutter SDK и собирает:

```bash
wsl -e bash /mnt/c/.../keqdroid/tool/build_linux_wsl.sh
# бинарь: build/linux/x64/release/bundle/keqdroid
```

- Ядра Linux (`xray`, `wireproxy`, `sing-box`, `keqrnel`, geo) — в `assets/bin/linux/`.
- **Proxy** работает без root; **TUN** запрашивает root через `pkexec` (polkit) при подключении.
- Упаковка в `.deb`/AppImage/tar.gz/PKGBUILD — `tool/package_linux.sh`.

## 4. Запуск тестов

```bash
flutter test                      # весь набор
flutter test test/utils/config_gen_test.dart   # один файл
flutter analyze                   # статический анализ (должен быть «No issues found!»)
```

Тесты разложены по зеркалам `lib/`:

```
test/
  utils/     — генерация конфигов, парсинг URI/AWG, роутинг
  services/  — storage, subscriptions, update, ping
  models/    — настройки ядра, имена серверов, ping-таргеты
  tunnel/    — разбор статистики сессии
  widgets/   — навигация, вкладки, индикатор подключения
  helpers/   — pump_app.dart, test_storage.dart (фикстуры)
```

Чистый `flutter analyze` и зелёный `flutter test` — обязательное условие любого PR.

## 5. Сборка нативных ядер (редко нужно)

Ядра обычно уже лежат собранные в `assets/bin/` и `jniLibs/`. Пересобирать нужно только
при обновлении версий ядра:

| Скрипт | Что собирает |
|--------|--------------|
| `tool/build_amneziawg.ps1` | AmneziaWG-ядро (`wireproxy-awg`) для Windows |
| `tool/build_linux_native.sh` / `build_linux_wsl.sh` | весь Linux-бандл + ядра |
| `tool/fetch_xray_geo.ps1` | свежие `geoip.dat` / `geosite.dat` для xray |
| `tools/amneziawg_android/` | сборка AmneziaWG `.so` под Android |

> Важно про `xray.exe`/`wireproxy.exe` под Windows: собирать **unstripped** и бандлить в
> ассеты, **не** запускать из `%TEMP%` — иначе Defender помечает их как угрозу. Подробности —
> [PITFALLS.md](PITFALLS.md).

## 6. Локализация (4 языка: en / ru / de / zh)

- Источник истины — ARB-файлы: `lib/l10n/app_en.arb` (база), `app_ru.arb`, `app_de.arb`,
  `app_zh.arb`. Конфиг — `l10n.yaml`.
- Добавил/изменил строку → правишь **все** ARB, затем:

```bash
flutter gen-l10n        # или просто flutter pub get / flutter run — генерится автоматически
```

- В коде строки берутся через `AppLocalizations.of(context)!.<ключ>`.
- Не редактируй вручную `app_localizations*.dart` — они генерируемые.

## 7. Релиз (для мейнтейнера)

```powershell
# собрать APK + Windows-zip, посчитать SHA-256, разложить в release\<версия>\
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1

# то же + публикация GitHub-релиза (нужен gh CLI)
powershell -ExecutionPolicy Bypass -File tool\make_release.ps1 -Publish -NotesFile notes.md
```

- Версия и тег (`vX.Y.Z`) берутся из `version:` в `pubspec.yaml`.
- **Каждый ассет обязан иметь `<имя>.sha256`** (ASCII без BOM). Встроенный `UpdateService`
  проверяет хеш и **отклоняет** установку без него (fail-closed). `make_release.ps1`
  генерирует их сам.

## Чек-лист «готов к работе»

- [ ] `flutter doctor` без критичных ошибок
- [ ] `flutter pub get` отработал
- [ ] приложение запускается на твоей платформе
- [ ] `flutter analyze` → No issues found
- [ ] `flutter test` → все зелёные
- [ ] прочитал [ARCHITECTURE.md](ARCHITECTURE.md) и [PITFALLS.md](PITFALLS.md)
