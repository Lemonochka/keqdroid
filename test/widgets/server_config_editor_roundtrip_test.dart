import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers/server_config_editor.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/server_config_form_corpus.dart';

// потерянный при пересборке параметр молча портит сервер, эталон снят со старого кода: UPDATE_GOLDEN=1
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

Future<String?> _editAddressAndSave(WidgetTester tester, String link) async {
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
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
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

  await tester.enterText(find.byType(TextField).first, 'edited.example.com');
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Save'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
  return servers.saved;
}

void main() {
  final update = Platform.environment['UPDATE_GOLDEN'] == '1';
  final file = File(serverConfigFormGolden);
  final golden = update
      ? <String, dynamic>{}
      : jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  serverConfigFormCorpus.forEach((name, link) {
    testWidgets(name, (tester) async {
      final saved = await _editAddressAndSave(tester, link);
      expect(saved, isNotNull, reason: 'editor did not save');
      expect(
        saved!.startsWith('vmess://')
            ? utf8.decode(base64.decode(saved.substring(8)))
            : saved,
        contains('edited.example.com'),
      );
      if (update) {
        golden[name] = saved;
      } else {
        expect(saved, golden[name]);
      }
    });
  });

  if (update) {
    tearDownAll(() {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(golden)}\n',
      );
    });
  }
}
