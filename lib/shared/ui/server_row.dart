import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/server_item.dart';
import '../../models/server_name_utils.dart';
import '../../services/ping_service.dart';
import '../../utils/bidi.dart';
import 'app_theme.dart';
import 'expressive.dart';
import 'server_avatar.dart';

/// Как стоит ряд: строкой (флаг, имя с бейджем и пингом, кружок справа) или
/// карточкой сетки (флаг, имя в две строки, пинг).
enum ServerRowLayout { inline, card }

/// Содержимое строки сервера: кружок, имя, бейдж протокола (или маршрут у
/// цепочки) и пинг.
///
/// Живёт отдельно от плитки списка, потому что ровно этот же ряд нужен при
/// выборе узлов цепочки. Пока он был приватной частью вкладки серверов, второй
/// список приходилось рисовать заново — и два списка одного и того же начинали
/// расходиться видом на первой же правке.
///
/// Виджет чисто презентационный: ни провайдеров, ни жестов. Подсветку
/// активного, анимации и меню добавляет владелец строки.
class ServerRow extends StatelessWidget {
  final ServerItem server;

  /// Пинг и когда он снят: null — прочерк, есть время без значения — «N/A».
  final int? pingMs;
  final DateTime? lastTestedAt;

  /// Тип пинга для порогов цвета (у url и tcp шкалы разные).
  final PingType pingColorType;

  /// Цвет текста. null — обычный [AppTheme.text]; на выбранном сегменте сюда
  /// приходит `onSecondaryContainer`.
  final Color? foreground;

  /// Строка выбрана — это меняет бейдж протокола дважды: подложка становится
  /// непрозрачной (иначе полупрозрачный тон сводится с заливкой сегмента и
  /// надпись проваливается по контрасту), а форма — пилюлей вместо углов в 4dp.
  final bool opaqueBadge;

  /// Имя усиленным начертанием (у M3E это и есть роль выбранного пункта).
  final bool emphasizeTitle;

  /// Выбирает владелец: ширину ячейки знает только он (см. [fitsInline]).
  final ServerRowLayout layout;

  /// Кружок справа — только у строки.
  final Widget? trailing;

  /// Значок состояния перед пингом — только у карточки: кружку справа в ней
  /// нет места, не отняв его у имени.
  final Widget? status;

  const ServerRow({
    super.key,
    required this.server,
    this.pingMs,
    this.lastTestedAt,
    this.pingColorType = PingType.tcp,
    this.foreground,
    this.opaqueBadge = false,
    this.emphasizeTitle = false,
    this.layout = ServerRowLayout.inline,
    this.trailing,
    this.status,
  });

  /// Шаг строки в списках серверов — вместе с зазором между сегментами, а не
  /// высота самого контейнера (та меньше ровно на зазор `ExpressiveListSegment.gap`).
  ///
  /// Общая константа, чтобы сетка в две колонки, `mainAxisExtent` и смещение
  /// якоря активного сервера считались от одного числа.
  static const double height = 76;

  /// Помещается ли строка в сегмент такой ширины.
  ///
  /// Поля, флаг и кружок справа занимают 124dp при любой ширине. В две колонки
  /// на вертикальном телефоне сегменту достаётся около 184dp, и на имя с пингом
  /// оставалось 60: «Росс…» и «42 …». 140dp под текст — это бейдж протокола и
  /// пинг целиком плюс начало имени; с крупным шрифтом растут и они.
  static bool fitsInline(double width, TextScaler textScaler) =>
      width >= _inlineChrome + textScaler.scale(16) / 16 * _inlineMinText;

  // 16 + флаг 40 + 12 слева, 8 + кружок 32 + 16 справа.
  static const double _inlineChrome = 124;
  static const double _inlineMinText = 140;

  /// Зазор между карточками — предел, который спека M3 ставит карточкам в
  /// сетке. Зазор сегментов списка (4dp) тут не годится: сегменты делят одну
  /// группу, а карточки — отдельные предметы.
  static const double cardGap = ExpressiveSpacing.small;

  static const double _avatarSize = 40;
  static const double _cardVerticalPadding = ExpressiveSpacing.medium;

  /// Шаг карточки — как и [height], вместе с зазором между карточками.
  ///
  /// Высота ячейки в сетке одна на всех, а у имени две строки и пинг под ним:
  /// взятый числом, при крупном шрифте (масштаб в настройках до 1.4 поверх
  /// системного) текст вылез бы за низ. Поэтому строки считаются от темы и
  /// текущего масштаба.
  static double cardHeight(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle? style) =>
        scaler.scale(style!.fontSize!) * style.height!;

    final text = line(textTheme.bodyLarge) * 2 +
        ExpressiveSpacing.hairline +
        max(line(textTheme.labelLarge), ExpressiveIconSize.inline);
    return (cardGap + _cardVerticalPadding * 2 + max(_avatarSize, text))
        .ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final textColor = foreground ?? AppTheme.text(context);
    final mutedColor = foreground?.withValues(alpha: 0.7) ??
        AppTheme.textLight(context);

    final isChain = server.protocol == 'chain';
    final protocolColor = serverProtocolColor(context, server.protocol);
    final badgeBackground = opaqueBadge
        ? AppTheme.card(context)
        : protocolColor.withValues(alpha: 0.15);

    final avatar = ServerAvatar(
      flag: server.flag,
      protocol: server.protocol,
      // У цепочки в кружке страна выхода — значок с числом узлов
      // отличает её от обычного сервера той же страны.
      chainHops: isChain ? server.chainConfig!.hops.length : null,
    );

    final name = ServerNameUtils.formatForDisplay(
      ServerNameUtils.cleanDisplayName(server.displayName),
    );
    // Имя пункта списка — роль `bodyLarge`: это label text по токенам списка, а
    // не заголовок. Выбранный сервер отличается весом (усиленный вариант), а не
    // кеглем.
    final nameStyle = (emphasizeTitle
            ? textTheme.emphasized(textTheme.bodyLarge)
            : textTheme.bodyLarge)
        ?.copyWith(color: textColor);
    final pin = server.isPinned
        ? Padding(
            padding: const EdgeInsetsDirectional.only(
              end: ExpressiveSpacing.extraSmall,
            ),
            child: Transform.rotate(
              // слегка наклонённая канцелярская кнопка — как
              // «приколотый» пин в мессенджерах
              angle: 45 * pi / 180,
              child: Icon(
                Icons.push_pin_rounded,
                size: ExpressiveIconSize.inline,
                color: foreground ?? AppTheme.accent(context),
              ),
            ),
          )
        : null;

    final ping = Text(
      ltrIsolate(
        pingMs != null
            ? PingService.formatPingValue(pingMs!, pingColorType)
            : (lastTestedAt != null ? 'N/A' : '- ms'),
      ),
      // Пинг — числовой показатель, у M3 это роль label, а не body: плотнее и
      // заметнее при том же кегле. Кегль берём supporting-строки списка
      // (14sp), иначе рядом с 16sp именем вторая строка проваливается.
      style: textTheme.labelLarge?.copyWith(
        color: pingMs != null
            ? pingQualityColor(context, pingMs!, pingColorType)
            : mutedColor,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (layout == ServerRowLayout.card) {
      // Горизонтально, как и строка: по спеке карточка на компактной ширине
      // лежит боком, а стоймя встаёт только на широких экранах. Бейджа
      // протокола и маршрута цепочки здесь нет — на узком экране пункт
      // показывает меньше, а протокол у подписок и так в имени; вся ширина
      // уходит имени, и оно переносится на вторую строку, а не режется.
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ExpressiveSpacing.large,
          vertical: _cardVerticalPadding,
        ),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: ExpressiveSpacing.medium),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Булавка частью текста: при переносе имени она остаётся у
                  // первой строки, а не повисает посередине двух.
                  Text.rich(
                    TextSpan(
                      children: [
                        if (pin != null)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: pin,
                          ),
                        TextSpan(text: name),
                      ],
                    ),
                    style: nameStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: ExpressiveSpacing.hairline),
                  Row(
                    children: [
                      if (status != null) ...[
                        status!,
                        const SizedBox(width: ExpressiveSpacing.extraSmall),
                      ],
                      Flexible(child: ping),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final title = Row(
      children: [
        ?pin,
        Flexible(
          child: Text(
            name,
            style: nameStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final details = Row(
      children: [
        // У цепочки на месте бейджа протокола — сам маршрут:
        // «какие страны и в каком порядке» и есть её содержание,
        // а слово CHAIN уже сказано значком на кружке.
        if (isChain)
          Flexible(
            child: ChainRouteStrip(
              hops: server.chainHopItems,
              arrowColor: mutedColor,
            ),
          )
        else
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ExpressiveSpacing.small,
                vertical: ExpressiveSpacing.hairline,
              ),
              decoration: BoxDecoration(
                color: badgeBackground,
                // Форму бейджа ведёт выбор — тем же правилом, что
                // форму самого сегмента: у невыбранных углы 4dp,
                // у выбранного пилюля. Одинаковая пилюля на всех
                // строках этот перепад съедала.
                borderRadius: ExpressiveShape.radius(
                  opaqueBadge
                      ? ExpressiveShape.full
                      : ExpressiveShape.extraSmall,
                ),
              ),
              child: Text(
                server.protocol.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme
                    .emphasized(textTheme.labelSmall)
                    ?.copyWith(color: protocolColor),
              ),
            ),
          ),
        const SizedBox(width: ExpressiveSpacing.small),
        Flexible(child: ping),
      ],
    );

    return Padding(
      // Отступ leading-слота по спеке списка — 16dp от края контейнера.
      padding: const EdgeInsets.symmetric(
        horizontal: ExpressiveSpacing.large,
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: ExpressiveSpacing.medium),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                title,
                const SizedBox(height: ExpressiveSpacing.hairline),
                details,
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: ExpressiveSpacing.small),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Цвет значения пинга по его качеству.
Color pingQualityColor(BuildContext context, int ms, PingType type) =>
    switch (PingService.pingLatencyQuality(ms, type)) {
      PingLatencyQuality.good => AppTheme.green(context),
      PingLatencyQuality.fair => AppTheme.orange(context),
      PingLatencyQuality.poor => AppTheme.red(context),
    };

/// Маршрут цепочки одной строкой: кружок страны на каждый узел, между ними
/// стрелки. Читается с одного взгляда — «через Германию в Японию» — и потому
/// стоит на месте, где у обычного сервера бейдж протокола.
class ChainRouteStrip extends StatelessWidget {
  final List<ServerItem> hops;
  final Color arrowColor;

  /// Размер кружка узла: заметно меньше аватарки сервера, но флаг ещё узнаётся.
  final double dotSize;

  /// Сколько узлов показываем целиком; остальные сворачиваются в «+N».
  static const int visibleHops = 4;

  const ChainRouteStrip({
    super.key,
    required this.hops,
    required this.arrowColor,
    this.dotSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final shown =
        hops.length > visibleHops ? hops.sublist(0, visibleHops) : hops;
    final hidden = hops.length - shown.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0)
            Icon(Icons.chevron_right_rounded, size: dotSize * 0.8, color: arrowColor),
          _node(context, shown[i]),
        ],
        if (hidden > 0) ...[
          const SizedBox(width: 3),
          Text(
            '+$hidden',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: arrowColor),
          ),
        ],
      ],
    );
  }

  Widget _node(BuildContext context, ServerItem hop) {
    final flag = hop.flag;
    // Без флага буква протокола на 16px нечитаема — тогда просто точка его
    // цветом: ряд остаётся ровным, а протокол всё равно различим.
    if (flag == null) {
      return Container(
        width: dotSize,
        height: dotSize,
        decoration: BoxDecoration(
          color: serverIconColors(context, hop.protocol).background,
          shape: BoxShape.circle,
        ),
      );
    }
    return ServerAvatar(flag: flag, protocol: hop.protocol, size: dotSize);
  }
}
