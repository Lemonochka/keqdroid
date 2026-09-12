import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers/server_config_editor.dart';

/// Редактор и параметры, которые приложение давно исполняет.
///
/// Жалоба: «недавно добавлены новые параметры и их поддержка, а настроить их на
/// этом экране нельзя». Здесь сторожим обе стороны: что поля видны и что при
/// сохранении ссылка не теряет то, чего редактор раньше не знал.
class _FakeServers extends ServersNotifier {
  _FakeServers(this._state);

  final ServersState _state;
  String? saved;

  @override
  ServersState build() => _state;

  @override
  Future<void> updateConfig(String id, String config) async => saved = config;
}

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

Future<_FakeServers> _open(WidgetTester tester, String link) async {
  tester.view.physicalSize = const Size(500, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final server = ServerItem.fromRaw(link);
  final servers = _FakeServers(ServersState(servers: [server]));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        serversProvider.overrideWith(() => servers),
        settingsNotifierProvider.overrideWith(_FakeSettings.new),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: ServerConfigEditorScreen(serverId: server.id),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return servers;
}

void main() {
  testWidgets('mKCP редактируется формой, а не только текстом', (tester) async {
    await _open(
      tester,
      'vless://716e3485-d4f9-4471-9660-fb4b0b838100@example.com:443'
      '?type=kcp&seed=hello&headerType=srtp&mtu=1350&tti=50#node',
    );

    // Раньше в списке транспортов не было ни mkcp, ни httpupgrade, и сервер на
    // них показывался как tcp — с чужими полями.
    expect(find.text('kcp'), findsWidgets);
    expect(find.text('Seed'), findsOneWidget);
    expect(find.text('MTU'), findsOneWidget);
  });

  testWidgets('параметры xhttp не теряются при сохранении', (tester) async {
    const link =
        'vless://716e3485-d4f9-4471-9660-fb4b0b838100@example.com:443'
        '?type=xhttp&security=reality&sni=example.com&fp=chrome'
        '&pbk=oYXosxG2YU6_mQkkPTS8JUnoRxqvaBaG5mH-y0pc2nA&sid=9f2c'
        '&mode=stream-one&x_padding_bytes=100-1000&path=%2Fdl#node';
    final servers = await _open(tester, link);

    // Правим адрес — иначе редактор честно ничего не пересобирает.
    await tester.enterText(find.byType(TextField).first, 'edited.example.com');
    await tester.pumpAndSettle();
    // Кнопка ниже сгиба: без прокрутки tap попадёт мимо экрана и промолчит.
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = servers.saved;
    expect(saved, isNotNull);
    expect(saved, contains('edited.example.com'));
    for (final part in [
      'type=xhttp',
      'mode=stream-one',
      'x_padding_bytes=100-1000',
      'security=reality',
      'pbk=',
    ]) {
      expect(saved, contains(part), reason: part);
    }
  });

  testWidgets('Vision на xhttp: и предупреждение, и отсутствие выбора', (
    tester,
  ) async {
    await _open(
      tester,
      'vless://716e3485-d4f9-4471-9660-fb4b0b838100@example.com:443'
      '?type=xhttp&security=reality&flow=xtls-rprx-vision'
      '&pbk=oYXosxG2YU6_mQkkPTS8JUnoRxqvaBaG5mH-y0pc2nA#node',
    );

    expect(
      find.textContaining('Vision only works on TCP'),
      findsOneWidget,
      reason: 'ядро такой сервер не поднимет, и это надо сказать',
    );
  });

  testWidgets('на TCP с REALITY Vision остаётся доступным', (tester) async {
    await _open(
      tester,
      'vless://716e3485-d4f9-4471-9660-fb4b0b838100@example.com:443'
      '?type=tcp&security=reality&flow=xtls-rprx-vision'
      '&pbk=oYXosxG2YU6_mQkkPTS8JUnoRxqvaBaG5mH-y0pc2nA#node',
    );

    expect(find.textContaining('Vision only works on TCP'), findsNothing);
    expect(find.text('xtls-rprx-vision'), findsWidgets);
  });
}
