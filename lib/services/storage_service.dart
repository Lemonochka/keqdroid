import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_logger.dart';
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
  static const _kWindowBounds  = 'keqdis_window_bounds';
  static const _kSortModes     = 'keqdis_server_sort_modes';

  final SharedPreferences _prefs;
  StorageService(this._prefs);

  /// Кэш распарсенного AppSettings. getSettings() зовётся на горячих путях
  /// (connect, каждый pingBatch/pingSingle), а fromJsonString делает jsonDecode
  /// на каждый вызов. Кэшируем объект; инвалидируем в saveSettings (наш write)
  /// и reloadFromDisk (write из фонового изолята WorkManager).
  AppSettings? _settingsCache;

  /// Все записи, reload() и read-modify-write циклы выполняются строго по
  /// очереди.
  /// 1) SharedPreferences.reload() подменяет ВЕСЬ Dart-кэш снапшотом
  ///    платформы; если снапшот снят до завершения параллельного set*, кэш
  ///    откатывается к старым значениям (так «воскресали» удалённые пакеты
  ///    split tunneling).
  /// 2) upsert/replace/delete читают список, правят и пишут целиком — два
  ///    параллельных цикла (например, батч обновления подписок) читали одну
  ///    базу и последняя запись затирала изменения первой (lost update).
  ///    Поэтому в _serial оборачивается ВЕСЬ цикл, а не только setString.
  ///
  /// ВАЖНО: _serial не реентерабелен — изнутри _serial-блока зовите только
  /// сырые _write*-хелперы и get*-чтения, не публичные save*-методы.
  Future<void> _opChain = Future.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final run = _opChain.then((_) => op());
    _opChain = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// Decodes a stored JSON array, parsing each element with [parse] and
  /// **skipping** entries that fail instead of discarding the whole list.
  ///
  /// A single corrupt record (interrupted write, schema change across an
  /// upgrade, manual edit) must not wipe every server/subscription/rule the
  /// user has. Total corruption (not a JSON array at all) still throws so the
  /// caller can surface it.
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

  /// сбросить кэш prefs и подтянуть с диска (после workmanager)
  Future<void> reloadFromDisk() => _serial(() async {
        await _prefs.reload();
        _settingsCache = null;
      });

  /// Один экземпляр на изолят: serial-очередь (_opChain) защищает от гонок
  /// только внутри одного экземпляра. Desktop-фон (runDueUpdates) звал init()
  /// повторно и получал отдельную очередь поверх тех же SharedPreferences —
  /// RMW-циклы снова гонялись с основными. Конструктор остаётся публичным
  /// для тестов.
  static StorageService? _instance;

  static Future<StorageService> init() async {
    final existing = _instance;
    if (existing != null) return existing;
    final prefs = await SharedPreferences.getInstance();
    return _instance = StorageService(prefs);
  }

  // серверы

  Future<List<ServerItem>> getServers() async {
    try {
      final raw = _prefs.getString(_kServers);
      if (raw == null) return [];
      return _decodeListResilient(raw, ServerItem.fromJson, 'server');
    } catch (e) {
      throw StorageException('Failed to load servers', cause: e);
    }
  }

  /// Сырая запись серверов — только изнутри _serial-блоков.
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

  /// подменяет серверы подписки одним списком
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

  /// Точечно применяет результаты пинга к АКТУАЛЬНОМУ списку в storage и
  /// возвращает записанный список. Провайдер раньше сохранял свой снапшот
  /// целиком (saveServers) — если параллельно обновилась подписка, её новые
  /// серверы затирались устаревшим списком из памяти.
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
          return item;
        }).toList();
        if (changed) await _writeServers(out);
        return out;
      });

  // подписки

  Future<List<Subscription>> getSubscriptions() async {
    try {
      final raw = _prefs.getString(_kSubscriptions);
      if (raw == null) return [];
      return _decodeListResilient(raw, Subscription.fromJson, 'subscription');
    } catch (e) {
      throw StorageException('Failed to load subscriptions', cause: e);
    }
  }

  /// Сырая запись подписок — только изнутри _serial-блоков.
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

  Future<void> deleteSubscription(String id) => _serial(() async {
        final subs = await getSubscriptions();
        subs.removeWhere((s) => s.id == id);
        await _writeSubscriptions(subs);
        // Каскадно удаляем серверы — в том же serial-блоке, чтобы между
        // двумя записями не вклинился параллельный RMW-цикл.
        final all = await getServers();
        await _writeServers(
          all.where((s) => s.subscriptionId != id).toList(),
        );
      });

  // правила роутинга

  Future<List<RoutingRule>> getRules() async {
    try {
      final raw = _prefs.getString(_kRules);
      if (raw == null) return RoutingRule.defaults;
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

  // активный сервер

  String? getActiveServerId() => _prefs.getString(_kActiveId);

  Future<void> setActiveServerId(String? id) => _serial(() async {
        if (id == null) {
          await _prefs.remove(_kActiveId);
        } else {
          await _prefs.setString(_kActiveId, id);
        }
      });

  // split tunneling

  List<String> getExcludePackages() =>
      _prefs.getStringList(_kExcludePkgs) ?? [];

  Future<void> setExcludePackages(List<String> packages) =>
      _serial(() => _prefs.setStringList(_kExcludePkgs, packages));

  List<String> getIncludePackages() =>
      _prefs.getStringList(_kIncludePkgs) ?? [];

  Future<void> setIncludePackages(List<String> packages) =>
      _serial(() => _prefs.setStringList(_kIncludePkgs, packages));

  // настройки

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

  // socks порт

  int? getSocksPort() => _prefs.containsKey(_kSocksPort)
      ? _prefs.getInt(_kSocksPort)
      : null;

  Future<void> setSocksPort(int port) =>
      _serial(() => _prefs.setInt(_kSocksPort, port));

  // hwid

  /// Сохранённый HWID (идентификатор устройства для подписок).
  String? getHwid() => _prefs.getString(_kHwid);

  Future<void> setHwid(String hwid) =>
      _serial(() => _prefs.setString(_kHwid, hwid));

  // окно (Linux desktop; Windows хранит placement нативно в реестре)

  /// Сохранённые границы окна: JSON `{x, y, w, h, maximized}`.
  String? getWindowBoundsJson() => _prefs.getString(_kWindowBounds);

  Future<void> setWindowBoundsJson(String json) =>
      _serial(() => _prefs.setString(_kWindowBounds, json));

  // сортировка серверов по группам

  /// Режимы сортировки групп серверов (id подписки/'__manual__' → имя режима).
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
}
