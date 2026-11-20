import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/providers/halloween_provider.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/shared/ui/halloween/halloween_season.dart';

import '../helpers/test_storage.dart';

Future<ProviderContainer> _container({required bool decor}) async {
  final storage = await buildStorageService();
  await storage.saveSettings(
    const AppSettings().copyWith(seasonalDecor: decor),
  );
  final container = ProviderContainer(
    overrides: [storageProvider.overrideWithValue(storage)],
  );
  addTearDown(container.dispose);
  await container.read(settingsNotifierProvider.future);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => HalloweenSeason.now = DateTime.now);

  test('в праздник оформление включено', () async {
    HalloweenSeason.now = () => DateTime(2026, 10, 31, 20);
    final c = await _container(decor: true);
    expect(c.read(halloweenActiveProvider), isTrue);
  });

  test('выключенное переключателем не показывается даже в праздник', () async {
    HalloweenSeason.now = () => DateTime(2026, 10, 31, 20);
    final c = await _container(decor: false);
    expect(c.read(halloweenActiveProvider), isFalse);
  });

  test('вне окна дат его нет, что бы ни стояло в настройках', () async {
    HalloweenSeason.now = () => DateTime(2026, 11, 5);
    final c = await _container(decor: true);
    expect(c.read(halloweenActiveProvider), isFalse);
  });

  test('переключатель действует сразу, без перезапуска', () async {
    HalloweenSeason.now = () => DateTime(2026, 10, 31, 20);
    final c = await _container(decor: true);
    expect(c.read(halloweenActiveProvider), isTrue);
    final settings = c.read(settingsNotifierProvider).value!;
    await c
        .read(settingsNotifierProvider.notifier)
        .save(settings.copyWith(seasonalDecor: false));
    expect(c.read(halloweenActiveProvider), isFalse);
  });
}
