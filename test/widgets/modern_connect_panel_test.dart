import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/l10n/app_localizations_en.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/providers/halloween_provider.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers_tab.dart';
import 'package:keqdroid/services/exit_ip_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/shared/ui/liquid_wave.dart';
import 'package:keqdroid/shared/ui/stat_strip.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

/// Верх экрана серверов в двух видах: «Легаси» как было и «Модерн» одной
/// панелью. Переключатель во «Внешнем виде» не должен оставлять мёртвый режим.

class _FakeServers extends ServersNotifier {
  static final pinged = <String>[];

  @override
  Future<void> pingSingle(String serverId) async => pinged.add(serverId);

  @override
  ServersState build() => ServersState(
        servers: [
          ServerItem(
            id: 'pl',
            config: 'vless://00000000-0000-0000-0000-000000000000@pl.example'
                '.com:443#Poland',
            type: ServerItemType.manual,
            pingMs: 44,
            lastTestedAt: DateTime(2026),
          ),
        ],
        activeServerId: 'pl',
      );
}

// боком плашке достаётся узкая колонка, пинг рядом с именем её переполняет
class _FakeServersNoPing extends _FakeServers {
  @override
  ServersState build() {
    final state = super.build();
    return ServersState(
      servers: [
        for (final s in state.servers) s.copyWith(pingMs: null, lastTestedAt: null),
      ],
      activeServerId: state.activeServerId,
    );
  }
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);
  final AppSettings _settings;
  @override
  Future<AppSettings> build() async => _settings;
}

class _FakeVpn extends VpnStateNotifier {
  _FakeVpn(this._state);
  final VpnState _state;
  @override
  Future<VpnState> build() async => _state;
}

class _NoHalloween extends HalloweenActiveNotifier {
  @override
  bool build() => false;
}

final _l10n = AppLocalizationsEn();

Future<void> _pump(
  WidgetTester tester, {
  required bool modern,
  VpnState vpn = const VpnState(status: VpnStatus.disconnected),
  AppSettings settings = const AppSettings(),
  ExitIp? exit,
  Size size = const Size(412, 900),
  ServersNotifier Function() servers = _FakeServers.new,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = await tester.runAsync(buildStorageService);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage!),
        serversProvider.overrideWith(servers),
        settingsNotifierProvider.overrideWith(
          () => _FakeSettings(settings.copyWith(modernConnectPanel: modern)),
        ),
        vpnStateProvider.overrideWith(() => _FakeVpn(vpn)),
        halloweenActiveProvider.overrideWith(_NoHalloween.new),
        // настоящий запрос IP выхода повторяется через 3 и 10 секунд и переживает тест
        exitIpProvider.overrideWith((ref) async => exit),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ServersTab()),
      ),
    ),
  );
  // волна в шапке анимируется вечно, pumpAndSettle повис бы
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('«Модерн» собирает сервер и пинг в панель', (tester) async {
    await _pump(tester, modern: true);
    // имя сервера в панели и в строке списка
    expect(find.text('Poland'), findsNWidgets(2));
    expect(find.textContaining('44 ms'), findsNWidgets(2));
    expect(find.text(_l10n.vpnTapToConnect('Poland')), findsNothing);
  });

  testWidgets('время работы стоит под сервером, а не строкой во всю ширину', (
    tester,
  ) async {
    await _pump(
      tester,
      modern: true,
      vpn: const VpnState(
        status: VpnStatus.connected,
        duration: Duration(minutes: 5, seconds: 31),
      ),
      settings: const AppSettings().copyWith(
        showTrafficStats: false,
        showConnectionTime: true,
      ),
    );
    expect(find.textContaining('5m 31s'), findsOneWidget);
    expect(find.byType(StatStrip), findsNothing);
  });

  for (final (landscape, size) in [
    (false, const Size(412, 900)),
    (true, const Size(1000, 450)),
  ]) {
    testWidgets(
      landscape
          ? 'боком время встаёт в блок статистики четвёртой ячейкой'
          : 'на вертикальном экране время под сервером, а не в блоке',
      (tester) async {
        PlatformBootstrap.debugIsDesktopOverride = false;
        addTearDown(() => PlatformBootstrap.debugIsDesktopOverride = null);
        await _pump(
          tester,
          modern: true,
          size: size,
          servers: _FakeServersNoPing.new,
          vpn: const VpnState(
            status: VpnStatus.connected,
            duration: Duration(minutes: 5, seconds: 31),
          ),
          settings: const AppSettings().copyWith(
            showTrafficStats: true,
            showConnectionTime: true,
            showTrafficSplit: false,
          ),
        );
        final time = find.textContaining('5m 31s');
        expect(time, findsOneWidget);
        expect(
          find.descendant(of: find.byType(StatStrip), matching: time),
          landscape ? findsOneWidget : findsNothing,
        );
      },
    );
  }

  testWidgets('«Легаси»: под кнопкой плашка из состояния и сервера', (
    tester,
  ) async {
    await _pump(tester, modern: false);
    expect(find.text(_l10n.trayStatusDisconnected), findsOneWidget);
    expect(find.text('Poland'), findsNWidgets(2));
    expect(find.text(_l10n.vpnTapToConnect('Poland')), findsNothing);
  });

  for (final (modern, presets) in [
    (true, panelLiquidShapes),
    (false, legacyLiquidShapes),
  ]) {
    testWidgets('фигурки в фоне, ${modern ? 'модерн' : 'легаси'}', (
      tester,
    ) async {
      await _pump(tester, modern: modern);
      final wave = tester.widget<LiquidWave>(find.byType(LiquidWave));
      expect(wave.shapePresets, same(presets));
    });
  }

  testWidgets('«Легаси»: состояние в плашке идёт за подключением', (
    tester,
  ) async {
    await _pump(
      tester,
      modern: false,
      vpn: const VpnState(status: VpnStatus.connected),
    );
    expect(find.text(_l10n.trayStatusConnected), findsOneWidget);
    expect(find.text(_l10n.trayStatusDisconnected), findsNothing);
  });

  for (final modern in [true, false]) {
    testWidgets(
      'флаг в плашке показывает IP выхода (${modern ? 'модерн' : 'легаси'})',
      (tester) async {
        await _pump(
          tester,
          modern: modern,
          vpn: const VpnState(status: VpnStatus.connected),
          exit: const ExitIp(ip: '144.31.3.189', countryCode: 'PL'),
        );
        expect(find.text('144.31.3.189'), findsNothing);
        await tester.tap(find.bySemanticsLabel(_l10n.exitIpLabel));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('144.31.3.189'), findsOneWidget);
      },
    );
  }

  testWidgets('нажатие на пинг в плашке перепинговывает сервер', (
    tester,
  ) async {
    _FakeServers.pinged.clear();
    await _pump(tester, modern: true);
    await tester.tap(find.byTooltip(_l10n.serversPingServer));
    await tester.pump();
    expect(_FakeServers.pinged, ['pl']);
  });

  test('выбор режима переживает сохранение настроек', () {
    final saved = const AppSettings()
        .copyWith(modernConnectPanel: true)
        .toJsonString();
    expect(AppSettings.fromJsonString(saved).modernConnectPanel, isTrue);
    expect(const AppSettings().modernConnectPanel, isFalse);
  });
}
