import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lightweight [Notifier] helpers replacing legacy [StateProvider].

abstract class StringSetNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void update(Set<String> Function(Set<String> state) fn) => state = fn(state);
}

abstract class StringBoolMapNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => {};

  void update(Map<String, bool> Function(Map<String, bool> state) fn) =>
      state = fn(state);
}

abstract class StringStringMapNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => {};

  void update(Map<String, String> Function(Map<String, String> state) fn) =>
      state = fn(state);
}

class SubscriptionRefreshingIdsNotifier extends StringSetNotifier {}

class PingingScopesNotifier extends StringSetNotifier {}

class PingingServerIdsNotifier extends StringSetNotifier {}

class SubscriptionRefreshErrorsNotifier extends StringStringMapNotifier {}

class CollapsedServerGroupsNotifier extends StringBoolMapNotifier {}

class CollapsedSubscriptionCardsNotifier extends StringBoolMapNotifier {}

class SubscriptionReorderInProgressNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

class HomeTabIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int value) => state = value;
}

class HomeTabPageNotifier extends Notifier<double> {
  @override
  double build() => 0.0;

  void set(double value) => state = value;
}

class VpnServerSwitchInProgressNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// desktop: правда ли окно на экране. На Windows его выставляет нативный трей
/// (onWindowVisibility) при скрытии/восстановлении окна — Flutter-lifecycle на
/// SW_HIDE отдаёт лишь `inactive`, поэтому это отдельный авторитетный сигнал,
/// глушащий волну-анимацию и опрос трафика в фоне. По умолчанию true (и на
/// платформах без трея так и остаётся).
class DesktopWindowVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}

final subscriptionRefreshingIdsProvider =
    NotifierProvider<SubscriptionRefreshingIdsNotifier, Set<String>>(
  SubscriptionRefreshingIdsNotifier.new,
);

final subscriptionRefreshErrorsProvider =
    NotifierProvider<SubscriptionRefreshErrorsNotifier, Map<String, String>>(
  SubscriptionRefreshErrorsNotifier.new,
);

final pingingScopesProvider =
    NotifierProvider<PingingScopesNotifier, Set<String>>(
  PingingScopesNotifier.new,
);

final pingingServerIdsProvider =
    NotifierProvider<PingingServerIdsNotifier, Set<String>>(
  PingingServerIdsNotifier.new,
);

final collapsedServerGroupsProvider =
    NotifierProvider<CollapsedServerGroupsNotifier, Map<String, bool>>(
  CollapsedServerGroupsNotifier.new,
);

final collapsedSubscriptionCardsProvider =
    NotifierProvider<CollapsedSubscriptionCardsNotifier, Map<String, bool>>(
  CollapsedSubscriptionCardsNotifier.new,
);

final subscriptionReorderInProgressProvider =
    NotifierProvider<SubscriptionReorderInProgressNotifier, bool>(
  SubscriptionReorderInProgressNotifier.new,
);

final homeTabIndexProvider =
    NotifierProvider<HomeTabIndexNotifier, int>(HomeTabIndexNotifier.new);

final homeTabPageProvider =
    NotifierProvider<HomeTabPageNotifier, double>(HomeTabPageNotifier.new);

final vpnServerSwitchInProgressProvider =
    NotifierProvider<VpnServerSwitchInProgressNotifier, bool>(
  VpnServerSwitchInProgressNotifier.new,
);

final desktopWindowVisibleProvider =
    NotifierProvider<DesktopWindowVisibleNotifier, bool>(
  DesktopWindowVisibleNotifier.new,
);

/// Видно ли пользователю UI на десктопе. Ложь, когда окно скрыто в трее —
/// тогда глобальный TickerMode (app.dart) глушит все анимации (волна,
/// kawaii-оверлей), а vpnEngine — секундный опрос трафика, чтобы не жечь CPU
/// в фоне.
///
/// Раньше сюда входило и «открыт попап меню трея»: меню рисовал Flutter в том
/// же окне, и на время показа окно считалось видимым. Меню стало нативным — его
/// рисует Windows, наше окно при этом остаётся скрытым, и глушить его анимации
/// правильно.
final desktopUiVisibleProvider = Provider<bool>((ref) {
  return ref.watch(desktopWindowVisibleProvider);
});
