import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/platform/vpn_native_bridge.dart';
import 'package:keqdroid/services/update_download_notice.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('ru'));
  late List<MethodCall> calls;

  // движок проходит состояния по шагам, а AppLifecycleListener скачок ассертом не пропускает
  const order = [
    AppLifecycleState.resumed,
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  void lifecycle(WidgetTester tester, AppLifecycleState target) {
    var at = order.indexOf(
      tester.binding.lifecycleState ?? AppLifecycleState.resumed,
    );
    final to = order.indexOf(target);
    while (at != to) {
      at += to > at ? 1 : -1;
      tester.binding.handleAppLifecycleStateChanged(order[at]);
    }
  }

  void native(WidgetTester tester) {
    calls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      VpnNativeBridge.channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(VpnNativeBridge.channel, null));
    lifecycle(tester, AppLifecycleState.resumed);
    addTearDown(() => lifecycle(tester, AppLifecycleState.resumed));
  }

  List<String> methods() => [for (final c in calls) c.method];

  testWidgets('на экране установщик открывается сразу, без уведомления «скачано»',
      (tester) async {
    native(tester);
    final notice = UpdateDownloadNotice(l10n, '0.38.0');
    await notice.started();
    notice.progress(0.4);
    await notice.downloaded();

    expect(methods(), [
      'startUpdateDownload',
      'updateDownloadProgress',
      'stopUpdateDownload',
    ]);
    expect(calls.first.arguments, {
      'channel': 'Загрузка обновления',
      'title': 'Скачивается обновление 0.38.0',
    });
    expect(calls[1].arguments, {'percent': 40});
  });

  testWidgets(
      'свёрнутое приложение: установщик ждёт возвращения, в шторке «скачано»',
      (tester) async {
    native(tester);
    final notice = UpdateDownloadNotice(l10n, '0.38.0');
    await notice.started();
    lifecycle(tester, AppLifecycleState.paused);

    var installerAllowed = false;
    final waiting = notice.downloaded().then((_) => installerAllowed = true);
    await tester.pump();

    expect(methods(), [
      'startUpdateDownload',
      'stopUpdateDownload',
      'showUpdateNotice',
    ]);
    expect(calls.last.arguments, {
      'channel': 'Обновления приложения',
      'title': 'Обновление 0.38.0 скачано',
      'text': 'Нажмите, чтобы установить',
    });
    expect(installerAllowed, isFalse);

    lifecycle(tester, AppLifecycleState.resumed);
    await waiting;

    expect(installerAllowed, isTrue);
    expect(methods().last, 'cancelUpdateNotice');
  });

  testWidgets('ошибка в фоне: уведомление сразу, снимается при возвращении',
      (tester) async {
    native(tester);
    final notice = UpdateDownloadNotice(l10n, '0.38.0');
    await notice.started();
    lifecycle(tester, AppLifecycleState.paused);

    await notice.failed();

    expect(methods(), [
      'startUpdateDownload',
      'stopUpdateDownload',
      'showUpdateNotice',
    ]);
    expect(calls.last.arguments, {
      'channel': 'Обновления приложения',
      'title': 'Не удалось скачать обновление',
      'text': 'Нажмите, чтобы попробовать ещё раз',
    });

    lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();
    expect(methods().last, 'cancelUpdateNotice');
  });

  testWidgets('ошибка на экране видна в самом окне, шторку не трогаем',
      (tester) async {
    native(tester);
    final notice = UpdateDownloadNotice(l10n, '0.38.0');
    await notice.started();
    await notice.failed();

    expect(methods(), ['startUpdateDownload', 'stopUpdateDownload']);
  });

  testWidgets('после скачивания ошибка установщика не называется ошибкой загрузки',
      (tester) async {
    native(tester);
    final notice = UpdateDownloadNotice(l10n, '0.38.0');
    await notice.started();
    await notice.downloaded();
    lifecycle(tester, AppLifecycleState.paused);
    await notice.failed();
    notice.progress(0.5);

    expect(methods(), ['startUpdateDownload', 'stopUpdateDownload']);
  });

  testWidgets('процент уходит в шторку не чаще раза в полсекунды и без повторов',
      (tester) async {
    native(tester);
    var now = DateTime(2026, 11, 15, 20, 40);
    final notice = UpdateDownloadNotice(l10n, '0.38.0', now: () => now);

    notice.progress(0.10);
    notice.progress(0.105);
    now = now.add(const Duration(milliseconds: 100));
    notice.progress(0.2);
    now = now.add(const Duration(milliseconds: 500));
    notice.progress(0.3);
    notice.progress(1.7);
    await tester.pump();

    expect(
      [for (final c in calls) (c.arguments as Map)['percent']],
      [10, 30],
    );
  });

  for (final error in [
    PlatformException(code: 'SERVICE_REFUSED'),
    MissingPluginException(),
  ]) {
    testWidgets('отказ нативной стороны (${error.runtimeType}) загрузку не роняет',
        (tester) async {
      native(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        VpnNativeBridge.channel,
        (call) async => throw error,
      );
      final notice = UpdateDownloadNotice(l10n, '0.38.0');
      await notice.started();
      notice.progress(0.5);
      lifecycle(tester, AppLifecycleState.paused);
      await notice.failed();
      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
    });
  }
}
