/// Crashlytics is Android-only; desktop builds use [NoopCrashlyticsReporter].
abstract class CrashlyticsReporter {
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    String reason = 'Unhandled error',
    bool fatal = false,
  });
}

class NoopCrashlyticsReporter implements CrashlyticsReporter {
  const NoopCrashlyticsReporter();

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    String reason = 'Unhandled error',
    bool fatal = false,
  }) async {}
}
