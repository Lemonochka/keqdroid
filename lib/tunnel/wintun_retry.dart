import '../core/exceptions.dart';
import 'tun_failure_hints.dart';

// WaitForInterface в api/adapter.c wintun 0.14.1. ядро, убитое посреди ожидания, оставляет
// адаптер с ошибкой, и следующий запуск тратит на него ещё столько же
const kWintunWaitMs = 15000;

// текст ошибки говорит три раза подряд, столько же пробует сам mihomo (listener/sing_tun/server_windows.go)
const kWintunAttempts = 3;

const kWintunRetryPause = Duration(seconds: 5);

// признак отказа в хвосте вывода, поэтому его дочитывают с таймаутом. timeout проверяет onTimeout по
// настоящему типу future, и на голом Future.wait (List<void>) пустой onTimeout падал TypeError мимо повтора
Future<void> coreOutputDone(List<Future<void>> pipes) =>
    Future.wait(pipes).then<void>((_) {});

// отказ Windows проходит со следующей попытки: 27.10.2026 TUN так и поднимали руками, переключая ядро
Future<void> retryWhileWintunRefused({
  required Future<void> Function(int attempt) attempt,
  required String Function() coreOutput,
  required Future<void> Function() resetAttempt,
  required bool Function() cancelled,
  void Function(int failedAttempt)? onRetry,
  Duration pause = kWintunRetryPause,
}) async {
  for (var n = 1; ; n++) {
    try {
      return await attempt(n);
    } on VpnStartException {
      if (n >= kWintunAttempts ||
          cancelled() ||
          !isWintunAdapterRefused(coreOutput())) {
        rethrow;
      }
      onRetry?.call(n);
      await resetAttempt();
      await Future<void>.delayed(pause);
      if (cancelled()) rethrow;
    }
  }
}
