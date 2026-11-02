import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_logger.dart';
import '../core/exceptions.dart';
import '../models/app_settings.dart';
import '../models/ping_sample.dart';
import '../models/routing_profile.dart';
import '../models/routing_rule.dart';
import '../models/server_item.dart';
import '../models/subscription.dart';
import '../models/traffic_route.dart';
import '../utils/traffic_routes.dart';

class StorageService {
  static const _kServers       = 'keqdis_servers_v2';
  static const _kSubscriptions = 'keqdis_subscriptions';
  static const _kRules         = 'keqdis_rules';
  static const _kRoutes        = 'keqdis_routes';
  static const _kRoutesHint    = 'keqdis_routes_hint';
  static const _kRoutingProfiles = 'keqdis_routing_profiles';
  static const _kActiveId      = 'keqdis_active_server';
  static const _kExcludePkgs   = 'keqdis_exclude_packages';
  static const _kIncludePkgs   = 'keqdis_include_packages';
  static const _kSettings      = 'keqdis_settings';
  static const _kSocksPort     = 'keqdis_socks_port';
  static const _kActiveHttpPort = 'keqdis_active_http_port';
  static const _kActiveHttpUser = 'keqdis_active_http_user';
  static const _kActiveHttpPass = 'keqdis_active_http_pass';
  static const _kKeqtrisBest  = 'keqdis_keqtris_best';
  static const _kHwid          = 'keqdis_hwid';
  static const _kWindowBounds  = 'keqdis_window_bounds';
  static const _kSortModes     = 'keqdis_server_sort_modes';
  static const _kExpiryNotified = 'keqdis_subscription_expiry_notified';
  static const _kExpiryReminded = 'keqdis_subscription_expiry_reminded';
  // отдельным ключом: шаблон с правилами бывает в сотни КБ, а список подписок разбирается при каждом чтении
  static const _kClashTemplatePrefix = 'keqdis_clash_template_';

  final SharedPreferences _prefs;
  StorageService(this._prefs);

  AppSettings? _settingsCache;

  // всё по одной очереди: reload() откатывал кэш поверх параллельного set*, а два цикла
  // чтение-правка-запись затирали друг друга. _serial не реентерабелен, внутри только сырые _write* и get*
  Future<void> _opChain = Future.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final run = _opChain.then((_) => op());
    _opChain = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  static List<T> _decodeListResilient<T>(
    String raw,
    T Function(Map<String, dynamic>) parse,
    String label,
  ) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw FormatException('$label store is not a JSON array');
    }
    final out = <T>[];
    for (final e in decoded) {
      try {
        out.add(parse(e as Map<String, dynamic>));
      } catch (err, st) {
        AppLogger.instance.warn(
          'Skipping unreadable $label entry while loading storage',
          error: err,
          stackTrace: st,
        );
      }
    }
    return out;
  }

  Future<void> reloadFromDisk() => _serial(() async {
        await _prefs.reload();
        _settingsCache = null;
      });

  // один экземпляр на изолят: вторая очередь поверх тех же prefs вернула бы гонки
  static StorageService? _instance;

  static Future<StorageService> init() async {
    final existing = _instance;
    if (existing != null) return existing;
    final prefs = await SharedPreferences.getInstance();
    return _instance = StorageService(prefs);
  }

  Future<List<ServerItem>> getServers() async {
    try {
      final raw = _prefs.getString(_kServers);
      if (raw == null) return [];
      return _decodeListResilient(raw, ServerItem.fromJson, 'server');
    } catch (e) {
      throw StorageException('Failed to load servers', cause: e);
    }
  }

  Future<void> _writeServers(List<ServerItem> servers) async {
    try {
      final raw = jsonEncode(servers.map((s) => s.toJson()).toList());
      await _prefs.setString(_kServers, raw);
    } catch (e) {
      throw StorageException('Failed to save servers', cause: e);
    }
  }

  Future<void> saveServers(List<ServerItem> servers) =>
      _serial(() => _writeServers(servers));

  Future<void> upsertServer(ServerItem server) => _serial(() async {
        final servers = await getServers();
        final idx = servers.indexWhere((s) => s.id == server.id);
        if (idx == -1) {
          servers.add(server);
        } else {
          servers[idx] = server;
        }
        await _writeServers(servers);
      });

  Future<void> deleteServer(String id) => _serial(() async {
        final servers = await getServers();
        servers.removeWhere((s) => s.id == id);
        await _writeServers(servers);
      });

  Future<void> replaceServersBySubscription(
    String subscriptionId,
    List<ServerItem> newServers,
  ) =>
      _serial(() async {
        final all = await getServers();
        final kept =
            all.where((s) => s.subscriptionId != subscriptionId).toList();
        await _writeServers([...kept, ...newServers]);
      });

  Future<void> deleteServersBySubscription(String subscriptionId) =>
      _serial(() async {
        final all = await getServers();
        await _writeServers(
          all.where((s) => s.subscriptionId != subscriptionId).toList(),
        );
      });

  Future<List<ServerItem>> applyPingUpdates(
    Map<String, ({int? pingMs, String? lastPingType})> updates,
    DateTime testedAt,
  ) =>
      _serial(() async {
        final servers = await getServers();
        var changed = false;
        final out = servers.map((s) {
          final u = updates[s.id];
          if (u == null) return s;
          changed = true;
          var item = s.copyWith(pingMs: u.pingMs, lastTestedAt: testedAt);
          if (u.lastPingType != null) {
            item = item.copyWith(lastPingType: u.lastPingType);
          }
          final type = item.lastPingType;
          if (type != null && PingSample.latencyTypes.contains(type)) {
            item = item.copyWith(
              pingSamples: PingSample.append(
                item.pingSamples,
                PingSample(at: testedAt, ms: u.pingMs, type: type),
              ),
            );
          }
          return item;
        }).toList();
        if (changed) await _writeServers(out);
        return out;
      });

  Future<List<Subscription>> getSubscriptions() async {
    try {
      final raw = _prefs.getString(_kSubscriptions);
      if (raw == null) return [];
      return _decodeListResilient(raw, Subscription.fromJson, 'subscription');
    } catch (e) {
      throw StorageException('Failed to load subscriptions', cause: e);
    }
  }

  Future<void> _writeSubscriptions(List<Subscription> subs) async {
    try {
      final raw = jsonEncode(subs.map((s) => s.toJson()).toList());
      await _prefs.setString(_kSubscriptions, raw);
    } catch (e) {
      throw StorageException('Failed to save subscriptions', cause: e);
    }
  }

  Future<void> saveSubscriptions(List<Subscription> subs) =>
      _serial(() => _writeSubscriptions(subs));

  Future<void> upsertSubscription(Subscription sub) => _serial(() async {
        final subs = await getSubscriptions();
        final idx = subs.indexWhere((s) => s.id == sub.id);
        if (idx == -1) {
          subs.add(sub);
        } else {
          subs[idx] = sub;
        }
        await _writeSubscriptions(subs);
      });

  String? getClashTemplate(String subscriptionId) =>
      _prefs.getString('$_kClashTemplatePrefix$subscriptionId');

  Future<void> setClashTemplate(String subscriptionId, String? template) =>
      _serial(() async {
        final key = '$_kClashTemplatePrefix$subscriptionId';
        if (template == null) {
          await _prefs.remove(key);
        } else {
          await _prefs.setString(key, template);
        }
      });

  Future<void> deleteSubscription(String id) => _serial(() async {
        final subs = await getSubscriptions();
        subs.removeWhere((s) => s.id == id);
        await _writeSubscriptions(subs);
        await _prefs.remove('$_kClashTemplatePrefix$id');
        final all = await getServers();
        await _writeServers(
          all.where((s) => s.subscriptionId != id).toList(),
        );
      });

  // читает только перенос в маршруты (getRoutes)
  Future<List<RoutingRule>> getRules() async {
    try {
      final raw = _prefs.getString(_kRules);
      if (raw == null) return const [];
      return _decodeListResilient(raw, RoutingRule.fromJson, 'routing rule');
    } catch (e) {
      throw StorageException('Failed to load routing rules', cause: e);
    }
  }

  Future<void> saveRules(List<RoutingRule> rules) async {
    try {
      final raw = jsonEncode(rules.map((r) => r.toJson()).toList());
      await _serial(() => _prefs.setString(_kRules, raw));
    } catch (e) {
      throw StorageException('Failed to save routing rules', cause: e);
    }
  }

  // перенос из трёх списков и своих правил ровно один раз: иначе удалённый маршрут возвращался бы из старого поля
  Future<List<TrafficRoute>> getRoutes() async {
    final raw = _prefs.getString(_kRoutes);
    if (raw != null) return _decodeRoutes(raw);
    return _serial(() async {
      // пока ждали очереди, перенос мог сделать другой вызов
      final again = _prefs.getString(_kRoutes);
      if (again != null) return _decodeRoutes(again);
      final settings = await getSettings();
      final rules = await getRules();
      final routes = routesFromLegacy(settings, rules);
      await _prefs.setString(_kRoutes, _encodeRoutes(routes));
      if (legacyRoutingCustomized(settings, rules)) {
        await _prefs.setBool(_kRoutesHint, true);
      }
      return routes;
    });
  }

  Future<void> saveRoutes(List<TrafficRoute> routes) =>
      _serial(() => _prefs.setString(_kRoutes, _encodeRoutes(routes)));

  Future<List<RoutingProfile>> getRoutingProfiles() async {
    final raw = _prefs.getString(_kRoutingProfiles);
    if (raw == null) return const [];
    try {
      return _decodeListResilient(raw, RoutingProfile.fromJson, 'routing profile');
    } catch (e) {
      throw StorageException('Failed to load routing profiles', cause: e);
    }
  }

  Future<void> saveRoutingProfiles(List<RoutingProfile> profiles) => _serial(
        () => _prefs.setString(
          _kRoutingProfiles,
          jsonEncode([for (final p in profiles) p.toJson()]),
        ),
      );

  bool get routesHintPending => _prefs.getBool(_kRoutesHint) ?? false;

  Future<void> dismissRoutesHint() =>
      _serial(() => _prefs.remove(_kRoutesHint));

  List<TrafficRoute> _decodeRoutes(String raw) {
    try {
      return _decodeListResilient(raw, TrafficRoute.fromJson, 'route');
    } catch (e) {
      throw StorageException('Failed to load routes', cause: e);
    }
  }

  static String _encodeRoutes(List<TrafficRoute> routes) =>
      jsonEncode([for (final r in routes) r.toJson()]);

  String? getActiveServerId() => _prefs.getString(_kActiveId);

  Future<void> setActiveServerId(String? id) => _serial(() async {
        if (id == null) {
          await _prefs.remove(_kActiveId);
        } else {
          await _prefs.setString(_kActiveId, id);
        }
      });

  List<String> getExcludePackages() =>
      _prefs.getStringList(_kExcludePkgs) ?? [];

  Future<void> setExcludePackages(List<String> packages) =>
      _serial(() => _prefs.setStringList(_kExcludePkgs, packages));

  List<String> getIncludePackages() =>
      _prefs.getStringList(_kIncludePkgs) ?? [];

  Future<void> setIncludePackages(List<String> packages) =>
      _serial(() => _prefs.setStringList(_kIncludePkgs, packages));

  AppSettings? get cachedSettings => _settingsCache;

  Future<AppSettings> getSettings() async {
    final cached = _settingsCache;
    if (cached != null) return cached;
    try {
      final raw = _prefs.getString(_kSettings);
      final settings =
          raw == null ? const AppSettings() : AppSettings.fromJsonString(raw);
      _settingsCache = settings;
      return settings;
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) => _serial(() async {
        await _prefs.setString(_kSettings, settings.toJsonString());
        _settingsCache = settings;
      });

  int? getSocksPort() => _prefs.containsKey(_kSocksPort)
      ? _prefs.getInt(_kSocksPort)
      : null;

  Future<void> setSocksPort(int port) =>
      _serial(() => _prefs.setInt(_kSocksPort, port));

  int getKeqtrisBest() => _prefs.getInt(_kKeqtrisBest) ?? 0;

  Future<void> setKeqtrisBest(int score) =>
      _serial(() => _prefs.setInt(_kKeqtrisBest, score));

  int? getActiveLocalHttpPort() => _prefs.getInt(_kActiveHttpPort);

  ({String username, String password}) getActiveLocalHttpCredentials() => (
        username: _prefs.getString(_kActiveHttpUser) ?? '',
        password: _prefs.getString(_kActiveHttpPass) ?? '',
      );

  Future<void> setActiveLocalHttpPort(
    int? port, {
    String username = '',
    String password = '',
  }) =>
      _serial(() async {
        if (port == null) {
          await _prefs.remove(_kActiveHttpPort);
        } else {
          await _prefs.setInt(_kActiveHttpPort, port);
        }
        if (port == null || username.isEmpty || password.isEmpty) {
          await _prefs.remove(_kActiveHttpUser);
          await _prefs.remove(_kActiveHttpPass);
        } else {
          await _prefs.setString(_kActiveHttpUser, username);
          await _prefs.setString(_kActiveHttpPass, password);
        }
      });

  String? getHwid() => _prefs.getString(_kHwid);

  Future<void> setHwid(String hwid) =>
      _serial(() => _prefs.setString(_kHwid, hwid));

  String? getWindowBoundsJson() => _prefs.getString(_kWindowBounds);

  Future<void> setWindowBoundsJson(String json) =>
      _serial(() => _prefs.setString(_kWindowBounds, json));

  Map<String, String> getServerSortModes() {
    final raw = _prefs.getString(_kSortModes);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> setServerSortModes(Map<String, String> modes) =>
      _serial(() => _prefs.setString(_kSortModes, jsonEncode(modes)));

  Map<String, String> getExpiryNotified() => _stringMap(_kExpiryNotified);

  Future<void> setExpiryNotified(Map<String, String> byId) =>
      _serial(() => _prefs.setString(_kExpiryNotified, jsonEncode(byId)));

  Map<String, String> getExpiryReminded() => _stringMap(_kExpiryReminded);

  Future<void> setExpiryReminded(Map<String, String> byId) =>
      _serial(() => _prefs.setString(_kExpiryReminded, jsonEncode(byId)));

  Map<String, String> _stringMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }
}
