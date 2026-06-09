import 'dart:io' show Platform;

import 'crashlytics_reporter.dart';
import 'crashlytics_reporter_android.dart';

CrashlyticsReporter createCrashlyticsReporter() {
  if (Platform.isAndroid) {
    return const FirebaseCrashlyticsReporter();
  }
  return const NoopCrashlyticsReporter();
}
