import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/app_info.dart';
import '../../services/app_icon_cache.dart';
import 'app_theme.dart';
import 'expressive.dart';
import 'expressive_group.dart';
import 'haptics.dart';

class AppListTile extends StatelessWidget {
  final AppInfo app;
  final bool checked;

  final Color? markColor;

  // форму считает список: только он знает, где у строки сосед, а где край группы
  final BorderRadius radius;

  final EdgeInsets margin;

  final VoidCallback? onTap;

  // кэш иконок сверху: свой ConsumerStatefulWidget на строке тащил бы область зависимостей Riverpod, а строк сотни
  final AppIconCache iconCache;

  // 40 dp иконки и две строки текста с полями по 8; на этом шаге живёт SliverFixedExtentList
  static const double height = 72;

  static const double _markSize = 24;

  const AppListTile({
    super.key,
    required this.app,
    required this.checked,
    required this.markColor,
    required this.radius,
    required this.margin,
    required this.onTap,
    required this.iconCache,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = checked ? scheme.onSecondaryContainer : scheme.onSurface;
    final muted = checked
        ? scheme.onSecondaryContainer.withValues(alpha: 0.7)
        : scheme.onSurfaceVariant;
    final titleStyle = checked
        ? theme.textTheme.emphasized(theme.textTheme.bodyLarge)
        : theme.textTheme.bodyLarge;

    return RepaintBoundary(
      child: MergeSemantics(
        child: Padding(
          padding: margin,
          child: ExpressiveListSegment(
            radius: radius,
            selected: checked,
            color: scheme.surfaceContainerHigh,
            selectedColor: scheme.secondaryContainer,
            onTap: onTap == null
                ? null
                : () {
                    AppHaptics.selection();
                    onTap!();
                  },
            splashColor: scheme.primary.withValues(alpha: 0.2),
            highlightColor: scheme.primary.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ExpressiveSpacing.large,
              ),
              child: Row(
                children: [
                  AppIconView(
                    iconBase64: app.iconBase64,
                    appName: app.appName,
                    iconPath: app.installPath,
                    cache: iconCache,
                  ),
                  const SizedBox(width: ExpressiveSpacing.medium),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                app.appName,
                                style: titleStyle?.copyWith(color: foreground),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // точка, а не символ: символ прыгал по базовой линии между шрифтами тем
                            if (app.isRunning) ...[
                              const SizedBox(width: ExpressiveSpacing.small),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: AppTheme.green(context),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          app.installPath ?? app.packageName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (markColor case final color?) ...[
                    const SizedBox(width: ExpressiveSpacing.medium),
                    AppSelectionMark(checked: checked, color: color),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppSelectionMark extends StatelessWidget {
  final bool checked;
  final Color color;
  const AppSelectionMark({
    super.key,
    required this.checked,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedSwitcher(
      duration: ExpressiveMotion.durationFast,
      switchInCurve: ExpressiveMotion.emphasized,
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: checked
          ? Container(
              key: const ValueKey('checked'),
              width: AppListTile._markSize,
              height: AppListTile._markSize,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(
                Icons.check_rounded,
                size: ExpressiveIconSize.inline,
                color: scheme.surface,
              ),
            )
          : Container(
              key: const ValueKey('unchecked'),
              width: AppListTile._markSize,
              height: AppListTile._markSize,
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outline, width: 2),
                shape: BoxShape.circle,
              ),
            ),
    );
  }
}

class AppIconView extends StatefulWidget {
  final String? iconBase64;
  final String appName;
  final String? iconPath;

  final AppIconCache cache;

  const AppIconView({
    super.key,
    required this.iconBase64,
    required this.appName,
    required this.cache,
    this.iconPath,
  });

  @override
  State<AppIconView> createState() => _AppIconViewState();
}

class _AppIconViewState extends State<AppIconView> {
  Uint8List? _bytes;

  AppIconCache get _cache => widget.cache;

  // отписываемся по сохранённому пути: в dispose виджет может нести уже другой
  String? _pendingPath;

  @override
  void initState() {
    super.initState();
    _applyIcon(widget.iconBase64);
    if (_bytes == null) _loadIcon();
  }

  @override
  void didUpdateWidget(AppIconView old) {
    super.didUpdateWidget(old);
    if (old.iconBase64 != widget.iconBase64) {
      _applyIcon(widget.iconBase64);
    }
    if (old.iconPath != widget.iconPath) {
      _releasePending();
      if (_bytes == null) _loadIcon();
    }
  }

  @override
  void dispose() {
    _releasePending();
    super.dispose();
  }

  void _applyIcon(String? src) {
    if (src != null && src.isNotEmpty) {
      try {
        _bytes = base64Decode(src);
      } catch (_) {
        _bytes = null;
      }
    } else {
      _bytes = null;
    }
  }

  void _releasePending() {
    final path = _pendingPath;
    if (path == null) return;
    _pendingPath = null;
    _cache.release(path);
  }

  // через общий кэш: без него на быстрой прокрутке поток платформы разбирал десятки выемок подряд, и список рвало
  void _loadIcon() {
    final path = widget.iconPath;
    if (path == null || path.isEmpty) return;
    if (_cache.has(path)) {
      _bytes = _cache.peek(path);
      return;
    }
    _pendingPath = path;
    _cache.request(path).then((bytes) {
      if (!mounted || bytes == null) return;
      setState(() => _bytes = bytes);
    });
  }

  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return ClipRRect(
        borderRadius: ExpressiveShape.radius(ExpressiveShape.medium),
        child: Image.memory(
          _bytes!,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          // иконка приезжает крупнее слота (128), а на уменьшении качество фильтра и видно
          filterQuality: FilterQuality.medium,
          // декод под размер слота: иконки бывают до 512×512, полный декод раздувал image cache
          cacheWidth: (_size * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (context, error, stackTrace) => _fallback(context),
        ),
      );
    }
    return _fallback(context);
  }

  // буква в контейнере роли: полупрозрачный акцент сводился с заливкой строки, и на выбранной съезжал оттенок
  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: ExpressiveShape.radius(ExpressiveShape.medium),
      ),
      child: Center(
        child: Text(
          widget.appName.isNotEmpty ? widget.appName[0].toUpperCase() : '?',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: scheme.onPrimaryContainer),
        ),
      ),
    );
  }
}
