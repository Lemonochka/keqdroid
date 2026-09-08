import 'dart:async';

import 'package:keqdroid/tunnel/tunnel_backend.dart';
import 'package:keqdroid/tunnel/tunnel_session_request.dart';
import 'package:keqdroid/tunnel/tunnel_state.dart';

/// Бэкенд-пустышка для виджет-тестов.
///
/// Настоящий бэкенд выбирается по платформе, и на Linux его `dispose()` зовёт
/// `gsettings`: виджет-тест экрана настроек запускал системный процесс и правил
/// прокси рабочего стола у того, кто гонял тесты. На CI это роняло сами тесты
/// («A Timer is still pending even after the widget tree was disposed» —
/// `Process.run` заводит таймер под fake_async), а на машине разработчика
/// молча меняло настройки GNOME. На Windows того же кода в `dispose()` нет,
/// поэтому локально всё было зелёным, а на раннере — нет.
///
/// Экрану движок нужен не сам по себе: через него идут иконки приложений и
/// прочая платформенная мелочь. Для этого хватает пустышки.
class FakeTunnelBackend extends TunnelBackend {
  final _ctrl = StreamController<VpnState>.broadcast();

  @override
  Stream<VpnState> get stateStream => _ctrl.stream;

  @override
  void init() {}

  @override
  void dispose() => unawaited(_ctrl.close());

  @override
  Future<({String username, String password})> fetchSocksCredentials() async =>
      (username: 'u', password: 'p');

  @override
  Future<void> startSession(TunnelSessionRequest request) async {}

  @override
  Future<void> stopSession() async {}

  @override
  Future<bool> requestTunnelPermission() async => true;

  @override
  Future<VpnState> getCurrentState() async => VpnState.disconnected;

  @override
  Future<int?> getPing(String address, int port) async => null;

  @override
  Future<List<Map<String, dynamic>>> getInstalledApps({
    bool includeSystem = false,
  }) async =>
      const [];

  @override
  Future<
      List<({
        String id,
        bool success,
        int? latencyMs,
        String error,
        int? httpStatus,
      })>> xrayUrlTestBatch({
    required List<(String id, String xrayConfig)> items,
    required int socksPort,
    String testUrl = 'https://connectivitycheck.gstatic.com/generate_204',
    int timeoutMs = 15000,
    bool keepAlive = true,
  }) async =>
      [
        for (final item in items)
          (
            id: item.$1,
            success: false,
            latencyMs: null,
            error: 'fake backend',
            httpStatus: null,
          ),
      ];
}
