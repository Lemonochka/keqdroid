import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/app_settings.dart';
import '../../models/server_item.dart';
import '../../models/server_name_utils.dart';
import '../../services/ping_service.dart';
import '../../utils/bidi.dart';
import 'app_theme.dart';
import 'expressive.dart';
import 'expressive_group.dart';
import 'halloween/halloween_icons.dart';
import 'server_avatar.dart';

enum ServerRowLayout { inline, card }

class ServerRow extends StatelessWidget {
  final ServerItem server;

  final int? pingMs;
  final DateTime? lastTestedAt;

  final PingType pingColorType;

  final Color? foreground;

  final bool opaqueBadge;

  final bool emphasizeTitle;

  final ServerRowLayout layout;

  final bool muted;
  final Widget? avatarBadge;

  final Widget? trailing;

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
    this.muted = false,
    this.avatarBadge,
    this.trailing,
    this.status,
  });

  static const double height = 76;

  static bool fitsInline(double width, TextScaler textScaler) =>
      width >= _inlineChrome + textScaler.scale(16) / 16 * _inlineMinText;

  // 16 + флаг 40 + 12 слева, 8 + кружок 32 + 16 справа.
  static const double _inlineChrome = 124;
  static const double _inlineMinText = 140;

  static bool fitsCard(double width, TextScaler textScaler) =>
      width >= _cardChrome + textScaler.scale(16) / 16 * _cardMinText;

  // 16 + флаг 40 + 12 слева, 16 справа. меньше 100 на текст: на Pixel 6a при 120% резались имена, при 140% и пинг
  static const double _cardChrome = 84;
  static const double _cardMinText = 100;

  static const double listSideInset = 16;

  static int wantedColumns(AppSettings settings) =>
      settings.serversTwoColumns ? settings.serversColumns : 1;

  static double columnCell(double listWidth, int columns) =>
      (listWidth -
          listSideInset * 2 -
          ExpressiveListSegment.gap * (columns + 1)) /
      columns;

  static int fittingColumns(
    double listWidth,
    TextScaler textScaler,
    int wanted,
  ) {
    for (var n = wanted; n > 1; n--) {
      final cell = columnCell(listWidth, n);
      if (fitsInline(cell, textScaler) || fitsCard(cell, textScaler)) return n;
    }
    return 1;
  }

  static const double cardGap = ExpressiveListSegment.gap;

  static const double _avatarSize = 40;
  static const double _cardVerticalPadding = ExpressiveSpacing.medium;

  // от темы и масштаба: числом при крупном шрифте текст вылез бы за низ
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

    Widget avatar = ServerAvatar(
      flag: server.flag,
      protocol: server.protocol,
      chainHops: isChain ? server.chainConfig!.hops.length : null,
    );
    avatar = _MuteFade(muted: muted, opacity: 0.4, child: avatar);
    if (avatarBadge != null) {
      avatar = SizedBox.square(
        dimension: _avatarSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: avatar),
            PositionedDirectional(bottom: -3, end: -3, child: avatarBadge!),
          ],
        ),
      );
    }

    final name = ServerNameUtils.formatForDisplay(
      ServerNameUtils.cleanDisplayName(server.displayName),
    );
    final nameDirection =
        contentDirection(name, fallback: Directionality.of(context));
    final nameAlign = uiStartAlign(context);
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
              angle: 45 * pi / 180,
              child: SeasonalIcon(
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
      style: textTheme.labelLarge?.copyWith(
        color: pingMs != null
            ? pingQualityColor(context, pingMs!, pingColorType)
            : mutedColor,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (layout == ServerRowLayout.card) {
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
              child: _MuteFade(
                muted: muted,
                opacity: 0.45,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                      textDirection: nameDirection,
                      textAlign: nameAlign,
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
            textDirection: nameDirection,
            textAlign: nameAlign,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final details = Row(
      children: [
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
      padding: const EdgeInsets.symmetric(
        horizontal: ExpressiveSpacing.large,
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: ExpressiveSpacing.medium),
          Expanded(
            child: _MuteFade(
              muted: muted,
              opacity: 0.45,
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

Color pingQualityColor(BuildContext context, int ms, PingType type) =>
    switch (PingService.pingLatencyQuality(ms, type)) {
      PingLatencyQuality.good => AppTheme.green(context),
      PingLatencyQuality.fair => AppTheme.orange(context),
      PingLatencyQuality.poor => AppTheme.red(context),
    };

class ChainRouteStrip extends StatelessWidget {
  final List<ServerItem> hops;
  final Color arrowColor;

  final double dotSize;

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

class _MuteFade extends StatelessWidget {
  const _MuteFade({
    required this.muted,
    required this.opacity,
    required this.child,
  });

  final bool muted;
  final double opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: muted ? opacity : 1.0),
        duration: ExpressiveMotion.durationDefault,
        curve: Curves.easeOutCubic,
        builder: (context, value, child) =>
            Opacity(opacity: value, child: child),
        child: child,
      );
}
