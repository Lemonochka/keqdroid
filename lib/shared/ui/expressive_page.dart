/// Страница подэкрана: крупный заголовок, который сворачивается при прокрутке.
///
/// До этого все пятнадцать подэкранов настроек открывались одинаково безлично —
/// маленькая шапка и сразу список. В анатомии M3 детальный экран начинается
/// крупным заголовком (`SliverAppBar.large`), который при прокрутке съезжает в
/// обычную шапку: страница получает начало, а не просто начинается.
///
/// Здесь же снимается копипаста: цвет фона, `elevation`, `iconTheme` и стиль
/// заголовка больше не задаются на каждом экране руками — всё приходит из
/// `appBarTheme` (см. `buildExpressiveComponentThemes`).
library;

import 'package:flutter/material.dart';

import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/scrolled_under.dart';
import 'package:keqdroid/shared/ui/smooth_scroll.dart';

class ExpressivePage extends StatelessWidget {
  final String title;

  /// Содержимое — как список детей обычного `ListView`.
  final List<Widget> children;

  final List<Widget>? actions;

  final EdgeInsets padding;

  final Widget? floatingActionButton;

  /// Физика прокрутки. Задаётся там, где экран уже полагался на неё явно
  /// (`ClampingScrollPhysics` вместо андроидного оттяга).
  final ScrollPhysics? physics;

  /// Принудительно включить/выключить крупный заголовок. По умолчанию решение
  /// принимается по высоте окна: на низком вьюпорте крупная шапка съедает
  /// заметную долю экрана, и там честнее обычная.
  final bool? largeTitle;

  /// Ниже этой высоты окна крупный заголовок не показываем. Значение выбрано
  /// по десктопному сценарию: окно в трее сжимается до узкого и невысокого,
  /// и 152dp шапки там были бы половиной содержимого.
  static const double _largeTitleMinHeight = 600;

  const ExpressivePage({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.padding = const EdgeInsets.fromLTRB(
      ExpressiveSpacing.large,
      ExpressiveSpacing.none,
      ExpressiveSpacing.large,
      ExpressiveSpacing.extraLarge,
    ),
    this.floatingActionButton,
    this.physics,
    this.largeTitle,
  });

  @override
  Widget build(BuildContext context) {
    final useLarge =
        largeTitle ?? MediaQuery.sizeOf(context).height >= _largeTitleMinHeight;
    final titleText = Text(title);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      floatingActionButton: floatingActionButton,
      body: SmoothScroll(
        builder: (context, controller) => CustomScrollView(
          controller: controller,
          physics: physics,
          slivers: [
            // Заливку задаём явно, чтобы она перетекала: `WidgetStateColor` из
            // темы переключился бы рывком, а `animateColor` у `SliverAppBar`
            // нет. Перестраивается здесь только сама шапка.
            ExpressiveScrolledUnderBuilder(
              builder: (context, background) => useLarge
                  ? SliverAppBar.large(
                      title: titleText,
                      actions: actions,
                      backgroundColor: background,
                    )
                  : SliverAppBar(
                      title: titleText,
                      actions: actions,
                      pinned: true,
                      backgroundColor: background,
                    ),
            ),
            SliverPadding(
              padding: padding,
              sliver: SliverList.list(children: children),
            ),
          ],
        ),
      ),
    );
  }
}
