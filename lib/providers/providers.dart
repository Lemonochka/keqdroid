import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_logger.dart';
import '../core/exceptions.dart';
import '../l10n/app_localizations.dart';
import '../models/app_info.dart';
import '../models/app_settings.dart';
import '../models/ping_test_config.dart';
import '../models/routing_rule.dart';
import '../models/server_item.dart';
import '../models/subscription.dart';
import '../services/geo_asset_service.dart';
import '../services/notification_service.dart';
import '../services/ping_service.dart';
import '../services/storage_service.dart';
import '../services/subscription_service.dart';
import '../services/update_service.dart';
import '../services/tunnel_session_builder.dart';
import '../services/vpn_engine.dart';
import '../platform/vpn_native_bridge.dart';
import '../tunnel/app_routing_mode.dart';
import '../tunnel/vpn_backend.dart';
import '../utils/app_locale.dart';
import '../utils/awg_profile.dart';
import '../utils/config_gen.dart';
import '../utils/custom_xray_config.dart';
import '../utils/error_messages.dart';
import '../utils/geo_asset_index.dart';
import '../utils/local_vpn_proxy.dart';
import '../utils/process_name_utils.dart';
import '../utils/proxy_chain.dart';
import '../utils/routing_rules_fold.dart';
import '../utils/socks5_credentials.dart';
import '../utils/split_tunnel_routing.dart';
import '../utils/subscription_diff.dart';
import '../utils/subscription_url.dart';
import 'ui_state_providers.dart';

export 'ui_state_providers.dart';

// Состояние приложения разложено по темам, но остаётся одной библиотекой:
// импортируют отсюда десятки мест, и приватные хелперы вроде
// _resolveFirstAddress ниже нужны сразу нескольким частям.
part 'servers_provider.dart';
part 'settings_providers.dart';
part 'subscriptions_provider.dart';
part 'vpn_state_provider.dart';

/// Резолвит первый IP-адрес хоста (таймаут 5с), либо null если не вышло.
/// direct-правило роутинга и URL/speed-пинг хотят идти по IP, а не по домену,
/// когда DNS сам уходит через прокси.
Future<String?> _resolveFirstAddress(String host) async {
  try {
    final addresses =
        await InternetAddress.lookup(host).timeout(const Duration(seconds: 5));
    if (addresses.isNotEmpty) return addresses.first.address;
  } catch (_) {}
  return null;
}

final storageProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Override storageProvider before runApp');
});

/// Режим сортировки серверов внутри группы (ключ = id подписки / '__manual__',
/// значение = ServerSortMode.name). Персистится, чтобы выбор переживал
/// перезапуск приложения (в отличие от сворачивания групп).
class ServerSortModesNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() =>
      ref.read(storageProvider).getServerSortModes();

  void update(Map<String, String> Function(Map<String, String> state) fn) {
    state = fn(state);
    unawaited(ref.read(storageProvider).setServerSortModes(state));
  }
}

final serverSortModesProvider =
    NotifierProvider<ServerSortModesNotifier, Map<String, String>>(
  ServerSortModesNotifier.new,
);

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService(ref.read(storageProvider));
});

final vpnEngineProvider = Provider<VpnEngine>((ref) {
  final engine = VpnEngine();
  engine.init();
  // Окно скрыто/свёрнуто (десктоп неделями живёт в трее) — секундный опрос
  // счётчиков трафика никому не виден, глушим его, чтобы не жечь CPU в фоне.
  // Два входа: (1) Flutter-lifecycle (`hidden`/`paused` — реальное сворачивание/
  // фон), (2) нативный трей на Windows через desktopWindowVisibleProvider — трей
  // SW_HIDE движок отдаёт лишь как `inactive`, поэтому lifecycle его не ловит.
  // Опрашиваем, только когда окно и на переднем плане, и реально видимо.
  // `inactive` на десктопе = окно видимо, но без фокуса — опрос продолжается.
  // Статус-события (ошибка, disconnect от вотчдога) идут независимо от этого.
  var lifecycleForeground = true;
  var uiVisible = true;
  void applyPolling() =>
      engine.setTrafficStatsPollingEnabled(lifecycleForeground && uiVisible);
  final lifecycle = AppLifecycleListener(
    onStateChange: (state) {
      final hidden = state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached;
      lifecycleForeground = !hidden;
      applyPolling();
    },
  );
  ref.listen<bool>(desktopUiVisibleProvider, (_, next) {
    uiVisible = next;
    applyPolling();
  });
  ref.onDispose(lifecycle.dispose);
  ref.onDispose(engine.dispose);
  return engine;
});

/// Интервал самопроверки обновлений на живом процессе: десктоп неделями висит
/// в трее без перезапуска, и без перепроверки новый релиз виден только вручную.
const _updateRecheckInterval = Duration(hours: 6);

// Подписка ТОЛЬКО на факт «подключён ли VPN» через select, не на весь VpnState:
// телеметрия эмитит состояние каждую секунду, и watch целиком ре-ранил бы
// провайдер на каждый эмит — checkForUpdate выжирал бы анонимный лимит GitHub
// (60 запросов/час). Дополнительно от спама сетью защищает in-memory троттлинг
// в UpdateService (не чаще раза в 30 минут).
/// Системный акцент (Material You) как запасной сид «динамических цветов», когда
/// плагин dynamic_color молчит на не-Pixel устройствах. `null` — цвета из плагина
/// доступны, платформа не Android, или Android < 12. Читается один раз при старте.
final systemAccentColorProvider = FutureProvider<Color?>((ref) async {
  final argb = await VpnNativeBridge.getSystemAccentColor();
  return argb == null ? null : Color(argb);
});

/// Коды, которые реально лежат в поставляемых geoip.dat/geosite.dat.
///
/// Нужен экрану роутинга: правило с кодом, которого нет в базе, ядро не
/// игнорирует — оно роняет весь конфиг, поэтому такие токены выкидываются перед
/// стартом. Раньше молча, теперь их видно в UI. Индекс кэширован в
/// [GeoAssetService] на процесс, так что провайдер дешёвый.
final geoAssetIndexProvider = FutureProvider<GeoAssetIndex>((ref) async {
  return GeoAssetService.index();
});

final updateInfoProvider = FutureProvider<UpdateInfo?>((ref) async {
  // периодический ре-чек; таймер перевзводится на каждый ре-ран провайдера
  final timer = Timer(_updateRecheckInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);

  // после заморозки процесса (Android в фоне) таймеры не тикают — на resume
  // проверяем давность последнего чека
  final lifecycle = AppLifecycleListener(
    onResume: () {
      final last = UpdateService.lastAutoCheckAt;
      if (last == null ||
          DateTime.now().difference(last) >= _updateRecheckInterval) {
        ref.invalidateSelf();
      }
    },
  );
  ref.onDispose(lifecycle.dispose);

  final vpnConnected = ref.watch(
    vpnStateProvider.select((s) => s.value?.status == VpnStatus.connected),
  );
  // Android+AWG — единственный случай без локального HTTP-прокси (Dio тогда
  // идёт напрямую, но пакет приложения включён в TUN и трафик всё равно в
  // туннеле). select — чтобы ре-ран был только при смене awg↔xray.
  final awgActive = ref.watch(
    serversProvider.select((s) {
      final srv = s.activeServer;
      return srv != null && AwgProfile.isAwgConfig(srv.config);
    }),
  );
  final settings = await ref.read(storageProvider).getSettings();
  return UpdateService.checkForUpdate(
    force: false,
    viaLocalProxy: tunnelHasLocalHttpProxy(
      vpnConnected: vpnConnected,
      awgBackend: awgActive,
    ),
    httpPort: settings.httpPort,
  );
});

