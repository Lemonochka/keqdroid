import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AutoSelectHome {
  const AutoSelectHome({
    required this.subscriptionId,
    required this.homeId,
    required this.pickedId,
    this.aliveStreak = 0,
  });

  static const returnAfter = 2;

  final String subscriptionId;

  final String homeId;

  final String pickedId;

  final int aliveStreak;

  bool get shouldReturn => aliveStreak >= returnAfter;

  static AutoSelectHome afterFailover(
    AutoSelectHome? previous, {
    required String subscriptionId,
    required String fromId,
    required String toId,
  }) {
    final keep = previous != null &&
        previous.subscriptionId == subscriptionId &&
        previous.pickedId == fromId &&
        previous.homeId != toId;
    return AutoSelectHome(
      subscriptionId: subscriptionId,
      homeId: keep ? previous.homeId : fromId,
      pickedId: toId,
    );
  }

  // уезжаем с сервера соседней подписки: своим он не становится, ждём по-прежнему сервер своей
  static AutoSelectHome? afterNeighbourFailover(
    AutoSelectHome? previous, {
    required String subscriptionId,
    required String fromId,
    required String toId,
  }) {
    if (previous == null ||
        previous.subscriptionId != subscriptionId ||
        previous.pickedId != fromId ||
        previous.homeId == toId) {
      return null;
    }
    return AutoSelectHome(
      subscriptionId: subscriptionId,
      homeId: previous.homeId,
      pickedId: toId,
    );
  }

  AutoSelectHome? stillWaiting({
    required String activeId,
    required String? autoSubscriptionId,
    required bool homeExists,
  }) {
    if (autoSubscriptionId != subscriptionId) return null;
    if (!homeExists) return null;
    if (activeId != pickedId) return null;
    return this;
  }

  AutoSelectHome afterCheck({required bool homeAnswered}) => AutoSelectHome(
        subscriptionId: subscriptionId,
        homeId: homeId,
        pickedId: pickedId,
        aliveStreak: homeAnswered ? aliveStreak + 1 : 0,
      );

  Map<String, Object> toJson() => {
        'sub': subscriptionId,
        'home': homeId,
        'picked': pickedId,
        'streak': aliveStreak,
      };

  static AutoSelectHome? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final sub = raw['sub'];
    final home = raw['home'];
    final picked = raw['picked'];
    if (sub is! String || home is! String || picked is! String) return null;
    final streak = raw['streak'];
    return AutoSelectHome(
      subscriptionId: sub,
      homeId: home,
      pickedId: picked,
      aliveStreak: streak is int ? streak : 0,
    );
  }
}

// на диске: на Android интерфейс выгружают, а туннель работает дальше
abstract final class AutoSelectHomeStore {
  static const _key = 'auto_select_home';

  static Future<AutoSelectHome?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return AutoSelectHome.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(AutoSelectHome? home) async {
    final prefs = await SharedPreferences.getInstance();
    if (home == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(home.toJson()));
    }
  }
}
