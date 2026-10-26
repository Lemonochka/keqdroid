import 'dart:convert';

import '../core/app_logger.dart';
import '../models/app_settings.dart';
import '../models/routing_profile.dart';
import '../models/server_item.dart';
import '../models/subscription.dart';
import '../models/traffic_route.dart';
import '../utils/traffic_routes.dart';
import 'card_image_service.dart';
import 'storage_service.dart';

enum BackupSection {
  splitTunneling,
  subscriptions,
  servers,

  appSettings,
}

class KeqdisBackup {
  final int version;
  final DateTime exportedAt;
  final Map<String, dynamic> data;

  const KeqdisBackup({
    required this.version,
    required this.exportedAt,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
        'format': 'keqdis_backup',
        'version': version,
        'exportedAt': exportedAt.toIso8601String(),
        'data': data,
      };

  String toJsonString({bool pretty = true}) {
    final obj = toJson();
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(obj)
        : jsonEncode(obj);
  }

  // после первого объекта бывает хвост старого файла: экспорт на Android раньше не обрезал файл.
  // режем до декодирования UTF-8, граница хвоста бывает посреди буквы
  static KeqdisBackup parse(List<int> bytes) {
    Object? parsed;
    try {
      parsed = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (error, stackTrace) {
      final end = _leadingObjectEnd(bytes);
      if (end == null) rethrow;
      try {
        parsed = jsonDecode(utf8.decode(bytes.sublist(0, end)));
      } on FormatException {
        Error.throwWithStackTrace(error, stackTrace);
      }
      AppLogger.instance.warn(
        'Backup file has ${bytes.length - end} bytes after the JSON object; '
        'ignored as a leftover of an overwritten file',
      );
    }
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('Invalid JSON file');
    }
    return fromJson(parsed);
  }

  static const _quote = 0x22, _backslash = 0x5C, _braceOpen = 0x7B;
  static const _openers = {_braceOpen, 0x5B}, _closers = {0x7D, 0x5D};
  static const _whitespace = {0x20, 0x09, 0x0A, 0x0D};

  static int? _leadingObjectEnd(List<int> bytes) {
    var i = 0;
    while (i < bytes.length && _whitespace.contains(bytes[i])) {
      i++;
    }
    if (i == bytes.length || bytes[i] != _braceOpen) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (; i < bytes.length; i++) {
      final b = bytes[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (b == _backslash) {
          escaped = true;
        } else if (b == _quote) {
          inString = false;
        }
      } else if (b == _quote) {
        inString = true;
      } else if (_openers.contains(b)) {
        depth++;
      } else if (_closers.contains(b)) {
        depth--;
        if (depth == 0) return i + 1;
      }
    }
    return null;
  }

  static KeqdisBackup fromJson(Map<String, dynamic> json) {
    final format = json['format'];
    if (format != 'keqdis_backup') {
      throw FormatException('Not a Keqdis backup file');
    }
    final version = (json['version'] as num?)?.toInt() ?? 0;
    if (version <= 0) {
      throw FormatException('Unsupported backup version: $version');
    }
    final exportedAt = DateTime.tryParse(json['exportedAt'] as String? ?? '');
    final data = json['data'];
    if (exportedAt == null || data is! Map<String, dynamic>) {
      throw FormatException('Invalid backup payload');
    }
    return KeqdisBackup(version: version, exportedAt: exportedAt, data: data);
  }
}

class SettingsBackupService {
  static const int currentVersion = 1;

  // белый список: остальное описывает машину и её сеть. тест требует разложить каждый ключ toJson()
  static const portableSettingKeys = <String>{
    'directRules',
    'proxyRules',
    'blockedRules',
    'finalOutbound',
    'ignoreProviderRules',
    'xrayCore',
    'vpnCore',
    'fakeIp',
    'autoConnectLastServer',
    'shareDeviceHwid',
    'notifySubscriptionUpdates',
    'pingType',
    'pingTestTarget',
    'pingTestUrlCustom',
    'pingKeepAlive',
    'autoPing',
    'darkTheme',
    'followSystemTheme',
    'themePresetId',
    'customThemeSeed',
    'customThemeVariant',
    'iconShapeId',
    'fontId',
    'amoledBlack',
    'seasonalDecor',
    'serversTwoColumns',
    'serversColumns',
    'modernConnectPanel',
    'serverIconThemeColors',
    'uiScale',
    'hapticFeedback',
    'showTrafficStats',
    'showConnectionTime',
    'showTrafficSplit',
    'waveLatencyColor',
    'showSpeedInNotification',
    'showUptimeInNotification',
    'appLanguageCode',
  };

  static Future<KeqdisBackup> buildBackup(
    StorageService storage, {
    required Set<BackupSection> sections,
  }) async {
    final data = <String, dynamic>{};

    if (sections.contains(BackupSection.splitTunneling)) {
      data['splitTunneling'] = {
        'excludePackages': storage.getExcludePackages(),
        'includePackages': storage.getIncludePackages(),
      };
    }

    if (sections.contains(BackupSection.subscriptions)) {
      final subs = await storage.getSubscriptions();
      data['subscriptions'] = subs.map((s) => s.toJson()).toList();
      final images = await CardImageService.exportForThemes(
        subs.map((s) => s.cardThemeId),
      );
      if (images.isNotEmpty) data['cardImages'] = images;
    }

    if (sections.contains(BackupSection.servers)) {
      final servers = await storage.getServers();
      data['servers'] = {
        'activeServerId': storage.getActiveServerId(),
        'items': servers.map((s) => s.toJson()).toList(),
      };
    }

    if (sections.contains(BackupSection.appSettings)) {
      final json = (await storage.getSettings()).toJson();
      data['appSettings'] = {
        for (final key in portableSettingKeys)
          if (json.containsKey(key)) key: json[key],
      };
      data['routes'] = [for (final r in await storage.getRoutes()) r.toJson()];
      data['routingProfiles'] = [
        for (final p in await storage.getRoutingProfiles()) p.toJson(),
      ];
    }

    return KeqdisBackup(
      version: currentVersion,
      exportedAt: DateTime.now(),
      data: data,
    );
  }

  static Set<BackupSection> detectSections(KeqdisBackup backup) {
    final s = <BackupSection>{};
    if (backup.data['splitTunneling'] is Map) s.add(BackupSection.splitTunneling);
    if (backup.data['subscriptions'] is List) s.add(BackupSection.subscriptions);
    if (backup.data['servers'] is Map) s.add(BackupSection.servers);
    if (backup.data['appSettings'] is Map) s.add(BackupSection.appSettings);
    return s;
  }

  static Future<void> applyBackup(
    StorageService storage, {
    required KeqdisBackup backup,
    required Set<BackupSection> sections,
  }) async {
    if (sections.contains(BackupSection.splitTunneling)) {
      final raw = backup.data['splitTunneling'];
      if (raw is! Map) throw FormatException('Invalid splitTunneling section');
      final exclude = (raw['excludePackages'] as List?)?.whereType<String>().toList() ?? <String>[];
      final include = (raw['includePackages'] as List?)?.whereType<String>().toList() ?? <String>[];
      await storage.setExcludePackages(exclude);
      await storage.setIncludePackages(include);
    }

    if (sections.contains(BackupSection.subscriptions)) {
      final raw = backup.data['subscriptions'];
      if (raw is! List) throw FormatException('Invalid subscriptions section');
      final subs = raw
          .whereType<Map>()
          .map((e) => Subscription.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      // картинки раньше подписок, иначе первый кадр нарисует карточку без файла
      final images = backup.data['cardImages'];
      if (images is Map) {
        await CardImageService.importAll({
          for (final e in images.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
        });
      }
      await storage.saveSubscriptions(subs);
    }

    if (sections.contains(BackupSection.servers)) {
      final raw = backup.data['servers'];
      if (raw is! Map) throw FormatException('Invalid servers section');
      final items = raw['items'];
      if (items is! List) throw FormatException('Invalid servers.items section');

      final servers = items
          .whereType<Map>()
          .map((e) => ServerItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      await storage.saveServers(servers);

      final activeId = raw['activeServerId'] as String?;
      if (activeId != null && servers.any((s) => s.id == activeId)) {
        await storage.setActiveServerId(activeId);
      } else if (activeId == null) {
        await storage.setActiveServerId(null);
      }
    }

    if (sections.contains(BackupSection.appSettings)) {
      final raw = backup.data['appSettings'];
      if (raw is! Map) throw FormatException('Invalid appSettings section');
      // поверх нынешних: порты, LAN, TUN и режим остаются от этой машины
      final merged = (await storage.getSettings()).toJson();
      for (final key in portableSettingKeys) {
        if (raw.containsKey(key)) merged[key] = raw[key];
      }
      // до 26.09.2026 fake-ip лежал под именем mihomoFakeIp
      if (!raw.containsKey('fakeIp') && raw.containsKey('mihomoFakeIp')) {
        merged['fakeIp'] = raw['mihomoFakeIp'];
      }
      await storage.saveSettings(AppSettings.fromJson(merged));
      await _applyRoutes(storage, backup.data['routes'], raw);
      // копии до профилей их не несут, и заведённые на этой машине остаются
      final profiles = backup.data['routingProfiles'];
      if (profiles is List) {
        await storage.saveRoutingProfiles([
          for (final p in profiles)
            if (p is Map) RoutingProfile.fromJson(p.cast<String, dynamic>()),
        ]);
      }
    }
  }

  // копии до маршрутов несут три списка и заменяют только общие маршруты:
  // маршрутов отдельных приложений и на другие серверы там быть не могло, и стирать их незачем
  static Future<void> _applyRoutes(
    StorageService storage,
    Object? rawRoutes,
    Map<dynamic, dynamic> appSettings,
  ) async {
    if (rawRoutes is List) {
      await storage.saveRoutes([
        for (final r in rawRoutes)
          if (r is Map) TrafficRoute.fromJson(r.cast<String, dynamic>()),
      ]);
      return;
    }
    const legacyKeys = ['directRules', 'proxyRules', 'blockedRules'];
    if (!legacyKeys.any(appSettings.containsKey)) return;
    String field(String key) => appSettings[key]?.toString() ?? '';
    final converted = routesFromLegacy(
      AppSettings(
        directRules: field('directRules'),
        proxyRules: field('proxyRules'),
        blockedRules: field('blockedRules'),
      ),
      const [],
    );
    final kept = [
      for (final r in await storage.getRoutes())
        if (!r.allApps || r.target == RouteTarget.server) r,
    ];
    await storage.saveRoutes([...converted, ...kept]);
  }
}
