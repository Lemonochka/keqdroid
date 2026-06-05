import 'package:flutter/material.dart';

import '../models/app_settings.dart';

/// подпись языка для настроек.
String appLanguageLabel(AppSettings settings, {required String systemLabel}) {
  return switch (settings.appLanguageCode) {
    'en' => 'English',
    'ru' => 'Русский',
    'de' => 'Deutsch',
    'zh' => '中文',
    _ => systemLabel,
  };
}

Locale? localeFromSettings(AppSettings settings) {
  return switch (settings.appLanguageCode) {
    'en' => const Locale('en'),
    'ru' => const Locale('ru'),
    'de' => const Locale('de'),
    'zh' => const Locale('zh'),
    _ => null,
  };
}
