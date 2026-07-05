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

class TrayMenuVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

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

final trayMenuVisibleProvider =
    NotifierProvider<TrayMenuVisibleNotifier, bool>(TrayMenuVisibleNotifier.new);
