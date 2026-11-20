import 'dart:io';

import 'package:flutter/services.dart';

abstract final class AppHaptics {
  static bool enabled = true;

  static final bool platformSupports = Platform.isAndroid || Platform.isIOS;

  static void selection() {
    if (shouldFireHaptics(
      enabled: enabled,
      platformSupports: platformSupports,
    )) {
      HapticFeedback.selectionClick();
    }
  }

  static void impact() {
    if (shouldFireHaptics(
      enabled: enabled,
      platformSupports: platformSupports,
    )) {
      HapticFeedback.mediumImpact();
    }
  }
}

bool shouldFireHaptics({
  required bool enabled,
  required bool platformSupports,
}) => enabled && platformSupports;
