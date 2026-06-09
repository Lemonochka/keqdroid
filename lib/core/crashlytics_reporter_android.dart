import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'crashlytics_reporter.dart';

class FirebaseCrashlyticsReporter implements CrashlyticsReporter {
  const FirebaseCrashlyticsReporter();

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    String reason = 'Unhandled error',
    bool fatal = false,
  }) {
    return FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: fatal,
    );
  }
}
