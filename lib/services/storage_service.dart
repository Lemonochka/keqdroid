import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/exceptions.dart';
import '../models/app_settings.dart';
import '../models/routing_rule.dart';
import '../models/server_item.dart';
import '../models/subscription.dart';

class StorageService {
  static const _kServers       = 'keqdis_servers_v2';   // v2 = формат ServerItem
  static const _kSubscriptions = 'keqdis_subscriptions';
  static const _kRules         = 'keqdis_rules';
  static const _kActiveId      = 'keqdis_active_server';
  static const _kExcludePkgs   = 'keqdis_exclude_packages';
  static const _kIncludePkgs   = 'keqdis_include_packages';
  static const _kSettings      = 'keqdis_settings';
  static const _kSocksPort     = 'keqdis_socks_port';
  static const _kHwid          = 'keqdis_hwid';

  final SharedPreferences _prefs;
  StorageService(this._prefs);

  /// сбросить кэш prefs и подтянуть с диска (после workmanager)
  Future<void> reloadFromDisk() async {
    await _prefs.reload();
  }

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // серверы

  Future<List<ServerItem>> getServers() async {
    try {
      final raw = _prefs.getString(_kServers);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ServerItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw StorageException('Failed to load servers', cause: e);
    }
  }

  Future<void> saveServers(List<ServerItem> servers) async {
    try {
      await _prefs.setString(
        _kServers,
        jsonEncode(servers.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      throw StorageException('Failed to save servers', cause: e);
    }
  }

  Future<void> upsertServer(ServerItem server) async {
    final servers = await getServers();
    final idx = servers.indexWhere((s) => s.id == server.id);
    if (idx == -1) {
      servers.add(server);
    } else {
      servers[idx] = server;
    }
    await saveServers(servers);
  }

  Future<void> deleteServer(String id) async {
    final servers = await getServers();
    servers.removeWhere((s) => s.id == id);
    await saveServers(servers);
  }

  /// подменяет серверы подписки одним списком
  Future<void> replaceServersBySubscription(
      String subscriptionId,
      List<ServerItem> newServers,
      ) async {
    final all = await getServers();
    final kept = all.where((s) => s.subscriptionId != subscriptionId).toList();
    await saveServers([...kept, ...newServers]);
  }

  Future<void> deleteServersBySubscription(String subscriptionId) async {
    final all = await getServers();
    await saveServers(all.where((s) => s.subscriptionId != subscriptionId).toList());
  }

  Future<void> updatePing(String serverId, int? pingMs) async {
    await updatePings({serverId: pingMs});
  }

  /// пинг пачкой, один read/write
  Future<void> updatePingResults(
    Map<String, ({int? pingMs, String? lastPingType})> updates,
  ) async {
    if (updates.isEmpty) return;
    final servers = await getServers();
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < servers.length; i++) {
      final update = updates[servers[i].id];
      if (update == null) continue;
      var item = servers[i].copyWith(
        pingMs: update.pingMs,
        lastTestedAt: now,
      );
      if (update.lastPingType != null) {
        item = item.copyWith(lastPingType: update.lastPingType);
      }
      servers[i] = item;
      changed = true;
    }
    if (!changed) return;
    await saveServers(servers);
  }

  /// @deprecated Use [updatePingResults] when ping type is known.
  Future<void> updatePings(Map<String, int?> pings) async {
    await updatePingResults({
      for (final e in pings.entries) e.key: (pingMs: e.value, lastPingType: null),
    });
  }

  // подписки

  Future<List<Subscription>> getSubscriptions() async {
    try {
      final raw = _prefs.getString(_kSubscriptions);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Subscription.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw StorageException('Failed to load subscriptions', cause: e);
    }
  }

  Future<void> saveSubscriptions(List<Subscription> subs) async {
    try {
      await _prefs.setString(
        _kSubscriptions,
        jsonEncode(subs.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      throw StorageException('Failed to save subscriptions', cause: e);
    }
  }

  Future<void> upsertSubscription(Subscription sub) async {
    final subs = await getSubscriptions();
    final idx = subs.indexWhere((s) => s.id == sub.id);
    if (idx == -1) {
      subs.add(sub);
    } else {
      subs[idx] = sub;
    }
    await saveSubscriptions(subs);
  }

  Future<void> deleteSubscription(String id) async {
    final subs = await getSubscriptions();
    subs.removeWhere((s) => s.id == id);
    await saveSubscriptions(subs);
    // Каскадно удаляем серверы
    await deleteServersBySubscription(id);
  }

  // правила роутинга

  Future<List<RoutingRule>> getRules() async {
    try {
      final raw = _prefs.getString(_kRules);
      if (raw == null) return RoutingRule.defaults;
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => RoutingRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw StorageException('Failed to load routing rules', cause: e);
    }
  }

  Future<void> saveRules(List<RoutingRule> rules) async {
    try {
      await _prefs.setString(
        _kRules,
        jsonEncode(rules.map((r) => r.toJson()).toList()),
      );
    } catch (e) {
      throw StorageException('Failed to save routing rules', cause: e);
    }
  }

  // активный сервер

  String? getActiveServerId() => _prefs.getString(_kActiveId);

  Future<void> setActiveServerId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kActiveId);
    } else {
      await _prefs.setString(_kActiveId, id);
    }
  }

  // split tunneling

  List<String> getExcludePackages() =>
      _prefs.getStringList(_kExcludePkgs) ?? [];

  Future<void> setExcludePackages(List<String> packages) =>
      _prefs.setStringList(_kExcludePkgs, packages);

  List<String> getIncludePackages() =>
      _prefs.getStringList(_kIncludePkgs) ?? [];

  Future<void> setIncludePackages(List<String> packages) =>
      _prefs.setStringList(_kIncludePkgs, packages);

  // настройки

  Future<AppSettings> getSettings() async {
    try {
      final raw = _prefs.getString(_kSettings);
      if (raw == null) return const AppSettings();
      return AppSettings.fromJsonString(raw);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    await _prefs.setString(_kSettings, settings.toJsonString());
  }

  // socks порт

  int? getSocksPort() => _prefs.containsKey(_kSocksPort)
      ? _prefs.getInt(_kSocksPort)
      : null;

  Future<void> setSocksPort(int port) =>
      _prefs.setInt(_kSocksPort, port);

  // hwid

  /// Сохранённый HWID (идентификатор устройства для подписок).
  String? getHwid() => _prefs.getString(_kHwid);

  Future<void> setHwid(String hwid) async {
    await _prefs.setString(_kHwid, hwid);
  }
}
