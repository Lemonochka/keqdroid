import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/server_item.dart';
import '../models/subscription.dart';
import 'storage_service.dart';

enum BackupSection {
  splitTunneling,
  subscriptions,
  servers,
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
    }

    if (sections.contains(BackupSection.servers)) {
      final servers = await storage.getServers();
      data['servers'] = {
        'activeServerId': storage.getActiveServerId(),
        'items': servers.map((s) => s.toJson()).toList(),
      };
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
      // Only set active server if it exists after import.
      if (activeId != null && servers.any((s) => s.id == activeId)) {
        await storage.setActiveServerId(activeId);
      } else if (activeId == null) {
        await storage.setActiveServerId(null);
      }
    }
  }
}