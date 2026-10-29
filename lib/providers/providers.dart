import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/app_logger.dart';
import '../core/exceptions.dart';
import '../l10n/app_localizations.dart';
import '../models/app_info.dart';
import '../models/app_settings.dart';
import '../models/ping_test_config.dart';
import '../models/routing_profile.dart';
import '../models/server_group.dart';
import '../models/tun_settings.dart';
import '../models/server_item.dart';
import '../models/subscription.dart';
import '../models/subscription_card_layout.dart';
import '../models/subscription_card_theme.dart';
import '../models/traffic_route.dart';
import '../models/xray_core_settings.dart';
import '../services/app_icon_cache.dart';
import '../services/auto_select_home.dart';
import '../services/auto_select_watchdog.dart';
import '../services/auto_server_select.dart';
import '../services/card_image_service.dart';
import '../services/core_dial_failures.dart';
import '../services/exit_ip_service.dart';
import '../services/geo_asset_service.dart';
import '../services/notification_service.dart';
import '../services/ping_service.dart';
import '../services/rule_list_service.dart';
import '../services/storage_service.dart';
import '../services/subscription_service.dart';
import '../services/update_service.dart';
import '../services/tunnel_session_builder.dart';
import '../services/vpn_engine.dart';
import '../platform/vpn_native_bridge.dart';
import '../tunnel/app_routing_mode.dart';
import '../tunnel/local_port_plan.dart';
import '../tunnel/vpn_backend.dart';
import '../utils/app_locale.dart';
import '../utils/app_routes.dart';
import '../utils/awg_profile.dart';
import '../utils/awg_uri.dart';
import '../utils/config_gen.dart';
import '../utils/custom_clash_config.dart';
import '../utils/custom_xray_config.dart';
import '../utils/error_messages.dart';
import '../utils/geo_asset_index.dart';
import '../utils/geo_rule_sanitizer.dart';
import '../utils/hysteria_uri.dart';
import '../utils/mieru_uri.dart';
import '../utils/desktop_tun.dart';
import '../utils/host_ipv6.dart';
import '../utils/process_name_utils.dart';
import '../utils/mihomo_api_session.dart';
import '../utils/mihomo_config_gen.dart';
import '../utils/owner_guard.dart';
import '../utils/proxy_chain.dart';
import '../utils/route_servers.dart';
import '../utils/routing_profiles.dart';
import '../utils/traffic_routes.dart';
import '../utils/rule_lists.dart';
import '../utils/singbox_outbounds.dart';
import '../utils/socks5_credentials.dart';
import '../utils/socks_uri.dart';
import '../utils/split_tunnel_routing.dart';
import '../utils/split_tunneling_entries.dart';
import '../utils/ssr_uri.dart';
import '../utils/subscription_diff.dart';
import '../utils/subscription_url.dart';
import '../utils/system_accent.dart';
import '../utils/vpn_core_support.dart';
import 'ui_state_providers.dart';

export 'ui_state_providers.dart';

part 'routes_provider.dart';
part 'rule_lists_provider.dart';
part 'servers_provider.dart';
part 'settings_providers.dart';
part 'subscriptions_provider.dart';
part 'vpn_state_provider.dart';

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

int? _activeLocalHttpProxyPort(Ref ref, StorageService storage) {
  final vpnConnected =
      ref.read(vpnStateProvider).value?.status == VpnStatus.connected;
  if (!vpnConnected) return null;
  // порт сессии: если настроенный был занят, ядро слушает другой
  return ActiveLocalPorts().httpPort ??
      storage.cachedSettings?.httpPort ??
      const AppSettings().httpPort;
}

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  final storage = ref.read(storageProvider);
  // пакет приложения исключён из TUN, без локального прокси обновление идёт мимо VPN
  return SubscriptionService(
    storage,
    localProxyPort: () => _activeLocalHttpProxyPort(ref, storage),
  );
});

// спрашиваем раз на подключение и смену сервера: выход меняется только с ними.
// неответ повторяем: новый изолят на Android видит подключено раньше, чем получит пароль входа, и первый запрос ловил 407.
// ответ держим до смены подключения: шапка пересобирается на каждом возврате, и флаг пропадал бы
final exitIpProvider = FutureProvider.autoDispose<ExitIp?>((ref) async {
  final connected = ref.watch(
    vpnStateProvider.select((a) => a.value?.status == VpnStatus.connected),
  );
  final serverId = ref.watch(
    serversProvider.select((s) => s.activeServer?.id),
  );
  if (!connected || serverId == null) return null;
  for (final pause in _exitIpRetryPauses) {
    if (pause > Duration.zero) await Future<void>.delayed(pause);
    if (!ref.mounted) return null;
    final port = _activeLocalHttpProxyPort(ref, ref.read(storageProvider));
    if (port == null) return null;
    final exit = await ref.read(exitIpLookupProvider)(port);
    if (!ref.mounted) return null;
    if (exit != null) {
      ref.keepAlive();
      return exit;
    }
  }
  return null;
});

// тесты подменяют, чтобы не ходить в сеть
final exitIpLookupProvider = Provider<Future<ExitIp?> Function(int)>(
  (ref) => (port) => ExitIpService.lookup(proxyPort: port),
);

const _exitIpRetryPauses = [
  Duration.zero,
  Duration(seconds: 3),
  Duration(seconds: 10),
];

final vpnEngineProvider = Provider<VpnEngine>((ref) {
  final engine = VpnEngine();
  engine.init();
  // трей на Windows прячет окно, а движок отдаёт это как inactive,
  // поэтому видимость берём ещё и из натива
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

final appIconCacheProvider = Provider<AppIconCache>(
  (ref) => AppIconCache(ref.read(vpnEngineProvider).getAppIcon),
);

const _updateRecheckInterval = Duration(hours: 6);

final systemAccentColorProvider = StreamProvider<Color?>((ref) async* {
  Color? select(SystemAccentCandidates candidates) {
    final picked = pickSystemAccent(candidates);
    AppLogger.instance.debug(
      picked == null
          ? 'System accent unavailable, using brand seed'
          : 'System accent seed: '
              '#${picked.color.toARGB32().toRadixString(16).padLeft(8, '0')}'
              ' from ${picked.source.name}',
    );
    return picked?.color;
  }

  yield select(await VpnNativeBridge.getSystemAccentCandidates());
  await for (final candidates in VpnNativeBridge.systemAccentChanges) {
    yield select(candidates);
  }
});

final geoAssetIndexProvider = FutureProvider<GeoAssetIndex>((ref) async {
  return GeoAssetService.index();
});

final updateInfoProvider = FutureProvider<UpdateInfo?>((ref) async {
  final timer = Timer(_updateRecheckInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);

  // в замороженном процессе таймеры стоят, поэтому проверяем ещё и на resume
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
  final settings = await ref.read(storageProvider).getSettings();
  return UpdateService.checkForUpdate(
    force: false,
    viaLocalProxy: vpnConnected,
    // порт сессии: если настроенный был занят, ядро слушает другой
    httpPort: ActiveLocalPorts().httpPortOr(settings.httpPort),
  );
});

