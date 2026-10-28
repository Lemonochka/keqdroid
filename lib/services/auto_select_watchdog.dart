abstract final class AutoSelectWatchdog {
  static const listenEvery = Duration(seconds: 1);

  static const failureBurst = 1;

  static const silentSecondsBeforeCheck = 2;

  // на десктопе счётчики из API ядра не видят TCP-подтверждений, с порогом 2 были ложные тревоги
  static const desktopSilentSecondsBeforeCheck = 5;

  static const streakGapSeconds = 5;

  static const judgeTimeoutSeconds = 4;

  static const candidateLimit = 10;

  static const quietAfterCheck = Duration(seconds: 15);

  // без связи замер раз в 20 с поднимал ядро на десяток серверов всю поездку в метро
  static const deadZoneQuietMax = Duration(minutes: 2);

  static const quietAfterSwitch = Duration(seconds: 5);

  // подписку, которую подозреваем, меряем почти целиком: тридцать это три пачки ядра на телефоне
  static const suspectLimit = 30;

  static const controlsPerSubscription = 2;

  static const probeEvery = Duration(seconds: 30);

  static const recheckEvery = Duration(minutes: 5);

  static const recheckLimit = 4;

  static const maxSwitchesPerWindow = 3;
  static const switchWindow = Duration(minutes: 3);

  static bool shouldProbe({
    required bool connected,
    required bool autoSelectOn,
    required bool trafficMoved,
    required bool trafficSent,
  }) =>
      connected && autoSelectOn && trafficSent && !trafficMoved;

  static bool dialFailuresSuggestDeadServer(int newFailures) =>
      newFailures >= failureBurst;

  static bool trafficStalled(int silentSeconds, {bool desktop = false}) =>
      silentSeconds >=
      (desktop ? desktopSilentSecondsBeforeCheck : silentSecondsBeforeCheck);

  static bool switchAllowed(List<DateTime> recent, DateTime now) {
    final inWindow = recent.where((t) => now.difference(t) < switchWindow);
    return inWindow.length < maxSwitchesPerWindow;
  }

  static Duration quietAfterRound({required int deadRounds}) {
    if (deadRounds <= 0) return quietAfterCheck;
    final grown = quietAfterCheck * (1 << (deadRounds - 1).clamp(0, 6));
    return grown > deadZoneQuietMax ? deadZoneQuietMax : grown;
  }
}

// своя подписка молчит, а соседняя в те же секунды отвечает: сеть жива, умерла подписка.
// молчат все разом, значит лифт или метро, и такой раунд не считается
final class SubscriptionOutage {
  const SubscriptionOutage({this.subscriptionId, this.rounds = 0, this.lastAt});

  static const roundsBeforeJump = 2;

  static const forgetAfter = Duration(minutes: 5);

  final String? subscriptionId;

  final int rounds;

  final DateTime? lastAt;

  bool suspects(String subscriptionId) =>
      rounds > 0 && this.subscriptionId == subscriptionId;

  bool get shouldJump => rounds >= roundsBeforeJump;

  SubscriptionOutage afterRound({
    required String subscriptionId,
    required bool ownAnswered,
    required bool othersAnswered,
    required DateTime now,
  }) {
    if (ownAnswered) return const SubscriptionOutage();
    final last = lastAt;
    final fresh = this.subscriptionId != subscriptionId ||
        last == null ||
        now.difference(last) > forgetAfter;
    if (!othersAnswered) return fresh ? const SubscriptionOutage() : this;
    return SubscriptionOutage(
      subscriptionId: subscriptionId,
      rounds: fresh ? 1 : rounds + 1,
      lastAt: now,
    );
  }
}

final class SilenceStreak {
  const SilenceStreak({this.silent = 0, this.idle = 0});

  final int silent;

  final int idle;

  SilenceStreak next({required int sent, required int received}) {
    if (received > 0) return const SilenceStreak();
    if (sent > 0) {
      final fresh = idle > AutoSelectWatchdog.streakGapSeconds;
      return SilenceStreak(silent: fresh ? 1 : silent + 1);
    }
    return SilenceStreak(silent: silent, idle: idle + 1);
  }
}
