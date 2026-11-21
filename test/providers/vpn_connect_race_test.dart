import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/core/exceptions.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/vpn_engine.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

// нажатия посреди подключения: туннель обязан доехать до сервера, который выбран последним,
// и ни одна отменённая попытка не поднимает свой сервер поверх новой

class _GatedBackend extends FakeTunnelBackend {
  final calls = <String>[];
  final _states = StreamController<VpnState>.broadcast();
  VpnState current = VpnState.disconnected;
  String? running;
  ConnectionMode? runningMode;
  bool? reloads;
  int _stops = 0;

  // как Windows в режиме прокси: стоп посреди старта выключает системный прокси, и старт падает на его проверке
  bool failIfStoppedDuringStart = false;

  // следующий старт или подмена конфига ждёт, пока тест не отпустит
  Completer<void>? gate;
  Completer<void> entered = Completer<void>();

  Future<void> _pass() async {
    final g = gate;
    if (g == null) return;
    gate = null;
    if (!entered.isCompleted) entered.complete();
    await g.future;
  }

  // сборка сессии берёт логин и пароль у движка: здесь её можно придержать до старта ядра
  Completer<void>? credsGate;
  Completer<void> credsEntered = Completer<void>();

  Completer<void> holdBuild() {
    credsEntered = Completer<void>();
    return credsGate = Completer<void>();
  }

  @override
  Future<({String username, String password})> fetchSocksCredentials() async {
    final g = credsGate;
    if (g != null) {
      credsGate = null;
      credsEntered.complete();
      await g.future;
    }
    return super.fetchSocksCredentials();
  }

  @override
  Stream<VpnState> get stateStream => _states.stream;

  @override
  Future<VpnState> getCurrentState() async => current;

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    final stopsBefore = _stops;
    await _pass();
    if (failIfStoppedDuringStart && _stops != stopsBefore) {
      const message = 'System proxy was not applied (enabled=false, server="")';
      // настоящий бэкенд сперва шлёт ошибку в поток состояний, потом бросает
      _states.add(
        const VpnState(status: VpnStatus.error, errorMessage: message),
      );
      throw const VpnStartException(message);
    }
    calls.add('start ${request.serverName}');
    running = request.serverName;
    runningMode = request.mode;
    current = const VpnState(status: VpnStatus.connected);
  }

  Completer<void>? stopGate;
  Completer<void> stopEntered = Completer<void>();

  Completer<void> holdStop() {
    stopEntered = Completer<void>();
    return stopGate = Completer<void>();
  }

  @override
  Future<void> stopSession() async {
    final g = stopGate;
    if (g != null) {
      stopGate = null;
      stopEntered.complete();
      await g.future;
    }
    _stops++;
    calls.add('stop');
    running = null;
    runningMode = null;
    current = VpnState.disconnected;
    _states.add(VpnState.disconnected);
  }

  @override
  Future<bool> reloadMihomoConfig(TunnelSessionRequest request) async {
    final ok = reloads;
    if (ok == null) return super.reloadMihomoConfig(request);
    await _pass();
    calls.add('reload ${request.serverName}');
    if (ok) running = request.serverName;
    return ok;
  }

  Completer<void> hold() {
    entered = Completer<void>();
    return gate = Completer<void>();
  }

  @override
  void dispose() {
    unawaited(_states.close());
    super.dispose();
  }
}

// адрес цифрами: имя ушло бы в DNS и ждало его 5 с на каждом подключении
ServerItem _server(String id, String ip) => ServerItem(
  id: id,
  type: ServerItemType.manual,
  config:
      'vless://00000000-0000-4000-8000-000000000000@$ip:443'
      '?type=tcp&security=tls&sni=$id.example.com#$id',
);

final _a = _server('a', '192.0.2.1');
final _b = _server('b', '192.0.2.2');
final _c = _server('c', '192.0.2.3');

Future<ProviderContainer> _ready(
  _GatedBackend backend, {
  String core = AppSettings.vpnCoreXray,
}) async {
  final storage = await buildStorageService();
  await storage.saveServers([_a, _b, _c]);
  await storage.setActiveServerId(_a.id);
  await storage.saveSettings(AppSettings(vpnCore: core));
  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(backend)),
    ],
  );
  addTearDown(container.dispose);
  container.read(serversProvider);
  await container.read(vpnStateProvider.future);
  return container;
}

// как _selectServer на экране серверов: сперва выбор, потом просьба переехать
Future<void> _pick(ProviderContainer container, ServerItem server) async {
  await container.read(serversProvider.notifier).setActive(server);
  await container.read(vpnStateProvider.notifier).reconnectToActiveServer();
}

VpnStatus? _status(ProviderContainer c) => c.read(vpnStateProvider).value?.status;

String? _shown(ProviderContainer c) => c.read(serversProvider).activeServerId;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('сервер выбрали посреди подключения: туннель доезжает до него', () async {
    final backend = _GatedBackend();
    final container = await _ready(backend);
    final vpn = container.read(vpnStateProvider.notifier);

    final release = backend.hold();
    final connecting = vpn.connect();
    await backend.entered.future;
    expect(_status(container), VpnStatus.connecting);

    await _pick(container, _b);
    release.complete();
    await connecting;

    expect(_shown(container), 'b');
    expect(backend.running, 'b', reason: 'на экране b, значит и туннель на b');
    expect(_status(container), VpnStatus.connected);
  });

  test('на xray выбрали третий сервер, пока шла смена на второй', () async {
    final backend = _GatedBackend();
    final container = await _ready(backend);
    await container.read(vpnStateProvider.notifier).connect();
    expect(backend.running, 'a');

    final release = backend.hold();
    final switching = _pick(container, _b);
    await backend.entered.future;
    await _pick(container, _c);
    release.complete();
    await switching;

    expect(_shown(container), 'c');
    expect(backend.running, 'c');
    expect(_status(container), VpnStatus.connected);
  });

  test('на mihomo выбрали третий сервер, пока второй подменялся на ходу', () async {
    final backend = _GatedBackend()..reloads = true;
    final container = await _ready(backend, core: AppSettings.vpnCoreMihomo);
    await container.read(vpnStateProvider.notifier).connect();

    final release = backend.hold();
    final switching = _pick(container, _b);
    await backend.entered.future;
    await _pick(container, _c);
    release.complete();
    await switching;

    expect(backend.calls.where((c) => c.startsWith('reload')).last, 'reload c');
    expect(backend.running, 'c');
    expect(_status(container), VpnStatus.connected);
  });

  test('отмена, другой сервер и снова подключить: старая попытка не всплывает', () async {
    final backend = _GatedBackend();
    final container = await _ready(backend);
    final vpn = container.read(vpnStateProvider.notifier);

    final release = backend.hold();
    final first = vpn.connect().catchError((Object _) {});
    await backend.entered.future;
    await vpn.cancelConnect();
    await pumpEventQueue();
    // после отмены экран только выбирает: туннеля нет, переезжать нечему
    await container.read(serversProvider.notifier).setActive(_b);
    final second = vpn.connect();
    release.complete();
    await first;
    await second;

    expect(backend.running, 'b');
    expect(backend.calls.last, 'start b');
    expect(_status(container), VpnStatus.connected);
  });

  // на Windows стоп от отмены идёт рядом со стартом и, доделываясь позже, выключал прокси нового старта
  test('стоп от отмены ещё идёт: новый старт ждёт его и не теряет ядро', () async {
    final backend = _GatedBackend();
    final container = await _ready(backend);
    final vpn = container.read(vpnStateProvider.notifier);

    final releaseStart = backend.hold();
    final first = vpn.connect().catchError((Object _) {});
    await backend.entered.future;
    final releaseStop = backend.holdStop();
    final cancelling = vpn.cancelConnect();
    await backend.stopEntered.future;
    await container.read(serversProvider.notifier).setActive(_b);
    final second = vpn.connect();
    releaseStart.complete();
    await first;
    await pumpEventQueue();
    expect(backend.calls, isNot(contains('start b')), reason: 'стоп ещё идёт');

    releaseStop.complete();
    await cancelling;
    await second;

    expect(backend.running, 'b');
    expect(backend.calls.last, 'start b');
    expect(_status(container), VpnStatus.connected);
  });

  // в песочнице отмена через 200 мс: ядро всё равно стартовало, экран снова показывал подключение,
  // и следующее нажатие подключить отменяло уже его
  test('отмена, пока собирается конфиг: ядро не запускается', () async {
    final backend = _GatedBackend();
    final container = await _ready(backend);
    final vpn = container.read(vpnStateProvider.notifier);

    final release = backend.holdBuild();
    final first = vpn.connect().catchError((Object _) {});
    await backend.credsEntered.future;
    await vpn.cancelConnect();
    release.complete();
    await first;
    await pumpEventQueue();

    expect(backend.calls.where((c) => c.startsWith('start')), isEmpty);
    expect(_status(container), VpnStatus.disconnected);

    await container.read(serversProvider.notifier).setActive(_b);
    await vpn.connect();
    expect(backend.running, 'b');
    expect(_status(container), VpnStatus.connected);
  });

  test('подключить, отмена, подключить, отмена: в конце выключено', () async {
    final backend = _GatedBackend();
    final container = await _ready(backend);
    final vpn = container.read(vpnStateProvider.notifier);

    final release = backend.hold();
    final first = vpn.connect().catchError((Object _) {});
    await backend.entered.future;
    await vpn.cancelConnect();
    await pumpEventQueue();
    final second = vpn.connect();
    await pumpEventQueue();
    await vpn.cancelConnect();
    release.complete();
    await first;
    await second;
    await pumpEventQueue();

    expect(backend.running, isNull, reason: 'последнее нажатие было отменой');
    expect(_status(container), isNot(VpnStatus.connected));
  });

  test('выбор посреди подключения и потом отмена: никуда не подключаемся', () async {
    final backend = _GatedBackend();
    final container = await _ready(backend);
    final vpn = container.read(vpnStateProvider.notifier);

    final release = backend.hold();
    final first = vpn.connect().catchError((Object _) {});
    await backend.entered.future;
    await _pick(container, _b);
    await vpn.cancelConnect();
    release.complete();
    await first;
    await pumpEventQueue();

    expect(backend.running, isNull);
    expect(backend.calls, isNot(contains('start b')));
    expect(_status(container), isNot(VpnStatus.connected));
  });

  // видео 22.11 с Windows: TUN выбрали, пока Proxy подключался. Попытка Proxy падала на проверке прокси,
  // который выключил стоп смены режима, а подключение в TUN выкидывалось как уже идущее
  test('режим сменили посреди подключения: без ошибки, туннель в новом режиме', () async {
    final backend = _GatedBackend()..failIfStoppedDuringStart = true;
    final container = await _ready(backend);
    final vpn = container.read(vpnStateProvider.notifier);
    final settings = container.read(settingsNotifierProvider.notifier);
    await settings.save(
      (await container.read(settingsNotifierProvider.future)).copyWith(
        connectionMode: ConnectionMode.proxy.storageValue,
      ),
    );

    final seen = <VpnStatus?>[];
    container.listen(
      vpnStateProvider,
      (_, next) => seen.add(next.value?.status),
    );

    final release = backend.hold();
    Object? failure;
    final first = vpn.connect().catchError((Object e) => failure = e);
    await backend.entered.future;

    // по шагам applyDesktopConnectionMode: отключить, сохранить режим, подключить
    await vpn.disconnect();
    await settings.save(
      (await container.read(settingsNotifierProvider.future)).copyWith(
        connectionMode: ConnectionMode.tun.storageValue,
      ),
    );
    final second = vpn.connect();
    release.complete();
    await first;
    await second;

    expect(failure, isNull, reason: 'отменённая попытка не показывает ошибку');
    expect(seen, isNot(contains(VpnStatus.error)));
    expect(backend.running, 'a');
    expect(backend.runningMode, ConnectionMode.tun);
    expect(_status(container), VpnStatus.connected);
  });

  // горячая клавиша и трей отключают и посреди подключения
  test('отключили посреди подключения, старт упал на стопе: на экране выключено', () async {
    final backend = _GatedBackend()..failIfStoppedDuringStart = true;
    final container = await _ready(backend);
    final vpn = container.read(vpnStateProvider.notifier);
    final seen = <VpnStatus?>[];
    container.listen(
      vpnStateProvider,
      (_, next) => seen.add(next.value?.status),
    );

    final release = backend.hold();
    Object? failure;
    final first = vpn.connect().catchError((Object e) => failure = e);
    await backend.entered.future;
    await vpn.disconnect();
    release.complete();
    await first;
    await pumpEventQueue();

    expect(failure, isNull);
    expect(seen, isNot(contains(VpnStatus.error)));
    expect(_status(container), VpnStatus.disconnected);
  });

  test('отключили посреди подключения: ядро, поднятое после стопа, гасится', () async {
    final backend = _GatedBackend();
    final container = await _ready(backend);
    final vpn = container.read(vpnStateProvider.notifier);

    final release = backend.hold();
    final first = vpn.connect().catchError((Object _) {});
    await backend.entered.future;
    await vpn.disconnect();
    release.complete();
    await first;
    await pumpEventQueue();

    expect(backend.running, isNull);
    expect(_status(container), VpnStatus.disconnected);
  });

  test('повторное нажатие подключить во время подключения ничего не дублирует', () async {
    final backend = _GatedBackend();
    final container = await _ready(backend);
    final vpn = container.read(vpnStateProvider.notifier);

    final release = backend.hold();
    final first = vpn.connect();
    await backend.entered.future;
    final again = vpn.connect();
    release.complete();
    await first;
    await again;

    expect(backend.calls, ['start a']);
    expect(_status(container), VpnStatus.connected);
  });
}
