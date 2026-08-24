import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers/server_config_editor.dart';

/// `ListTile` рисует свой фон и чернила на БЛИЖАЙШЕМ `Material`-предке.
///
/// Секции редактора были `Container` с `BoxDecoration`, то есть ближе
/// `SwitchListTile` оказывался крашеный `DecoratedBox` — и Flutter ронял ассерт
/// «ListTile background color or ink splashes may be invisible» прямо при
/// заходе в конфиг сервера. В дебаге это отваливший кусок экрана, в релизе —
/// тихо съеденные чернила.
///
/// Ссылка с `security=tls`: только тогда в секции безопасности появляется
/// тумблер `allowInsecure`, а с ним и весь этот случай.
const _tlsLink =
    'vless://716e3485-d4f9-4471-9660-fb4b0b838100@example.com:443'
    '?type=tcp&security=tls&sni=example.com#node';

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

void main() {
  testWidgets('секции редактора дают ListTile свой Material', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final server = ServerItem.fromRaw(_tlsLink);

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
          home: ServerConfigEditorScreen(serverId: server.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byType(SwitchListTile),
      findsWidgets,
      reason: 'без тумблера тест ничего не проверяет',
    );

    // Тап по тумблеру запускает чернила — тот самый путь, на который ругался
    // ассерт.
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
