import 'dart:io';

import 'package:flutter/services.dart';

/// Тактильная отдача.
///
/// У M3 Expressive отклик — часть языка наравне с движением: нажатие должно
/// подтверждаться, а не только рисоваться. Здесь два уровня, больше не нужно:
/// лёгкий щелчок на смену выбора и заметный удар на главное действие.
abstract final class AppHaptics {
  /// Пользовательская настройка. Держим статикой, а не читаем провайдер в
  /// каждой точке вызова: отдача дёргается из мест без `ref` (обработчики
  /// нажатий в обычных виджетах), а значение обновляется в одном месте — из
  /// темы приложения, при каждом изменении настроек.
  static bool enabled = true;

  /// Windows и Linux вибромотора не имеют, вызовы там просто уходят в пустоту.
  static final bool platformSupports = Platform.isAndroid || Platform.isIOS;

  /// Смена выбора: вкладка, сервер, переключатель.
  static void selection() {
    if (shouldFireHaptics(enabled: enabled, platformSupports: platformSupports)) {
      HapticFeedback.selectionClick();
    }
  }

  /// Главное действие: подключение и отключение.
  static void impact() {
    if (shouldFireHaptics(enabled: enabled, platformSupports: platformSupports)) {
      HapticFeedback.mediumImpact();
    }
  }
}

/// Решение «отдавать ли тактильный отклик», вынесено отдельно, чтобы его можно
/// было проверить: сам вызов уходит в платформенный канал, которого в тестах на
/// десктопе нет.
bool shouldFireHaptics({
  required bool enabled,
  required bool platformSupports,
}) =>
    enabled && platformSupports;
