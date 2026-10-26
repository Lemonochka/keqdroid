import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/server_avatar.dart';

import '../../models/server_flag.dart';
import '../../services/exit_ip_service.dart';
import 'package:keqdroid/shared/ui/liquid_toast.dart';

// адрес постоянно не показываем: скриншоты главного экрана уходят в чаты и issue
class ConnectedStatusChip extends StatefulWidget {
  const ConnectedStatusChip({
    super.key,
    required this.label,
    required this.exit,
    required this.onJumpToActive,
    required this.textStyle,
    required this.verticalPadding,
    this.borderRadius,
    this.color,
    this.foregroundColor,
    this.fallbackFlag,
    this.fallbackProtocol = '',
    this.maxLines = 2,
    this.minHeight = 0,
    this.textAlign = TextAlign.center,
  });

  final String label;

  final ExitIp? exit;

  final VoidCallback onJumpToActive;
  final TextStyle? textStyle;
  final double verticalPadding;

  final BorderRadius? borderRadius;
  final Color? color;
  final Color? foregroundColor;

  // флаг сервера, пока выход не известен; он не нажимается
  final ServerFlag? fallbackFlag;
  final String fallbackProtocol;
  final int maxLines;
  final double minHeight;
  final TextAlign textAlign;

  static const revealFor = Duration(seconds: 5);

  static const double flagSize = 22;

  @override
  State<ConnectedStatusChip> createState() => _ConnectedStatusChipState();
}

class _ConnectedStatusChipState extends State<ConnectedStatusChip> {
  bool _revealed = false;
  Timer? _hide;

  @override
  void didUpdateWidget(ConnectedStatusChip old) {
    super.didUpdateWidget(old);
    if (old.exit?.ip != widget.exit?.ip) _setRevealed(false);
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _setRevealed(bool revealed) {
    _hide?.cancel();
    if (revealed) {
      _hide = Timer(ConnectedStatusChip.revealFor, () => _setRevealed(false));
    }
    if (mounted && revealed != _revealed) {
      setState(() => _revealed = revealed);
    }
  }

  void _onChipTap() {
    final exit = widget.exit;
    if (!_revealed || exit == null) {
      widget.onJumpToActive();
      return;
    }
    unawaited(Clipboard.setData(ClipboardData(text: exit.ip)));
    _setRevealed(false);
    AppSnack.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.settingsIpCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final exit = widget.exit;
    final flag = exit?.flag;
    final revealed = _revealed && flag != null;
    final shape = RoundedRectangleBorder(
      borderRadius: widget.borderRadius ??
          ExpressiveShape.radius(ExpressiveShape.full),
    );
    final fallback = flag == null &&
            (widget.fallbackFlag != null || widget.fallbackProtocol.isNotEmpty)
        ? Padding(
            padding: const EdgeInsets.all(3),
            child: ServerAvatar(
              flag: widget.fallbackFlag,
              protocol: widget.fallbackProtocol,
              size: ConnectedStatusChip.flagSize,
            ),
          )
        : null;

    final text = Text(
      revealed ? exit!.ip : widget.label,
      key: ValueKey(revealed),
      textAlign: widget.textAlign,
      textDirection: revealed ? TextDirection.ltr : null,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      style: widget.textStyle?.copyWith(
        color: widget.foregroundColor ?? scheme.onSecondaryContainer,
        fontFeatures:
            revealed ? const [FontFeature.tabularFigures()] : null,
      ),
    );
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final swapped = AnimatedSwitcher(
      duration: ExpressiveMotion.durationDefault,
      switchInCurve: const Interval(
        0.3,
        1,
        curve: ExpressiveMotion.emphasizedDecelerate,
      ),
      switchOutCurve: const Interval(0.6, 1),
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          for (final old in previous)
            PositionedDirectional(start: 0, top: 0, bottom: 0, child: old),
          ?current,
        ],
      ),
      transitionBuilder: (child, animation) {
        final faded = FadeTransition(opacity: animation, child: child);
        if (child.key != const ValueKey(true)) return faded;
        return ClipRect(
          clipper: _RevealFromStart(animation, rtl: rtl),
          child: faded,
        );
      },
      child: text,
    );

    final leading = flag != null
        ? Semantics(
            button: true,
            label: l10n.exitIpLabel,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _setRevealed(!_revealed),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: ServerAvatar(
                  flag: flag,
                  protocol: '',
                  size: ConnectedStatusChip.flagSize,
                ),
              ),
            ),
          )
        : fallback;
    final inset = leading != null ? 4.0 : 0.0;
    return Tooltip(
      message: revealed ? l10n.exitIpLabel : l10n.serversJumpToActive,
      waitDuration: const Duration(milliseconds: 600),
      child: Material(
        color: widget.color ?? scheme.secondaryContainer,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _onChipTap,
          customBorder: shape,
          child: Semantics(
            button: true,
            child: AnimatedSize(
              // на пружине, как подпись статуса рядом: при смене состояния не прыгает
              duration: const Duration(milliseconds: 450),
              curve: const SpringCurve(
                ExpressiveMotion.spatialFast,
                Duration(milliseconds: 450),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: widget.minHeight),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      leading != null ? 6 : 16,
                      widget.verticalPadding - inset,
                      16,
                      widget.verticalPadding - inset,
                    ),
                    child: leading == null
                        ? swapped
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              leading,
                              const SizedBox(width: 6),
                              Flexible(child: swapped),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RevealFromStart extends CustomClipper<Rect> {
  _RevealFromStart(this.progress, {required this.rtl})
      : super(reclip: progress);

  final Animation<double> progress;
  final bool rtl;

  @override
  Rect getClip(Size size) {
    final width = size.width * progress.value.clamp(0.0, 1.0);
    return rtl
        ? Rect.fromLTWH(size.width - width, 0, width, size.height)
        : Rect.fromLTWH(0, 0, width, size.height);
  }

  @override
  bool shouldReclip(_RevealFromStart old) =>
      old.progress != progress || old.rtl != rtl;
}
