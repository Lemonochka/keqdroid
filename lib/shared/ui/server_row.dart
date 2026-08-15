import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/server_item.dart';
import '../../models/server_name_utils.dart';
import '../../services/ping_service.dart';
import '../../utils/bidi.dart';
import 'app_theme.dart';
import 'expressive.dart';
import 'server_avatar.dart';

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

  /// Цвет текста. null — обычный [AppTheme.text]; на поднятом сегменте сюда
  /// приходит `onSecondaryContainer`.
  final Color? foreground;

  /// Бейдж протокола на непрозрачной подложке — так он не сливается с заливкой
  /// поднятого сегмента и выглядит как у соседних строк.
  final bool opaqueBadge;

  /// Имя усиленным начертанием (у M3E это и есть роль выбранного пункта).
  final bool emphasizeTitle;

  final Widget? trailing;

  const ServerRow({
    super.key,
    required this.server,
    this.pingMs,
    this.lastTestedAt,
    this.pingColorType = PingType.tcp,
    this.foreground,
    this.opaqueBadge = false,
    this.emphasizeTitle = false,
    this.trailing,
  });

  /// Высота строки в списках серверов. Общая, чтобы сетка в две колонки и
  /// `mainAxisExtent` не разъезжались с одноколоночным списком.
  static const double height = 76;

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          ServerAvatar(
            flag: server.flag,
            protocol: server.protocol,
            // У цепочки в кружке страна выхода — значок с числом узлов
            // отличает её от обычного сервера той же страны.
            chainHops: isChain ? server.chainConfig!.hops.length : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (server.isPinned)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 4),
                        child: Transform.rotate(
                          // слегка наклонённая канцелярская кнопка — как
                          // «приколотый» пин в мессенджерах
                          angle: 45 * pi / 180,
                          child: Icon(
                            Icons.push_pin,
                            size: 13,
                            color: foreground ?? AppTheme.accent(context),
                          ),
                        ),
                      ),
                    Flexible(
                      child: Text(
                        ServerNameUtils.formatForDisplay(
                          ServerNameUtils.cleanDisplayName(server.displayName),
                        ),
                        style: (emphasizeTitle
                                ? textTheme.emphasized(textTheme.titleSmall)
                                : textTheme.titleSmall)
                            ?.copyWith(color: textColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
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
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: badgeBackground,
                            borderRadius: ExpressiveShape.radius(
                              ExpressiveShape.extraSmall,
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
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        ltrIsolate(
                          pingMs != null
                              ? PingService.formatPingValue(
                                  pingMs!, pingColorType)
                              : (lastTestedAt != null ? 'N/A' : '- ms'),
                        ),
                        // Пинг — числовой показатель, у M3 это роль label, а
                        // не body: плотнее и заметнее при том же кегле.
                        style: textTheme.labelMedium?.copyWith(
                          color: pingMs != null
                              ? pingQualityColor(context, pingMs!, pingColorType)
                              : mutedColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
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
            Icon(Icons.chevron_right, size: dotSize * 0.8, color: arrowColor),
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
          color: serverProtocolColor(context, hop.protocol),
          shape: BoxShape.circle,
        ),
      );
    }
    return ServerAvatar(flag: flag, protocol: hop.protocol, size: dotSize);
  }
}
