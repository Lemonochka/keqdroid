import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers/server_config_editor.dart';

/// Готовый конфиг из подписки: у него нет share-ссылки, поэтому редактор
/// открывается в сыром режиме с окном на 26 строк — самый высокий экран
/// приложения, и именно на нём всплывает клавиатура.
const _customConfig = '''
{
  "dns": { "servers": ["1.1.1.1", "1.0.0.1"] },
  "routing": {
    "rules": [
      { "ip": ["geoip:private"], "outboundTag": "direct" }
    ],
    "domainStrategy": "IPIfNonMatch"
  },
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "185.22.235.13",
            "port": 8443,
            "users": [{"id": "716e3485-d4f9-4471-9660-fb4b0b838100", "encryption": "none"}]
          }
        ]
      }
    },
    { "tag": "direct", "protocol": "freedom" },
    { "tag": "block", "protocol": "blackhole" }
  ],
  "remarks": "WHITE BOSS MOUSER"
}
''';

class _FakeServers extends ServersNotifier {
  _FakeServers(this._state);

  final ServersState _state;

  @override
  ServersState build() => _state;
}

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

/// Экран под роутом: возврат назад обязан пройти через настоящий pop.
Future<void> _pumpEditor(WidgetTester tester, ServerItem server) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        serversProvider.overrideWith(
          () => _FakeServers(ServersState(servers: [server])),
        ),
        settingsNotifierProvider.overrideWith(_FakeSettings.new),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ServerConfigEditorScreen(serverId: server.id),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Клавиатура в тесте — это отъедающий низ экрана `viewInsets`.
void _setKeyboard(WidgetTester tester, double height) {
  tester.view.viewInsets = FakeViewPadding(bottom: height);
}

void main() {
  final server = ServerItem.fromRaw(_customConfig);

  setUp(() {
    // 360×640 — обычный телефон; на нём клавиатура съедает больше половины.
    // Physical, а не logical: dpr держим 1.0.
  });

  tearDown(() {
    // Иначе следующий тест стартует с поднятой клавиатурой.
  });

  testWidgets('редактор custom-конфига переживает клавиатуру и возврат назад', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await _pumpEditor(tester, server);
    expect(tester.takeException(), isNull);

    // Клавиатура вверх — фокус в окне сырого конфига.
    await tester.tap(find.byType(TextField).first);
    _setKeyboard(tester, 320);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Назад с ПОДНЯТОЙ клавиатурой: именно так экран и закрывают руками, а
    // inset схлопывается уже после того, как маршрут начал уезжать.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pump();
    _setKeyboard(tester, 0);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('правка текста при поднятой клавиатуре не роняет экран', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await _pumpEditor(tester, server);

    _setKeyboard(tester, 320);
    await tester.pumpAndSettle();

    // Ломаем json, потом чиним: на этом переключается высота окна (26↔10
    // строк) и пересобирается форма — всё под клавиатурой.
    await tester.enterText(find.byType(TextField).first, 'not a config');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField).first, _customConfig);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pump();
    _setKeyboard(tester, 0);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
