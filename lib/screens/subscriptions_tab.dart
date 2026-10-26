import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/floating_bar.dart';
import 'package:keqdroid/shared/ui/reorder_zoom_fix.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/expressive_elements.dart';
import 'package:keqdroid/shared/ui/expressive_button_group.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';
import 'package:keqdroid/shared/ui/tv_focus.dart';
import 'package:keqdroid/shared/ui/update_interval_sheet.dart';
import 'package:keqdroid/shared/ui/horizontal_mouse_scroll.dart';
import 'package:keqdroid/shared/ui/shape_loading_indicator.dart';
import 'package:keqdroid/shared/ui/smooth_scroll.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/subscription.dart';
import '../models/subscription_card_layout.dart';
import '../models/subscription_card_theme.dart';
import '../core/exceptions.dart';
import '../services/card_image_service.dart';
import '../services/file_dialog_service.dart';
import '../platform/platform_bootstrap.dart';
import '../providers/providers.dart';
import 'qr_scan_screen.dart';
import 'settings_tab.dart' show routingScreen;
import 'tv_receive_screen.dart';
import 'tv_send_dialog.dart';
import '../services/tv_handoff.dart';
import '../ui/responsive/desktop_page_layout.dart';
import '../utils/bidi.dart';
import '../utils/error_messages.dart';
import '../utils/external_link.dart';
import '../utils/identity_presets.dart';
import '../utils/routing_profiles.dart';
import '../utils/time_ago.dart';
import 'package:keqdroid/shared/ui/liquid_toast.dart';

part 'subscriptions/card_look_sheet.dart';
part 'subscriptions/identity_sheet.dart';

class SubscriptionsTab extends ConsumerWidget {
  const SubscriptionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final subsAsync = ref.watch(subscriptionsProvider);

    final bgColor = AppTheme.bg(context);
    final textColor = AppTheme.text(context);

    // кнопка действия стоит на линии пилюли, а её отступ панель сообщает после кадра
    return ValueListenableBuilder<double>(
      valueListenable: FloatingBar.bottomInset,
      builder: (context, _, _) => Scaffold(
          backgroundColor: bgColor,
          body: _withFloatingAction(context, ref, SafeArea(
            child: DesktopPageLayout(
              maxWidth: 920,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      tabContentHorizontalInset(),
                      24,
                      tabContentHorizontalInset(),
                      8,
                    ),
                    child: Text(
                      l10n.subscriptionsTitle,
                      style: Theme.of(context).textTheme
                          .emphasized(Theme.of(context).textTheme.headlineMedium)
                          ?.copyWith(color: textColor),
                    ),
                  ),
                  Expanded(
                    child: subsAsync.when(
                      skipLoadingOnReload: true,
                      loading: () => const Center(
                        child: ShapeLoadingIndicator(),
                      ),
                      error: (e, _) => _SubsErrorView(
                        error: e,
                        onRetry: () => ref.invalidate(subscriptionsProvider),
                      ),
                      data: (subs) => subs.isEmpty
                          ? _emptySubsState(context)
                          : SmoothScroll(
                              builder: (context, controller) => FloatingBarFade(
                                child: ReorderZoomFix(
                                builder: (context, fix) =>
                                  ReorderableListView.builder(
                                    scrollController: controller,
                                    physics: const ClampingScrollPhysics(),
                                    padding: EdgeInsets.fromLTRB(
                                      16,
                                      8,
                                      16,
                                      FloatingBar.shown(context)
                                          ? 24 + FloatingBar.clearance(context)
                                          : 100,
                                    ),
                                    buildDefaultDragHandles: false,
                                    onReorderStart: (_) {
                                      ref
                                          .read(
                                            subscriptionReorderInProgressProvider
                                                .notifier,
                                          )
                                          .set(true);
                                    },
                                    onReorderEnd: (_) {
                                      ref
                                          .read(
                                            subscriptionReorderInProgressProvider
                                                .notifier,
                                          )
                                          .set(false);
                                    },
                                    // onReorderItem уже поправил newIndex, иначе вычтем единицу дважды
                                    onReorderItem: (oldIndex, newIndex) {
                                      ref
                                          .read(subscriptionsProvider.notifier)
                                          .reorder(
                                            oldIndex,
                                            newIndex,
                                            fromReorderableList: false,
                                          );
                                    },
                                    proxyDecorator: (child, index, animation) {
                                      return fix(AnimatedBuilder(
                                        animation: animation,
                                        builder: (context, child) {
                                          final scale =
                                              Tween<double>(
                                                begin: 1.0,
                                                end: 1.02,
                                              ).evaluate(
                                                CurvedAnimation(
                                                  parent: animation,
                                                  curve: Curves.easeOut,
                                                ),
                                              );
                                          return Transform.scale(
                                            scale: scale,
                                            child: Material(
                                              color: Colors.transparent,
                                              elevation: 8,
                                              shadowColor: Colors.black26,
                                              borderRadius:
                                                  BorderRadius.circular(ExpressiveShape.largeIncreased),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: child,
                                      ), animation);
                                    },
                                    itemCount: subs.length,
                                    itemBuilder: (_, i) {
                                      final sub = subs[i];
                                      final isDesktop =
                                          PlatformBootstrap.isDesktop;
                                      final item = _SubItem(
                                        sub: sub,
                                        listIndex: i,
                                        onDelete: () => ref
                                            .read(
                                              subscriptionsProvider.notifier,
                                            )
                                            .remove(sub.id),
                                        onRefresh: () => ref
                                            .read(
                                              subscriptionsProvider.notifier,
                                            )
                                            .refreshTracked(sub),
                                      );
                                      return Padding(
                                        key: ValueKey(sub.id),
                                        padding: EdgeInsets.only(
                                          bottom: i < subs.length - 1 ? 12 : 0,
                                        ),
                                        child: isDesktop
                                            ? item
                                            : ReorderableDelayedDragStartListener(
                                                index: i,
                                                child: item,
                                              ),
                                      );
                                    },
                                  ),
                              ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          )),
          floatingActionButton: FloatingBar.shown(context)
              ? null
              : TvFocus.fab(
            (fabContext) => FloatingActionButton.extended(
              heroTag: 'subscriptions_add_fab',
              backgroundColor: AppTheme.accentContainer(fabContext),
              foregroundColor: AppTheme.onAccentContainer(fabContext),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.subscriptionsAddButton),
              onPressed: () => _showAddSubDialog(context, ref),
            ),
          ),
      ),
    );
  }

  // кнопка живёт в панели, страница только отдаёт ей действие
  Widget _withFloatingAction(BuildContext context, WidgetRef ref, Widget body) {
    if (!FloatingBar.shown(context)) return body;
    FloatingBar.actions[1] = () => _showAddSubDialog(context, ref);
    return FloatingBarHideOnScroll(child: body);
  }

  Widget _emptySubsState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accentColor = AppTheme.accent(context);
    final textLightColor = AppTheme.textLight(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.subscriptions_rounded,
            size: 48,
            color: accentColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.subscriptionsEmptyTitle,
            style: TextStyle(color: textLightColor),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.subscriptionsEmptyHint,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: textLightColor),
          ),
        ],
      ),
    );
  }

  void _showAddSubDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    // идентичность до первой загрузки: панель с привязкой по HWID считает устройство уже на ней
    var identity = SubscriptionFetchIdentity.empty;
    bool loading = false;
    // снек-бар скрыт за модальным барьером, а закрытие шторки потеряло бы URL
    String? sheetError;

    final textColor = AppTheme.text(context);
    final accentContainerColor = AppTheme.accentContainer(context);
    final onAccentContainerColor = AppTheme.onAccentContainer(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Text(
                  l10n.subscriptionsAddSubscription,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme
                      .emphasized(Theme.of(context).textTheme.titleLarge)
                      ?.copyWith(color: textColor),
                ),
              ),
              const SizedBox(height: 20),
              _inputField(
                context,
                nameCtrl,
                l10n.subscriptionNameLabel,
                l10n.subscriptionNameHint,
              ),
              const SizedBox(height: 12),
              _inputField(
                context,
                urlCtrl,
                l10n.subscriptionUrlLabel,
                l10n.subscriptionUrlHint,
                technical: true,
                suffix: PlatformBootstrap.isDesktop
                    ? null
                    : PlatformBootstrap.isTelevision
                    ? IconButton(
                        icon: Icon(
                          Icons.install_mobile_rounded,
                          color: AppTheme.accent(context),
                        ),
                        tooltip: l10n.tvReceiveTitle,
                        onPressed: () {
                          Navigator.pop(ctx);
                          unawaited(TvReceiveScreen.open(context));
                        },
                      )
                    : IconButton(
                        icon: Icon(
                          Icons.qr_code_scanner_rounded,
                          color: AppTheme.accent(context),
                        ),
                        tooltip: l10n.qrScanTitle,
                        onPressed: () async {
                          final raw = await QrScanScreen.scan(ctx);
                          if (raw == null || !ctx.mounted) return;
                          final tv = TvPairing.parse(raw);
                          if (tv != null) {
                            Navigator.pop(ctx);
                            if (context.mounted) {
                              await sendSubscriptionToTv(context, ref, tv);
                            }
                            return;
                          }
                          final uri = Uri.tryParse(raw);
                          if (uri != null &&
                              (uri.scheme == 'http' ||
                                  uri.scheme == 'https')) {
                            urlCtrl.text = raw;
                            setModalState(() => sheetError = null);
                          } else {
                            setModalState(
                              () => sheetError = l10n.qrNotSubscriptionLink,
                            );
                          }
                        },
                      ),
              ),
              const SizedBox(height: 12),
              _IdentityTile(
                identity: identity,
                onTap: () async {
                  final picked =
                      await _showIdentitySheet(ctx, initial: identity);
                  if (picked == null) return;
                  setModalState(() => identity = picked);
                },
              ),
              if (sheetError != null) ...[
                const SizedBox(height: 8),
                Text(
                  sheetError!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.red(context)),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accentContainerColor,
                    foregroundColor: onAccentContainerColor,
                  ),
                  onPressed: loading
                      ? null
                      : () async {
                          if (urlCtrl.text.trim().isEmpty) return;
                          setModalState(() {
                            loading = true;
                            sheetError = null;
                          });
                          try {
                            final typedName = nameCtrl.text.trim();
                            final sub = Subscription.create(
                              name: typedName.isEmpty
                                  ? Uri.parse(urlCtrl.text.trim()).host
                                  : typedName,
                              url: urlCtrl.text.trim(),
                              nameIsAuto: typedName.isEmpty,
                              fetchIdentity: identity,
                            );
                            await ref
                                .read(subscriptionsProvider.notifier)
                                .add(sub);
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                            if (!ctx.mounted) return;
                            setModalState(() {
                              loading = false;
                              sheetError = friendlyError(e, ctx);
                            });
                          }
                        },
                  child: loading
                      ? ShapeLoadingIndicator(
                          size: 20,
                          color: onAccentContainerColor,
                        )
                      : Text(
                          l10n.subscriptionsAddAndFetch,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputField(
    BuildContext context,
    TextEditingController ctrl,
    String label,
    String hint, {
    Widget? suffix,
    bool technical = false,
  }) {
    final textColor = AppTheme.text(context);
    final textLightColor = AppTheme.textLight(context);
    final cardColor = AppTheme.card(context);
    final accentColor = AppTheme.accent(context);

    return TextField(
      controller: ctrl,
      textDirection: technical ? technicalInputDirection : null,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintTextDirection: technical ? technicalInputDirection : null,
        suffixIcon: suffix,
        labelStyle: TextStyle(color: textLightColor),
        hintStyle: TextStyle(color: textLightColor.withValues(alpha: 0.5)),
        filled: true,
        fillColor: cardColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ExpressiveShape.large),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ExpressiveShape.large),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ExpressiveShape.large),
          borderSide: BorderSide(color: accentColor, width: 2),
        ),
      ),
    );
  }
}

class _SubsErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _SubsErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textColor = AppTheme.text(context);
    final textLightColor = AppTheme.textLight(context);
    final redColor = AppTheme.red(context);
    final accentColor = AppTheme.accent(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: redColor.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.errorSubscriptionTitle,
              style: Theme.of(context).textTheme
                  .emphasized(Theme.of(context).textTheme.titleMedium)
                  ?.copyWith(color: textColor),
            ),
            const SizedBox(height: 8),
            Text(
              friendlyError(error, context),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: textLightColor),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded, size: 18, color: accentColor),
              label: Text(
                l10n.subscriptionsRetry,
                style: TextStyle(color: accentColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _subFormatDate(BuildContext context, DateTime dt) =>
    timeAgo(AppLocalizations.of(context)!, dt);

class _SubAnnounceBanner extends ConsumerWidget {
  const _SubAnnounceBanner({required this.sub});

  final Subscription sub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(
      collapsedSubscriptionCardsProvider.select((m) => m[sub.id] ?? false),
    );
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            borderRadius: ExpressiveShape.radius(
              ExpressiveShape.medium,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.campaign_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  sub.announce!,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onTertiaryContainer,
                      ),
                  maxLines: collapsed ? 2 : null,
                  overflow: collapsed
                      ? TextOverflow.ellipsis
                      : TextOverflow.clip,
                ),
              ),
            ],
          ),
        ),
      );
  }
}

class _SubExpiredBanner extends StatelessWidget {
  const _SubExpiredBanner({required this.sub});

  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final redColor = AppTheme.red(context);
    final textLightColor = AppTheme.textLight(context);
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: redColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(ExpressiveShape.medium),
            border: Border.all(color: redColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.timer_off_rounded, size: 15, color: redColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sub.expiresAt != null
                          ? l10n.subscriptionsExpiredOn(
                              _subFormatDate(context, sub.expiresAt!),
                            )
                          : l10n.subscriptionsExpired,
                      style: Theme.of(context).textTheme
                          .emphasized(
                            Theme.of(context).textTheme.labelMedium,
                          )
                          ?.copyWith(color: redColor),
                    ),
                    Text(
                      l10n.subscriptionsExpiredHint,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: textLightColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
}

bool _subIsInsecureHttp(Subscription sub) =>
    sub.url.trim().toLowerCase().startsWith('http://');

Future<void> _subOpenProviderLink(BuildContext context, String url) async {
  final messenger = AppSnack.of(context);
  final l10n = AppLocalizations.of(context)!;
  final ok = await openExternalLink(url);
  if (ok) return;
  messenger.showSnackBar(
    SnackBar(content: Text(l10n.subscriptionsLinkOpenFailed)),
  );
}

String _subFormatExpiry(BuildContext context, DateTime dt) {
  final l10n = AppLocalizations.of(context)!;
  final diff = dt.difference(DateTime.now());
  if (diff.isNegative) return l10n.subscriptionsExpired;
  if (diff.inDays >= 1) return l10n.subscriptionsInDays(diff.inDays);
  if (diff.inHours >= 1) return l10n.subscriptionsInHours(diff.inHours);
  return l10n.subscriptionsSoon;
}

class _SubCardDetails extends ConsumerWidget {
  const _SubCardDetails({required this.sub, required this.onSwitchToHttps});

  final Subscription sub;

  final VoidCallback onSwitchToHttps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final collapsed = ref.watch(
      collapsedSubscriptionCardsProvider.select((m) => m[sub.id] ?? false),
    );
    final refreshError = ref.watch(
      subscriptionRefreshErrorsProvider.select((m) => m[sub.id]),
    );
    final hasRefreshError = refreshError != null;
    final profile = profileForSubscription(
      ref.watch(routingProfilesProvider).value ?? const [],
      sub.id,
    );
    final pct = sub.usagePercent;
    final showsUsage = sub.showsCard(SubscriptionCardElement.usage);
    final textColor = AppTheme.text(context);
    final textLightColor = AppTheme.textLight(context);
    final accentColor = AppTheme.accent(context);
    final redColor = AppTheme.red(context);
    final orangeColor = AppTheme.orange(context);
    return AnimatedCrossFade(
        duration: const Duration(milliseconds: 220),
        crossFadeState: collapsed
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
        firstChild: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sub.usedDisplay != null && showsUsage)
                // LtrBlock: в фарси Row зеркалился и выходило / 100 GiB 621.8 GiB
                LtrBlock(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        sub.usedDisplay!,
                        style: Theme.of(context).textTheme
                            .emphasized(
                              Theme.of(context).textTheme.headlineSmall,
                            )
                            ?.copyWith(color: textColor),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '/ ${sub.limitDisplay}',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: textLightColor),
                      ),
                    ],
                  ),
                ),
              if (_subIsInsecureHttp(sub))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(Icons.lock_open_rounded, size: 14, color: orangeColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l10n.subInsecureHttpWarning,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: orangeColor),
                        ),
                      ),
                      TextButton(
                        onPressed: onSwitchToHttps,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                        ),
                        child: Text(
                          l10n.subSwitchToHttps,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: accentColor),
                        ),
                      ),
                    ],
                  ),
                ),
              if (pct != null && showsUsage) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(ExpressiveShape.extraSmall),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 5,
                    backgroundColor: accentColor.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation(
                      pct > 0.9
                          ? redColor
                          : pct > 0.7
                          ? orangeColor
                          : accentColor,
                    ),
                  ),
                ),
              ],
              if (hasRefreshError) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: redColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(ExpressiveShape.small),
                    border: Border.all(
                      color: redColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 14,
                        color: redColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          refreshError,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: redColor),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (sub.showsCard(SubscriptionCardElement.meta)) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (sub.expiresAt != null) ...[
                    Icon(
                      Icons.timer_rounded,
                      size: 14,
                      color: sub.isExpired ? redColor : textLightColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      sub.isExpired
                          ? l10n.subscriptionsExpired
                          : _subFormatExpiry(context, sub.expiresAt!),
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(
                            color: sub.isExpired
                                ? redColor
                                : textLightColor,
                          ),
                    ),
                  ],
                  if (sub.lastUpdatedAt != null) ...[
                    const Spacer(),
                    Text(
                      _subFormatDate(context, sub.lastUpdatedAt!),
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: textLightColor),
                    ),
                  ],
                ],
              ),
              ],
              if (sub.showsCard(SubscriptionCardElement.actions)) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _CardChip(
                    icon: Icons.update_rounded,
                    label: sub.autoUpdate
                        ? l10n.subscriptionsIntervalShort(
                            sub.updateIntervalHours,
                          )
                        : l10n.subscriptionsOff,
                    accent: ExpressiveAccent.primary,
                    muted: !sub.autoUpdate,
                    onTap: () => showUpdateIntervalSheet(context, ref, sub),
                  ),
                  if (profile != null)
                    _CardChip(
                      icon: Icons.alt_route_rounded,
                      label: profile.name,
                      onTap: () {
                        ref
                            .read(expandedRoutingProfilesProvider.notifier)
                            .update((m) => {...m, profile.id: true});
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                routingScreen(focusProfileId: profile.id),
                          ),
                        );
                      },
                    ),
                  if (sub.webPageUrl != null)
                    _CardChip(
                      icon: Icons.open_in_new_rounded,
                      label: l10n.subscriptionsProviderPage,
                      accent: ExpressiveAccent.secondary,
                      onTap: () =>
                          _subOpenProviderLink(context, sub.webPageUrl!),
                    ),
                  if (sub.supportUrl != null)
                    _CardChip(
                      icon: Icons.support_agent_rounded,
                      label: l10n.subscriptionsSupport,
                      accent: ExpressiveAccent.tertiary,
                      onTap: () =>
                          _subOpenProviderLink(context, sub.supportUrl!),
                    ),
                ],
              ),
              ],
            ],
          ),
        ),
        secondChild: const SizedBox(height: 10),
      );
  }
}

Widget _subHeaderDragTarget({
  required bool isDesktop,
  required int listIndex,
  required Widget child,
}) {
  if (!isDesktop) {
    return Expanded(child: child);
  }
  return Expanded(
    child: ReorderableDelayedDragStartListener(
      index: listIndex,
      child: child,
    ),
  );
}

class _SubCardHeader extends ConsumerWidget {
  const _SubCardHeader({
    required this.sub,
    required this.listIndex,
    required this.onRefresh,
    required this.onShowMenu,
  });

  final Subscription sub;
  final int listIndex;
  final Future<void> Function() onRefresh;

  final VoidCallback onShowMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final collapsed = ref.watch(
      collapsedSubscriptionCardsProvider.select((m) => m[sub.id] ?? false),
    );
    final isRefreshing = ref.watch(
      subscriptionRefreshingIdsProvider.select((ids) => ids.contains(sub.id)),
    );
    final refreshError = ref.watch(
      subscriptionRefreshErrorsProvider.select((m) => m[sub.id]),
    );
    final hasRefreshError = refreshError != null;
    final textColor = AppTheme.text(context);
    final textLightColor = AppTheme.textLight(context);
    final accentColor = AppTheme.accent(context);
    final redColor = AppTheme.red(context);
    final isDesktop = PlatformBootstrap.isDesktop;
    return Padding(
        padding: EdgeInsets.fromLTRB(16, 14, isDesktop ? 16 : 8, 0),
        child: Row(
          children: [
            if (isDesktop) ...[
              ReorderableDragStartListener(
                index: listIndex,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    size: 22,
                    color: textLightColor,
                  ),
                ),
              ),
            ],
            _subHeaderDragTarget(
              isDesktop: isDesktop,
              listIndex: listIndex,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => ref
                        .read(collapsedSubscriptionCardsProvider.notifier)
                        .update((m) => {...m, sub.id: !collapsed}),
                    child: AnimatedRotation(
                      turns: collapsed ? -0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: textLightColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => ref
                          .read(
                            collapsedSubscriptionCardsProvider.notifier,
                          )
                          .update((m) => {...m, sub.id: !collapsed}),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            sub.name,
                            style: Theme.of(context).textTheme
                                .emphasized(
                                  Theme.of(context).textTheme.titleMedium,
                                )
                                ?.copyWith(color: textColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (sub.providerSubtitle != null)
                            Text(
                              sub.providerSubtitle!,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: textLightColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: isDesktop ? 12 : 4),
            IconButton(
              style: TvFocus.iconButtonStyle(
                context,
                color: hasRefreshError ? redColor : textLightColor,
              ),
              icon: isRefreshing
                  ? ShapeLoadingIndicator(size: 18, color: accentColor)
                  : const Icon(Icons.refresh_rounded, size: 20),
              onPressed: isRefreshing
                  ? null
                  : () async {
                      try {
                        await onRefresh();
                      } catch (e) {
                        if (!context.mounted) return;
                        AppSnack.of(context).showSnackBar(
                          SnackBar(
                            content: Text(friendlyError(e, context)),
                            backgroundColor: redColor,
                          ),
                        );
                      }
                    },
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
            ),
            SizedBox(width: isDesktop ? 10 : 4),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              style: TvFocus.iconButtonStyle(context, color: textLightColor),
              tooltip: l10n.subscriptionsCardMenu,
              onPressed: () => onShowMenu(),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
            ),
          ],
        ),
      );
  }
}

class _SubItem extends ConsumerStatefulWidget {
  final Subscription sub;
  final int listIndex;
  final VoidCallback onDelete;
  final Future<void> Function() onRefresh;

  const _SubItem({
    required this.sub,
    required this.listIndex,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  ConsumerState<_SubItem> createState() => _SubItemState();
}

class _SubItemState extends ConsumerState<_SubItem> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;

  Future<void> _switchToHttps() async {
    final httpsUrl = widget.sub.url
        .trim()
        .replaceFirst(RegExp(r'^http://', caseSensitive: false), 'https://');
    await ref
        .read(subscriptionsProvider.notifier)
        .editMeta(widget.sub.id, url: httpsUrl);
    try {
      await widget.onRefresh();
    } catch (e) {
      if (!mounted) return;
      AppSnack.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, context)),
          backgroundColor: AppTheme.red(context),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.sub;
    final cardColor = AppTheme.card(context);
    final cardTheme = resolveCardTheme(sub.cardThemeId);
    final cardRadius = BorderRadius.circular(ExpressiveShape.largeIncreased);

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: cardRadius,
          boxShadow: [
            BoxShadow(
              color:
                  Theme.of(context).colorScheme.shadow.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            if (!cardTheme.isPlain)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: cardRadius,
                  child: IgnorePointer(
                    child: cardTheme.background(context, veil: sub.cardVeil),
                  ),
                ),
              ),
            Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SubCardHeader(
              sub: sub,
              listIndex: widget.listIndex,
              onRefresh: widget.onRefresh,
              onShowMenu: () => _showCardMenu(context),
            ),
            if (sub.announce != null &&
                sub.showsCard(SubscriptionCardElement.announce))
              _SubAnnounceBanner(sub: sub),
            if (sub.isExpired) _SubExpiredBanner(sub: sub),
            _SubCardDetails(sub: sub, onSwitchToHttps: _switchToHttps),
              ],
            ),
          ],
        ),
      ),
    );
  }


  void _showEditDialog(BuildContext context) {
    final sub = widget.sub;
    final nameCtrl = TextEditingController(text: sub.name);
    final urlCtrl = TextEditingController(text: sub.url);
    var identity = sub.fetchIdentity;
    String? editError;

    final cardColor = AppTheme.card(context);
    final textColor = AppTheme.text(context);
    final textLightColor = AppTheme.textLight(context);
    final accentColor = AppTheme.accent(context);
    final accentContainerColor = AppTheme.accentContainer(context);
    final onAccentContainerColor = AppTheme.onAccentContainer(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget inputField(
            TextEditingController ctrl,
            String label,
            String hint, {
            int maxLines = 1,
            Widget? suffix,
            bool technical = false,
          }) {
            return TextField(
              controller: ctrl,
              maxLines: maxLines,
              textDirection: technical ? technicalInputDirection : null,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: textColor),
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                suffixIcon: suffix,
                labelStyle: TextStyle(color: textLightColor),
                hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: textLightColor.withValues(alpha: 0.5),
                    ),
                filled: true,
                fillColor: cardColor,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ExpressiveShape.large),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ExpressiveShape.large),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ExpressiveShape.large),
                  borderSide: BorderSide(color: accentColor, width: 2),
                ),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              20,
              24,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    l10n.subscriptionsEditSubscription,
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme
                        .emphasized(Theme.of(ctx).textTheme.titleLarge)
                        ?.copyWith(color: textColor),
                  ),
                ),
                const SizedBox(height: 20),
                inputField(nameCtrl, l10n.subscriptionNameLabel, sub.name),
                const SizedBox(height: 10),
                inputField(
                  urlCtrl,
                  l10n.subscriptionUrlLabel,
                  sub.url,
                  maxLines: 2,
                  technical: true,
                  suffix: IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: l10n.subscriptionsCopyUrl,
                    color: textLightColor,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: urlCtrl.text));
                      AppSnack.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.subscriptionsUrlCopied),
                          backgroundColor: textColor,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(ExpressiveShape.medium),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _IdentityTile(
                  identity: identity,
                  onTap: () async {
                    final picked =
                        await _showIdentitySheet(ctx, initial: identity);
                    if (picked == null) return;
                    setSheet(() => identity = picked);
                  },
                ),
                if (editError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    editError!,
                    style: Theme.of(ctx)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.red(ctx)),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: accentContainerColor,
                      foregroundColor: onAccentContainerColor,
                    ),
                    onPressed: () async {
                      final newName = nameCtrl.text.trim();
                      final newUrl = urlCtrl.text.trim();
                      if (newUrl.isEmpty) return;
                      try {
                        await ref
                            .read(subscriptionsProvider.notifier)
                            .editMeta(
                              sub.id,
                              name: newName.isNotEmpty ? newName : null,
                              resetName: newName.isEmpty,
                              url: newUrl,
                              fetchIdentity: identity,
                            );
                      } catch (e) {
                        // без catch ошибка уходит в zone, и Save молча ничего не делает
                        if (ctx.mounted) {
                          setSheet(() => editError = friendlyError(e, ctx));
                        }
                        return;
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text(
                      l10n.subscriptionsSave,
                      style: Theme.of(ctx)
                          .textTheme
                          .emphasized(Theme.of(ctx).textTheme.labelLarge),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCardMenu(BuildContext context) {
    final sub = widget.sub;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  sub.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(ctx).textTheme
                      .emphasized(Theme.of(ctx).textTheme.titleLarge)
                      ?.copyWith(color: AppTheme.text(ctx)),
                ),
              ),
              ExpressiveGroup(
                children: [
                  ExpressiveActionTile(
                    icon: Icons.edit_rounded,
                    title: l10n.subscriptionsEditSubscription,
                    accent: ExpressiveAccent.primary,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showEditDialog(context);
                    },
                  ),
                  ExpressiveActionTile(
                    icon: Icons.style_rounded,
                    title: l10n.subscriptionCardLookTitle,
                    accent: ExpressiveAccent.tertiary,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showCardLookSheet(context, sub);
                    },
                  ),
                  ExpressiveActionTile(
                    icon: Icons.qr_code_2_rounded,
                    title: l10n.subscriptionsShareButton,
                    accent: ExpressiveAccent.secondary,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showShareSheet(context);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ExpressiveGroup(
                children: [
                  ExpressiveActionTile(
                    icon: Icons.delete_outline_rounded,
                    title: l10n.subscriptionsDelete,
                    danger: true,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showDeleteConfirmation(context);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showShareSheet(BuildContext context) {
    final sub = widget.sub;
    final l10n = AppLocalizations.of(context)!;
    final qrKey = GlobalKey();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sub.name,
              style: Theme.of(ctx)
                  .textTheme
                  .emphasized(Theme.of(ctx).textTheme.titleMedium)
                  ?.copyWith(color: AppTheme.text(ctx)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            RepaintBoundary(
              key: qrKey,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: QrImageView(
                  data: sub.url,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              sub.url,
              textAlign: TextAlign.center,
              maxLines: 3,
              style: Theme.of(ctx)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textLight(ctx)),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentContainer(ctx),
                  foregroundColor: AppTheme.onAccentContainer(ctx),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ExpressiveShape.large),
                  ),
                ),
                icon: Icon(
                  Platform.isLinux
                      ? Icons.download_rounded
                      : Icons.share_rounded,
                  size: 18,
                ),
                label: Text(
                  Platform.isLinux
                      ? l10n.subscriptionsSave
                      : l10n.subscriptionsShareAction,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () => Platform.isLinux
                    ? _saveQr(ctx, qrKey)
                    : _shareQr(ctx, qrKey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List?> _qrPng(GlobalKey qrKey) async {
    final boundary =
        qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  String get _qrFileName {
    final safe = widget.sub.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    return 'keqdis_sub_${safe.isEmpty ? 'qr' : safe}.png';
  }

  // на Linux share_plus файлы не передаёт и кидает исключение, поэтому сохраняем
  Future<void> _saveQr(BuildContext ctx, GlobalKey qrKey) async {
    final l10n = AppLocalizations.of(context)!;
    String message;
    try {
      final png = await _qrPng(qrKey);
      if (png == null) return;
      final path = await AppFileDialogs.saveFile(
        fileName: _qrFileName,
        bytes: png,
        dialogTitle: l10n.subscriptionsQrSaveTitle,
        mimeType: 'image/png',
      );
      if (path == null) return;
      message = l10n.subscriptionsQrSaved(path);
    } catch (e) {
      if (!mounted) return;
      message = l10n.subscriptionsQrSaveFailed(
        e is FileDialogUnavailableException
            ? friendlyErrorDetailed(e, context)
            : friendlyError(e, context),
      );
    }
    if (ctx.mounted) Navigator.of(ctx).pop();
    if (!mounted) return;
    AppSnack.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _shareQr(BuildContext ctx, GlobalKey qrKey) async {
    final sub = widget.sub;
    final l10n = AppLocalizations.of(context)!;
    try {
      final png = await _qrPng(qrKey);
      if (png == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$_qrFileName');
      await file.writeAsBytes(png, flush: true);
      await SharePlus.instance.share(
        ShareParams(text: sub.url, files: [XFile(file.path)]),
      );
    } catch (e) {
      if (ctx.mounted) {
        AppSnack.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              l10n.subscriptionsShareFailed(friendlyError(e, ctx)),
            ),
          ),
        );
      }
    }
  }


  void _showDeleteConfirmation(BuildContext context) {
    final sub = widget.sub;
    final cardColor = AppTheme.card(context);
    final textColor = AppTheme.text(context);
    final textLightColor = AppTheme.textLight(context);
    final redColor = AppTheme.red(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: redColor, size: 28),
            const SizedBox(width: 12),
            Text(
              l10n.subscriptionsDeleteSubscription,
              style: Theme.of(ctx)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: textColor),
            ),
          ],
        ),
        content: Text(
          l10n.subscriptionsDeleteConfirm(sub.name),
          style: TextStyle(color: textLightColor, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l10n.subscriptionsCancel,
              style: TextStyle(color: textLightColor),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: redColor,
              foregroundColor: AppTheme.onRed(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ExpressiveShape.medium),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onDelete();
            },
            child: Text(
              l10n.subscriptionsDelete,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

}

class _CardThemePicker extends StatefulWidget {
  final String currentId;

  final ValueChanged<String> onSelect;

  final String subscriptionId;

  final bool inServers;
  final ValueChanged<bool> onInServersChanged;

  final CardVeil veil;

  const _CardThemePicker({
    required this.currentId,
    required this.onSelect,
    required this.subscriptionId,
    required this.inServers,
    required this.onInServersChanged,
    required this.veil,
  });

  @override
  State<_CardThemePicker> createState() => _CardThemePickerState();
}

class _CardThemePickerState extends State<_CardThemePicker> {
  String? _error;

  // гифка или видео перекодируются несколько секунд
  var _busy = false;

  final CarouselController _carousel = CarouselController();

  @override
  void dispose() {
    _carousel.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final l10n = AppLocalizations.of(context)!;
    final CardImageResult result;
    setState(() => _busy = true);
    try {
      result = await CardImageService.pick(subscriptionId: widget.subscriptionId);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorDetailed(e, context));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (result.cancelled || !mounted) return;

    final rejection = result.rejection;
    if (rejection != null) {
      setState(() => _error = switch (rejection) {
            CardImageRejection.aspect => l10n.cardImageRejectAspect,
            CardImageRejection.tooSmall =>
              l10n.cardImageRejectSmall(CardImageService.minWidth),
            CardImageRejection.tooLarge =>
              l10n.cardImageRejectLarge(CardImageService.maxWidth),
            CardImageRejection.unreadable => l10n.cardImageRejectUnreadable,
          });
      return;
    }
    setState(() => _error = null);
    widget.onSelect(result.theme!.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentId = widget.currentId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            l10n.subscriptionCardThemeTitle,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppTheme.textLight(context),
                ),
          ),
        ),
        SizedBox(
          height: _cardThemeCarouselHeight,
          child: HorizontalMouseScroll(
            controller: _carousel,
            child: CarouselView.weighted(
            controller: _carousel,
            flexWeights: const [3, 2, 1],
            consumeMaxWeight: true,
            itemSnapping: true,
            padding: const EdgeInsets.all(ExpressiveSpacing.extraSmall),
            shape: RoundedRectangleBorder(
              borderRadius: ExpressiveShape.radius(ExpressiveShape.extraLarge),
            ),
            backgroundColor: AppTheme.card(context),
            onTap: (index) {
              if (index == 0) {
                if (!_busy) unawaited(_pick());
                return;
              }
              final theme = kSubscriptionCardThemes[index - 1];
              widget.onSelect(theme.id == currentId ? '' : theme.id);
            },
            children: [
              _CustomImageSlot(themeId: currentId, busy: _busy),
              for (final theme in kSubscriptionCardThemes)
                _CardThemeSlot(
                  theme: theme,
                  veil: widget.veil,
                  selected: theme.id == currentId,
                ),
            ],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 8),
            child: Text(
              _error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.red(context)),
            ),
          ),
        if (resolveCardTheme(currentId).hasImage)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 4, right: 0),
              dense: true,
              value: widget.inServers,
              onChanged: widget.onInServersChanged,
              title: Text(
                l10n.subscriptionCardThemeInServers,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
      ],
    );
  }
}

const _cardThemeCarouselHeight = 88.0;

class _CarouselLabel extends StatelessWidget {
  const _CarouselLabel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ExpressiveSpacing.large,
        ),
        child: child,
      ),
    );
  }
}

class _CardThemeRing extends StatelessWidget {
  const _CardThemeRing();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: ExpressiveShape.radius(ExpressiveShape.extraLarge),
        border: Border.all(color: AppTheme.accent(context), width: 3),
      ),
    );
  }
}

class _CardThemeSlot extends StatelessWidget {
  const _CardThemeSlot({
    required this.theme,
    required this.veil,
    required this.selected,
  });

  final SubscriptionCardTheme theme;
  final CardVeil veil;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Stack(
      fit: StackFit.expand,
      children: [
        theme.background(context, veil: veil),
        if (theme.isPlain)
          _CarouselLabel(
            child: Text(
              l10n.subscriptionCardThemeNone,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textLight(context),
                  ),
            ),
          ),
        if (selected) const _CardThemeRing(),
      ],
    );
  }
}

class _CustomImageSlot extends StatelessWidget {
  final String themeId;
  final bool busy;

  const _CustomImageSlot({required this.themeId, required this.busy});

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accent(context);
    final selected = themeId.startsWith(SubscriptionCardTheme.filePrefix);

    return Stack(
      fit: StackFit.expand,
      children: [
          FutureBuilder<String?>(
            // ключ по id: иначе после смены картинки FutureBuilder показывал бы старую
            key: ValueKey(themeId),
            future: CardImageService.resolvePath(themeId),
            builder: (context, snapshot) {
              final path = snapshot.data;
              if (path == null) {
                return _CarouselLabel(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        selected
                            ? Icons.image_not_supported_rounded
                            : Icons.add_photo_alternate_rounded,
                        size: ExpressiveIconSize.large,
                        color: accent,
                      ),
                      const SizedBox(height: ExpressiveSpacing.extraSmall),
                      Text(
                        CardImageService.sizeHint,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppTheme.textLight(context),
                            ),
                      ),
                    ],
                  ),
                );
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  Image(
                    image: FileImage(File(
                      SubscriptionCardTheme.isVideoFile(path)
                          ? SubscriptionCardTheme.posterFor(path)
                          : path,
                    )),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  Align(
                    alignment: AlignmentDirectional.bottomStart,
                    child: Padding(
                      padding: const EdgeInsets.all(ExpressiveSpacing.small),
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.edit_rounded,
                        size: ExpressiveIconSize.medium,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        if (selected) const _CardThemeRing(),
        if (busy)
          const Center(child: ShapeLoadingIndicator(size: 40)),
      ],
    );
  }
}

class _CardChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ExpressiveAccent accent;

  final bool muted;

  const _CardChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = ExpressiveAccent.primary,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) => TvFocusHighlight(
        radius: ExpressiveShape.radius(ExpressiveShape.small),
        child: Builder(builder: _buildChip),
      );

  Widget _buildChip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = muted ? scheme.surfaceContainerHighest : accent.container(scheme);
    final fg = muted ? scheme.onSurfaceVariant : accent.onContainer(scheme);
    final shape = ExpressiveShape.radius(ExpressiveShape.small);

    return Material(
      color: bg,
      borderRadius: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

