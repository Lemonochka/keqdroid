import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/routing_profile.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/services/settings_backup_service.dart';

import '../helpers/test_storage.dart';

/// Маршруты в резервной копии. Прежние копии несли только три списка
/// («Свои правила» в них не попадали вовсе), и на новой версии они обязаны
/// восстанавливаться так же, как переносятся при обновлении.
const _app = TrafficRoute(
  id: 'app',
  apps: ['chrome.exe'],
  content: RouteContent.allTraffic,
  target: RouteTarget.direct,
);
const _server = TrafficRoute(
  id: 'srv',
  sites: 'youtube.com',
  target: RouteTarget.server,
  serverId: 'de',
);
const _general = TrafficRoute(
  id: 'gen',
  sites: 'old.example',
  target: RouteTarget.block,
);

void main() {
  test('новая копия переносит маршруты целиком', () async {
    final from = await buildStorageService();
    await from.saveRoutes(const [_app, _server, _general]);
    final built = await SettingsBackupService.buildBackup(
      from,
      sections: {BackupSection.appSettings},
    );
    final backup = KeqdroidBackup.fromJson(
      jsonDecode(built.toJsonString()) as Map<String, dynamic>,
    );

    final to = await buildStorageService();
    await to.saveRoutes(const []);
    await SettingsBackupService.applyBackup(
      to,
      backup: backup,
      sections: {BackupSection.appSettings},
    );
    expect(await to.getRoutes(), const [_app, _server, _general]);
  });

  test('профили маршрутизации уезжают в копию и возвращаются из неё',
      () async {
    const profile = RoutingProfile(
      id: 'games',
      name: 'Игры',
      subscriptionIds: ['sub-a'],
      finalOutbound: AppSettings.finalOutboundDirect,
      routes: [_app],
    );
    final from = await buildStorageService();
    await from.saveRoutingProfiles(const [profile]);
    final built = await SettingsBackupService.buildBackup(
      from,
      sections: {BackupSection.appSettings},
    );
    final backup = KeqdroidBackup.fromJson(
      jsonDecode(built.toJsonString()) as Map<String, dynamic>,
    );

    final to = await buildStorageService();
    await SettingsBackupService.applyBackup(
      to,
      backup: backup,
      sections: {BackupSection.appSettings},
    );
    expect(
      [for (final p in await to.getRoutingProfiles()) p.toJson()],
      [profile.toJson()],
    );
  });

  test('копия до профилей не трогает заведённые на этой машине', () async {
    final to = await buildStorageService();
    await to.saveRoutingProfiles(const [RoutingProfile(id: 'p', name: 'P')]);
    await SettingsBackupService.applyBackup(
      to,
      backup: KeqdroidBackup(
        version: 1,
        exportedAt: DateTime(2026, 10),
        data: {
          'appSettings': <String, dynamic>{},
          'routes': [_app.toJson()],
        },
      ),
      sections: {BackupSection.appSettings},
    );
    expect([for (final p in await to.getRoutingProfiles()) p.id], ['p']);
  });

  test('копия до маршрутов: списки становятся маршрутами, свои остаются',
      () async {
    final backup = KeqdroidBackup(
      version: 1,
      exportedAt: DateTime(2026, 9),
      data: {
        'appSettings': {
          'directRules': 'vk.com',
          'proxyRules': 'discord.com',
          'blockedRules': '',
          'finalOutbound': AppSettings.finalOutboundProxy,
        },
      },
    );
    final to = await buildStorageService();
    await to.saveRoutes(const [_app, _server, _general]);
    await SettingsBackupService.applyBackup(
      to,
      backup: backup,
      sections: {BackupSection.appSettings},
    );

    final routes = await to.getRoutes();
    expect(
      [
        for (final r in routes)
          if (r.allApps && r.target != RouteTarget.server) (r.sites, r.target),
      ],
      [('vk.com', RouteTarget.direct), ('discord.com', RouteTarget.vpn)],
      reason: 'общие маршруты копия заменяет своими списками',
    );
    expect(routes, containsAll(const [_app, _server]),
        reason: 'отдельных приложений и других серверов в старой копии нет');
    expect(routes, isNot(contains(_general)));
  });

  test('копия без списков маршрутов не трогает', () async {
    final backup = KeqdroidBackup(
      version: 1,
      exportedAt: DateTime(2026, 9),
      data: {
        'appSettings': {'themePresetId': 'ocean'},
      },
    );
    final to = await buildStorageService();
    await to.saveRoutes(const [_general]);
    await SettingsBackupService.applyBackup(
      to,
      backup: backup,
      sections: {BackupSection.appSettings},
    );
    expect(await to.getRoutes(), const [_general]);
  });
}
