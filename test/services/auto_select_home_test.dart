import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/auto_select_home.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Свой» сервер автовыбора: с какого увёз аварийный переезд и когда на него
/// возвращаться.
void main() {
  test('переезд запоминает сервер, с которого увёз', () {
    final home = AutoSelectHome.afterFailover(
      null,
      subscriptionId: 's1',
      fromId: 'a',
      toId: 'b',
    );

    expect(home.homeId, 'a');
    expect(home.pickedId, 'b');
    expect(home.aliveStreak, 0);
  });

  test('цепочка переездов ждёт по-прежнему первый сервер', () {
    final first = AutoSelectHome.afterFailover(
      null,
      subscriptionId: 's1',
      fromId: 'a',
      toId: 'b',
    );
    final second = AutoSelectHome.afterFailover(
      first,
      subscriptionId: 's1',
      fromId: 'b',
      toId: 'c',
    );

    expect(second.homeId, 'a');
    expect(second.pickedId, 'c');
  });

  test('переезд прямо на свой сервер начинает отсчёт заново', () {
    final first = AutoSelectHome.afterFailover(
      null,
      subscriptionId: 's1',
      fromId: 'a',
      toId: 'b',
    );
    // Упал сосед, а судья увёз как раз на свой: теперь «свой» — сосед.
    final back = AutoSelectHome.afterFailover(
      first,
      subscriptionId: 's1',
      fromId: 'b',
      toId: 'a',
    );

    expect(back.homeId, 'b');
    expect(back.pickedId, 'a');
  });

  test('возврат только после двух ответов подряд, провал сбрасывает счёт', () {
    var home = AutoSelectHome.afterFailover(
      null,
      subscriptionId: 's1',
      fromId: 'a',
      toId: 'b',
    );

    home = home.afterCheck(homeAnswered: true);
    expect(home.shouldReturn, isFalse);
    home = home.afterCheck(homeAnswered: false);
    expect(home.aliveStreak, 0);
    home = home.afterCheck(homeAnswered: true);
    home = home.afterCheck(homeAnswered: true);
    expect(home.shouldReturn, isTrue);
  });

  group('переезды внутри соседней подписки', () {
    const away = AutoSelectHome(
      subscriptionId: 'own',
      homeId: 'home',
      pickedId: 'b1',
    );

    test('ждём по-прежнему свой сервер, а не соседний', () {
      final next = AutoSelectHome.afterNeighbourFailover(
        away,
        subscriptionId: 'own',
        fromId: 'b1',
        toId: 'b2',
      );

      expect(next?.homeId, 'home');
      expect(next?.pickedId, 'b2');
    });

    test('уехали прямо на свой — ждать нечего', () {
      expect(
        AutoSelectHome.afterNeighbourFailover(
          away,
          subscriptionId: 'own',
          fromId: 'b1',
          toId: 'home',
        ),
        isNull,
      );
    });

    test('сервер сменил не автовыбор — соседний своим не становится', () {
      expect(
        AutoSelectHome.afterNeighbourFailover(
          away,
          subscriptionId: 'own',
          fromId: 'b9',
          toId: 'b2',
        ),
        isNull,
      );
      expect(
        AutoSelectHome.afterNeighbourFailover(
          null,
          subscriptionId: 'own',
          fromId: 'b1',
          toId: 'b2',
        ),
        isNull,
      );
    });
  });

  group('когда ждать больше нечего', () {
    const home = AutoSelectHome(
      subscriptionId: 's1',
      homeId: 'a',
      pickedId: 'b',
    );

    test('всё на месте — ждём', () {
      expect(
        home.stillWaiting(
          activeId: 'b',
          autoSubscriptionId: 's1',
          homeExists: true,
        ),
        same(home),
      );
    });

    test('сервер сменил не автовыбор', () {
      expect(
        home.stillWaiting(
          activeId: 'z',
          autoSubscriptionId: 's1',
          homeExists: true,
        ),
        isNull,
      );
    });

    test('«Авто» горит в другой подписке или погасло', () {
      expect(
        home.stillWaiting(
          activeId: 'b',
          autoSubscriptionId: 's2',
          homeExists: true,
        ),
        isNull,
      );
      expect(
        home.stillWaiting(
          activeId: 'b',
          autoSubscriptionId: null,
          homeExists: true,
        ),
        isNull,
      );
    });

    test('своего сервера больше нет в подписке', () {
      expect(
        home.stillWaiting(
          activeId: 'b',
          autoSubscriptionId: 's1',
          homeExists: false,
        ),
        isNull,
      );
    });
  });

  test('переживает перезапуск интерфейса', () async {
    SharedPreferences.setMockInitialValues({});
    const home = AutoSelectHome(
      subscriptionId: 's1',
      homeId: 'a',
      pickedId: 'b',
      aliveStreak: 1,
    );

    await AutoSelectHomeStore.save(home);
    final loaded = await AutoSelectHomeStore.load();
    expect(loaded?.homeId, 'a');
    expect(loaded?.pickedId, 'b');
    expect(loaded?.aliveStreak, 1);

    await AutoSelectHomeStore.save(null);
    expect(await AutoSelectHomeStore.load(), isNull);
  });
}
