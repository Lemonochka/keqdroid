import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/routing_rule.dart';
import 'package:keqdroid/models/traffic_route.dart';

import '../helpers/test_storage.dart';

// Маршруты в хранилище: перенос прежних списков при первом чтении.
void main() {
  test('свежая установка: один маршрут по умолчанию и без подсказки', () async {
    final storage = await buildStorageService();
    final routes = await storage.getRoutes();
    expect(routes.single.sites, 'ru, yandex.ru, vk.com');
    expect(routes.single.target, RouteTarget.direct);
    expect(storage.routesHintPending, isFalse);
  });

  test(
    'обновление: списки и свои правила стали маршрутами, подсказка ждёт',
    () async {
      final storage = await buildStorageService();
      await storage.saveSettings(
        const AppSettings(
          directRules: 'vk.com',
          proxyRules: 'youtube.com',
          blockedRules: '',
        ),
      );
      await storage.saveRules(const [
        RoutingRule(
          id: 'r',
          name: 'n',
          type: RuleType.geosite,
          values: ['google'],
          action: RuleAction.proxy,
        ),
      ]);

      final routes = await storage.getRoutes();
      expect(routes.map((r) => (r.sites, r.target)), [
        ('vk.com', RouteTarget.direct),
        ('youtube.com', RouteTarget.vpn),
        ('geosite:google', RouteTarget.vpn),
      ]);
      expect(storage.routesHintPending, isTrue);

      await storage.dismissRoutesHint();
      expect(storage.routesHintPending, isFalse);
    },
  );

  // Перенос делается один раз. Иначе маршрут, который пользователь удалил,
  // возвращался бы из прежнего поля при каждом запуске.
  test('удалённый маршрут не возвращается из прежних полей', () async {
    final storage = await buildStorageService();
    await storage.saveSettings(const AppSettings(directRules: 'vk.com'));
    expect(await storage.getRoutes(), hasLength(1));

    await storage.saveRoutes(const []);
    expect(await storage.getRoutes(), isEmpty);
  });

  test('два одновременных чтения переносят один раз', () async {
    final storage = await buildStorageService();
    await storage.saveSettings(const AppSettings(directRules: 'vk.com'));
    final both = await Future.wait([storage.getRoutes(), storage.getRoutes()]);
    expect(both[0].single.id, both[1].single.id);
  });
}
