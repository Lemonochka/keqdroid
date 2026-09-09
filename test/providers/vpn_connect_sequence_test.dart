import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

/// Предохранитель на порядок шагов `VpnStateNotifier.connect()`.
///
/// Шаги связаны не логикой, а временем: креды нужны раньше, чем из них соберут
/// конфиг, а конфиг — раньше, чем сессия уедет в нативную часть. Перестановка
/// не падает с исключением, она даёт сессию с пустым паролем или со вчерашним
/// конфигом, и видно это только на живом подключении.
///
/// Тест намеренно проверяет не весь список вызовов, а тот его порядок, который
/// одинаков на всех платформах: ветки про права VPN и подбор портов разные у
/// Android, Windows и Linux, и прибивать их гвоздями здесь значило бы красить
/// тест в цвет машины, на которой он запущен.
class _RecordingBackend extends FakeTunnelBackend {
  final List<String> calls = [];
  TunnelSessionRequest? session;

  /// Состояние, которое движок отдаёт на запрос. `connecting` в начале означало
  /// бы «сессия уже поднимается» и увело бы connect() в другую ветку.
  VpnState current = VpnState.disconnected;

  @override
  Future<VpnState> getCurrentState() async {
    calls.add('getCurrentState');
    return current;
  }

  @override
  Future<bool> requestTunnelPermission() async {
    calls.add('requestTunnelPermission');
    return true;
  }

  @override
  Future<({String username, String password})> fetchSocksCredentials() async {
    calls.add('fetchSocksCredentials');
    return (username: 'user-from-native', password: 'pass-from-native');
  }

  @override
  Future<void> startSession(TunnelSessionRequest request) async {
    calls.add('startSession');
    session = request;
    current = const VpnState(status: VpnStatus.connected);
  }

  @override
  Future<void> stopSession() async {
    calls.add('stopSession');
  }
}

final _server = ServerItem(
  id: 'srv-1',
  type: ServerItemType.manual,
  config: 'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
      '?type=tcp&security=none#test',
);

Future<(ProviderContainer, _RecordingBackend)> _container() async {
  final backend = _RecordingBackend();
  final storage = await buildStorageService();
  await storage.saveServers([_server]);
  await storage.setActiveServerId(_server.id);

  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(backend)),
    ],
  );
  addTearDown(container.dispose);

  // Список серверов и состояние туннеля грузятся асинхронно в build()
  // нотифаеров. Не дождаться их — значит поймать гонку: build() завершится
  // после connect() и перепишет его результат нативным состоянием.
  container.read(serversProvider);
  await container.read(vpnStateProvider.future);
  return (container, backend);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('креды забираются до старта сессии, а сессия — последний шаг', () async {
    final (container, backend) = await _container();

    await container.read(vpnStateProvider.notifier).connect();

    final creds = backend.calls.indexOf('fetchSocksCredentials');
    final start = backend.calls.indexOf('startSession');

    expect(creds, isNonNegative, reason: 'креды у нативной части не спросили');
    expect(start, isNonNegative, reason: 'сессия не стартовала');
    expect(
      creds,
      lessThan(start),
      reason: 'креды обязаны быть известны до сборки сессии: '
          'иначе в конфиг уедет пустой пароль. ${backend.calls}',
    );
    expect(
      backend.calls.where((c) => c == 'startSession').length,
      1,
      reason: 'сессия поднимается ровно один раз за попытку',
    );
  });

  test('состояние движка спрашивают до старта, а не только после', () async {
    final (container, backend) = await _container();

    await container.read(vpnStateProvider.notifier).connect();

    // Первый запрос — отсечка «сессия уже поднята кем-то другим» (плитка,
    // автозапуск). Без него connect() поднимал бы вторую поверх первой.
    expect(backend.calls.first, 'getCurrentState');
    expect(
      backend.calls.indexOf('getCurrentState'),
      lessThan(backend.calls.indexOf('startSession')),
    );
  });

  test('в сессию уезжают креды нативной части и конфиг выбранного сервера',
      () async {
    final (container, backend) = await _container();

    await container.read(vpnStateProvider.notifier).connect();

    final session = backend.session;
    expect(session, isNotNull);
    expect(session!.serverName, _server.displayName);
    // Конфиг собран генератором, а не проброшен ссылкой как есть.
    expect(session.xrayConfig, contains('"outbounds"'));
    expect(session.xrayConfig, contains('198.51.100.10'));
    // Креды из нативной части обязаны попасть в синглтон, из которого их
    // читает генератор инбаундов: именно этот пароль закрывает локальный порт
    // от посторонних на устройстве. Не «где-то в строке конфига» — инбаунд
    // бывает и без авторизации (её снимает sing-box на десктопном TUN), а вот
    // разъехаться креды не имеют права никогда.
    expect(Socks5Credentials().username, 'user-from-native');
    expect(Socks5Credentials().password, 'pass-from-native');
    if (session.xrayConfig.contains('"auth": "password"')) {
      expect(session.xrayConfig, contains('pass-from-native'));
    }
  });

  test('без выбранного сервера сессия не стартует вовсе', () async {
    final backend = _RecordingBackend();
    final storage = await buildStorageService();
    final container = ProviderContainer(
      overrides: [
        storageProvider.overrideWithValue(storage),
        vpnEngineProvider.overrideWithValue(VpnEngine.withBackend(backend)),
      ],
    );
    addTearDown(container.dispose);
    container.read(serversProvider);
    await container.read(vpnStateProvider.future);

    await container.read(vpnStateProvider.notifier).connect();

    // getCurrentState приходит от самого нотифаера при построении — важно, что
    // до сессии дело не дошло.
    expect(backend.calls, isNot(contains('startSession')));
    expect(backend.session, isNull);
    expect(
      container.read(vpnStateProvider).value?.status,
      VpnStatus.error,
      reason: 'молчаливый выход оставил бы кружок крутиться навсегда',
    );
  });
}
