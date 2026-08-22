/// Мелкие повторяющиеся элементы M3 Expressive.
///
/// Слой между токенами ([ExpressiveShape], [ExpressiveSpacing]) и экранами.
/// Он появился потому, что токенов оказалось мало: одинаковые по смыслу
/// элементы всё равно рисовались руками на каждом экране и расходились в
/// мелочах — кружок с иконкой был переписан 28 раз, плашка-предупреждение 18,
/// и у каждой копии свой кегль иконки и своя прозрачность заливки. Ровно это
/// и читается как «интерфейс без дизайнера»: не грубая ошибка, а то, что
/// одинаковые вещи выглядят чуть по-разному.
library;

import 'package:flutter/material.dart';

import 'package:keqdroid/models/icon_shape.dart';
import 'package:keqdroid/shared/ui/expressive.dart';

/// Выбранная пользователем форма кружков-иконок — через тему, а не через
/// провайдер: слой элементов обязан оставаться чистыми виджетами, иначе
/// `ExpressiveIconBadge` нельзя будет поставить в тест или в превью без
/// поднятого ProviderScope.
class ExpressiveIconShapeTheme extends ThemeExtension<ExpressiveIconShapeTheme> {
  const ExpressiveIconShapeTheme({this.shape = IconShape.circle});

  final IconShape shape;

  /// Форма из темы [context]; круг — если расширение не задано (тесты, превью).
  static IconShape of(BuildContext context) =>
      Theme.of(context).extension<ExpressiveIconShapeTheme>()?.shape ??
      IconShape.circle;

  @override
  ExpressiveIconShapeTheme copyWith({IconShape? shape}) =>
      ExpressiveIconShapeTheme(shape: shape ?? this.shape);

  /// Форма — величина дискретная, промежуточных состояний у неё нет:
  /// переключаем на середине, а не пытаемся интерполировать углы.
  @override
  ExpressiveIconShapeTheme lerp(
    ThemeExtension<ExpressiveIconShapeTheme>? other,
    double t,
  ) {
    if (other is! ExpressiveIconShapeTheme) return this;
    return t < 0.5 ? this : other;
  }
}

/// Иконка в цветном кружке — ведущий элемент строки настроек, пункта меню,
/// заголовка секции.
///
/// Размер задаётся диаметром, а не отступом. Раньше это был
/// `Container(padding: EdgeInsets.all(10))` вокруг иконки 20 — то есть кружок
/// 40dp, выраженный числом, которого нет ни в одной шкале. Диаметр 40 — это
/// стандартный размер ведущего элемента строки в M3, и он же оставляет иконку
/// на сетке.
class ExpressiveIconBadge extends StatelessWidget {
  final IconData icon;

  /// Роль контейнера. Игнорируется, если задан [background].
  final ExpressiveAccent accent;

  /// Нештатная заливка для случаев, где цвет несёт свой смысл (ошибка,
  /// предупреждение, статус) и ролью не заменяется.
  final Color? background;
  final Color? foreground;

  /// Диаметр кружка.
  final double size;

  final double iconSize;

  /// Форма поверх выбранной пользователем. Задаётся там, где форма несёт
  /// смысл сама по себе и подчиняться настройке не должна.
  final IconShape? shape;

  const ExpressiveIconBadge({
    super.key,
    required this.icon,
    this.accent = ExpressiveAccent.primary,
    this.background,
    this.foreground,
    this.size = 40,
    this.iconSize = ExpressiveIconSize.medium,
    this.shape,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effective = shape ?? ExpressiveIconShapeTheme.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: background ?? accent.container(scheme),
        shape: effective.border(size),
      ),
      child: Icon(
        icon,
        size: iconSize,
        color: foreground ?? accent.onContainer(scheme),
      ),
    );
  }
}

/// Плашка-подсказка внутри экрана: «нужно переподключиться», «режим прокси не
/// покрывает часть трафика», «HWID выключен».
///
/// Собственных ролей у такой плашки в M3 нет — цвет здесь несёт смысл
/// (предупреждение, ошибка, справка) и берётся снаружи. Единственное, что
/// фиксируется здесь, — прозрачности: раньше заливка была то 0.12, то 0.14, то
/// 0.15, а рамка то 0.32, то 0.35. Разница между ними невидима поодиночке и
/// отлично видна, когда две такие плашки оказываются на одном экране.
class ExpressiveNotice extends StatelessWidget {
  /// Акцентный цвет плашки: `AppTheme.orange`, `scheme.error`, `scheme.primary`.
  final Color color;

  final String text;

  /// Иконка слева. Без неё плашка — просто тонированный абзац.
  final IconData? icon;

  /// Рамка добавляется там, где плашка стоит на уже тонированном фоне и
  /// заливки 0.12 не хватает, чтобы её отделить.
  final bool outlined;

  /// Цвет текста. По умолчанию `onSurface`: цвет плашки несут заливка и иконка,
  /// а сам текст обязан оставаться читаемым. Тонированный текст на тонированном
  /// фоне — первое, что проваливается по контрасту на светлой теме.
  final Color? textColor;

  static const double _fillOpacity = 0.12;
  static const double _outlineOpacity = 0.32;

  const ExpressiveNotice({
    super.key,
    required this.color,
    required this.text,
    this.icon,
    this.outlined = false,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(ExpressiveSpacing.medium),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _fillOpacity),
        borderRadius: ExpressiveShape.radius(ExpressiveShape.medium),
        border: outlined
            ? Border.all(color: color.withValues(alpha: _outlineOpacity))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: ExpressiveIconSize.inline, color: color),
            const SizedBox(width: ExpressiveSpacing.small),
          ],
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.35,
                color: textColor ?? theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
