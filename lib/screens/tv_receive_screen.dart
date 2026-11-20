import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/shape_loading_indicator.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/app_logger.dart';
import '../models/subscription.dart';
import '../providers/providers.dart';
import '../services/tv_handoff.dart';
import '../utils/error_messages.dart';
import '../utils/subscription_url.dart';

class TvReceiveScreen extends ConsumerStatefulWidget {
  const TvReceiveScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const TvReceiveScreen()));

  @override
  ConsumerState<TvReceiveScreen> createState() => _TvReceiveScreenState();
}

enum _Phase { starting, waiting, received, failed, noNetwork }

class _TvReceiveScreenState extends ConsumerState<TvReceiveScreen> {
  TvReceiveServer? _server;
  _Phase _phase = _Phase.starting;

  String _detail = '';

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    unawaited(_server?.close());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final lan = await findLanAddress();
      if (!mounted) return;
      if (lan == null) {
        setState(() => _phase = _Phase.noNetwork);
        return;
      }
      final server = await TvReceiveServer.start(
        lanAddress: lan,
        onOffer: _onOffer,
      );
      if (!mounted) {
        await server.close();
        return;
      }
      setState(() {
        _server = server;
        _phase = _Phase.waiting;
      });
    } catch (e, st) {
      AppLogger.instance.warn(
        'TV receive server failed to start',
        error: e,
        stackTrace: st,
      );
      if (mounted) setState(() => _phase = _Phase.noNetwork);
    }
  }

  Future<String?> _onOffer(TvSubscriptionOffer offer) async {
    if (!mounted) return 'The receive screen was closed';
    final key = normalizeSubscriptionUrl(offer.url);
    final known = ref
        .read(subscriptionsProvider)
        .value
        ?.where((s) => normalizeSubscriptionUrl(s.url) == key)
        .firstOrNull;
    if (known != null) {
      setState(() {
        _phase = _Phase.received;
        _detail = known.name;
      });
      return null;
    }
    final sub = Subscription.create(
      name: offer.name ?? Uri.parse(offer.url).host,
      url: offer.url,
      nameIsAuto: offer.nameIsAuto,
    );
    final subscriptions = ref.read(subscriptionsProvider.notifier);
    try {
      await subscriptions.add(sub);
    } catch (e) {
      if (!mounted) return explainError(e).short;
      final why = explainErrorLocalized(e, AppLocalizations.of(context)!);
      final text = '${why.title}: ${why.message}';
      setState(() {
        _phase = _Phase.failed;
        _detail = text;
      });
      return text;
    }
    if (!mounted) return null;
    final added = ref
        .read(subscriptionsProvider)
        .value
        ?.where((s) => s.id == sub.id)
        .firstOrNull;
    setState(() {
      _phase = _Phase.received;
      _detail = added?.name ?? sub.name;
    });
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;

    final info = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tvReceiveTitle,
            style: textTheme
                .emphasized(textTheme.headlineSmall)
                ?.copyWith(color: AppTheme.text(context)),
          ),
          const SizedBox(height: ExpressiveSpacing.medium),
          Text(
            l10n.tvReceiveHint,
            style: textTheme.bodyLarge?.copyWith(
              color: AppTheme.textLight(context),
            ),
          ),
          const SizedBox(height: ExpressiveSpacing.largeIncreased),
          _status(context, l10n),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final qr = _QrCard(
              data: _server?.pairing.toLink(),
              offline: _phase == _Phase.noNetwork,
            );
            final wide = constraints.maxWidth >= 700;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ExpressiveSpacing.extraLarge),
                child: wide
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [qr, const SizedBox(width: 40), info],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          qr,
                          const SizedBox(height: ExpressiveSpacing.extraLarge),
                          info,
                        ],
                      ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _status(BuildContext context, AppLocalizations l10n) {
    final (Widget icon, String text, Color color) = switch (_phase) {
      _Phase.starting || _Phase.waiting => (
        ShapeLoadingIndicator(size: 24, color: AppTheme.accent(context)),
        l10n.tvReceiveWaiting,
        AppTheme.accent(context),
      ),
      _Phase.received => (
        Icon(Icons.check_circle_rounded, color: AppTheme.green(context)),
        l10n.tvReceiveGot(_detail),
        AppTheme.green(context),
      ),
      _Phase.failed => (
        Icon(Icons.error_outline_rounded, color: AppTheme.red(context)),
        l10n.tvReceiveFailed(_detail),
        AppTheme.red(context),
      ),
      _Phase.noNetwork => (
        Icon(Icons.wifi_off_rounded, color: AppTheme.red(context)),
        l10n.tvReceiveNoNetwork,
        AppTheme.red(context),
      ),
    };
    return Row(
      children: [
        SizedBox.square(dimension: 24, child: Center(child: icon)),
        const SizedBox(width: ExpressiveSpacing.small),
        Flexible(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

// на белом: камеры хуже читают код на цветной подложке
class _QrCard extends StatelessWidget {
  const _QrCard({required this.data, required this.offline});

  final String? data;
  final bool offline;

  static const double _size = 240;

  @override
  Widget build(BuildContext context) {
    final data = this.data;
    return Container(
      padding: const EdgeInsets.all(ExpressiveSpacing.large),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ExpressiveShape.large),
      ),
      child: SizedBox.square(
        dimension: _size,
        child: data != null
            ? QrImageView(
                data: data,
                version: QrVersions.auto,
                size: _size,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
              )
            : Center(
                child: offline
                    ? const Icon(
                        Icons.wifi_off_rounded,
                        size: 64,
                        color: Colors.black38,
                      )
                    : const ShapeLoadingIndicator(color: Colors.black38),
              ),
      ),
    );
  }
}
