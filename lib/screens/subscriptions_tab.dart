import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/smooth_scroll.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/subscription.dart';
import '../platform/platform_bootstrap.dart';
import '../providers/providers.dart';
import 'qr_scan_screen.dart';
import '../ui/responsive/desktop_page_layout.dart';
import '../utils/error_messages.dart';

class SubscriptionsTab extends ConsumerWidget {
  const SubscriptionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final subsAsync = ref.watch(subscriptionsProvider);

    // кэшируем цвета
    final bgColor = AppTheme.bg(context);
    final textColor = AppTheme.text(context);
    final accentColor = AppTheme.accent(context);
    final accentContainerColor = AppTheme.accentContainer(context);
    final onAccentContainerColor = AppTheme.onAccentContainer(context);

    return Scaffold(
          backgroundColor: bgColor,
          body: SafeArea(
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
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                  Expanded(
                    child: subsAsync.when(
                      skipLoadingOnReload: true,
                      loading: () => Center(
                        child: CircularProgressIndicator(color: accentColor),
                      ),
                      error: (e, _) => _SubsErrorView(
                        error: e,
                        onRetry: () => ref.invalidate(subscriptionsProvider),
                      ),
                      data: (subs) => subs.isEmpty
                          ? _emptySubsState(context)
                          : SmoothScroll(
                              builder: (context, controller) =>
                                  ReorderableListView.builder(
                                    scrollController: controller,
                                    physics: const ClampingScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      8,
                                      16,
                                      100,
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
                                    // onReorderItem уже корректирует newIndex за
                                    // удалённый элемент (движение вниз), поэтому
                                    // fromReorderableList: false — иначе вычтем -1 дважды.
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
                                      return AnimatedBuilder(
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
                                                  BorderRadius.circular(18),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: child,
                                      );
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
                ],
              ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'subscriptions_add_fab',
            backgroundColor: accentContainerColor,
            foregroundColor: onAccentContainerColor,
            icon: const Icon(Icons.add),
            label: Text(l10n.subscriptionsAddButton),
            onPressed: () => _showAddSubDialog(context, ref),
          ),
    );
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
            Icons.subscriptions_outlined,
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
            style: TextStyle(fontSize: 12, color: textLightColor),
          ),
        ],
      ),
    );
  }

  void _showAddSubDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    bool loading = false;
    // Ошибки (скан QR, загрузка подписки) — в самой шторке: snackbar был бы
    // скрыт за модальным барьером, а закрытие шторки теряло бы введённый URL.
    String? sheetError;

    final bgColor = AppTheme.bg(context);
    final textColor = AppTheme.text(context);
    final accentContainerColor = AppTheme.accentContainer(context);
    final onAccentContainerColor = AppTheme.onAccentContainer(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
              Text(
                l10n.subscriptionsAddSubscription,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
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
                // у mobile_scanner нет имплементации под Windows/Linux
                suffix: PlatformBootstrap.isDesktop
                    ? null
                    : IconButton(
                        icon: Icon(
                          Icons.qr_code_scanner,
                          color: AppTheme.accent(context),
                        ),
                        tooltip: l10n.qrScanTitle,
                        onPressed: () async {
                          final raw = await QrScanScreen.scan(ctx);
                          if (raw == null || !ctx.mounted) return;
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
              if (sheetError != null) ...[
                const SizedBox(height: 8),
                Text(
                  sheetError!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.red(context),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentContainerColor,
                    foregroundColor: onAccentContainerColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
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
                            final sub = Subscription.create(
                              name: nameCtrl.text.trim().isEmpty
                                  ? Uri.parse(urlCtrl.text.trim()).host
                                  : nameCtrl.text.trim(),
                              url: urlCtrl.text.trim(),
                            );
                            await ref
                                .read(subscriptionsProvider.notifier)
                                .add(sub);
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                            // Шторку не закрываем: ошибка показывается в ней
                            // самой, а введённые имя и URL сохраняются (как в
                            // шторке вставки серверов и диалоге редактирования).
                            if (!ctx.mounted) return;
                            setModalState(() {
                              loading = false;
                              sheetError = friendlyError(e, ctx);
                            });
                          }
                        },
                  child: loading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: onAccentContainerColor,
                          ),
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
  }) {
    final textColor = AppTheme.text(context);
    final textLightColor = AppTheme.textLight(context);
    final cardColor = AppTheme.card(context);
    final dividerColor = AppTheme.divider(context);
    final accentColor = AppTheme.accent(context);

    return TextField(
      controller: ctrl,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        labelStyle: TextStyle(color: textLightColor),
        hintStyle: TextStyle(color: textLightColor.withValues(alpha: 0.5)),
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: dividerColor, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: dividerColor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
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

  String _humanMessage(BuildContext context, Object e) {
    final l10n = AppLocalizations.of(context)!;
    final details = explainErrorLocalized(e, l10n);
    return '${details.title}\n${details.message}\n${l10n.errorActionLabel(details.action)}';
  }

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
              Icons.cloud_off_outlined,
              size: 48,
              color: redColor.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.errorSubscriptionTitle,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _humanMessage(context, error),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: textLightColor,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh, size: 18, color: accentColor),
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

  bool get _isInsecureHttp =>
      widget.sub.url.trim().toLowerCase().startsWith('http://');

  /// Точечный фикс для http-подписки: с 0.7.6 такие не обновляются
  /// (isSafeUrl принимает только https). Меняем схему и сразу пробуем обновить.
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
      ScaffoldMessenger.of(context).showSnackBar(
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
    final pct = sub.usagePercent;

    // кэшируем цвета, чтобы не дёргать Theme.of() на каждый вложенный виджет
    final cardColor = AppTheme.card(context);
    final textColor = AppTheme.text(context);
    final textLightColor = AppTheme.textLight(context);
    final accentColor = AppTheme.accent(context);
    final greenColor = AppTheme.green(context);
    final redColor = AppTheme.red(context);
    final orangeColor = AppTheme.orange(context);
    final isDesktop = PlatformBootstrap.isDesktop;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 14, isDesktop ? 16 : 8, 0),
              child: Row(
                children: [
                  if (isDesktop) ...[
                    ReorderableDragStartListener(
                      index: widget.listIndex,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.drag_handle,
                          size: 22,
                          color: textLightColor,
                        ),
                      ),
                    ),
                  ],
                  _buildHeaderDragTarget(
                    isDesktop: isDesktop,
                    listIndex: widget.listIndex,
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
                              Icons.expand_more,
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
                            child: Text(
                              sub.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: isDesktop ? 12 : 4),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    color: textLightColor,
                    onPressed: () => _showEditDialog(context),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                  SizedBox(width: isDesktop ? 10 : 4),
                  IconButton(
                    icon: isRefreshing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accentColor,
                            ),
                          )
                        : Icon(
                            Icons.refresh,
                            size: 20,
                            color: hasRefreshError ? redColor : textLightColor,
                          ),
                    onPressed: isRefreshing
                        ? null
                        : () async {
                            try {
                              await widget.onRefresh();
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
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
                  SizedBox(width: isDesktop ? 10 : 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: redColor,
                    onPressed: () => _showDeleteConfirmation(context),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: collapsed
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sub.url,
                      style: TextStyle(fontSize: 11, color: textLightColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_isInsecureHttp)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Icon(Icons.lock_open, size: 14, color: orangeColor),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                l10n.subInsecureHttpWarning,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: orangeColor,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _switchToHttps,
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              child: Text(
                                l10n.subSwitchToHttps,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: accentColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.data_usage, size: 14, color: textLightColor),
                        const SizedBox(width: 4),
                        Text(
                          sub.usageLabel,
                          style: TextStyle(fontSize: 12, color: textLightColor),
                        ),
                        if (sub.lastUpdatedAt != null) ...[
                          const Spacer(),
                          Text(
                            _formatDate(sub.lastUpdatedAt!),
                            style: TextStyle(
                              fontSize: 11,
                              color: textLightColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (pct != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
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
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: redColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 14,
                              color: redColor,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                refreshError,
                                style: TextStyle(fontSize: 11, color: redColor),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.update, size: 14, color: textLightColor),
                        const SizedBox(width: 4),
                        Text(
                          l10n.subscriptionsAutoUpdate,
                          style: TextStyle(fontSize: 12, color: textLightColor),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => ref
                              .read(subscriptionsProvider.notifier)
                              .toggleAutoUpdate(sub.id),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: sub.autoUpdate
                                  ? greenColor.withValues(alpha: 0.2)
                                  : textLightColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              sub.autoUpdate
                                  ? l10n.subscriptionsOn
                                  : l10n.subscriptionsOff,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: sub.autoUpdate
                                    ? greenColor
                                    : textLightColor,
                              ),
                            ),
                          ),
                        ),
                        if (sub.autoUpdate) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _showIntervalPicker(context, sub),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    l10n.subscriptionsCurrentInterval(
                                      sub.updateIntervalHours,
                                    ),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: accentColor,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(
                                    Icons.edit,
                                    size: 11,
                                    color: accentColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (sub.expiresAt != null) ...[
                          const Spacer(),
                          Icon(
                            Icons.timer_outlined,
                            size: 13,
                            color: sub.isExpired ? redColor : textLightColor,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            sub.isExpired
                                ? l10n.subscriptionsExpired
                                : _formatExpiry(sub.expiresAt!),
                            style: TextStyle(
                              fontSize: 11,
                              color: sub.isExpired ? redColor : textLightColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              secondChild: const SizedBox(height: 10),
            ),
          ],
        ),
      ),
    );
  }

  // mobile: вся карточка тащится через ReorderableDelayedDragStartListener
  // desktop: ручка для мыши + long-press на заголовке, как на мобильном
  Widget _buildHeaderDragTarget({
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

  void _showEditDialog(BuildContext context) {
    final sub = widget.sub;
    final nameCtrl = TextEditingController(text: sub.name);
    final urlCtrl = TextEditingController(text: sub.url);
    // Ошибка сохранения (например, дубликат URL) — показываем в самой шторке:
    // snackbar был бы скрыт за модальным барьером.
    String? editError;

    final bgColor = AppTheme.bg(context);
    final cardColor = AppTheme.card(context);
    final textColor = AppTheme.text(context);
    final textLightColor = AppTheme.textLight(context);
    final dividerColor = AppTheme.divider(context);
    final accentColor = AppTheme.accent(context);
    final accentContainerColor = AppTheme.accentContainer(context);
    final onAccentContainerColor = AppTheme.onAccentContainer(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget inputField(
            TextEditingController ctrl,
            String label,
            String hint, {
            int maxLines = 1,
          }) {
            return TextField(
              controller: ctrl,
              maxLines: maxLines,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                labelStyle: TextStyle(color: textLightColor),
                hintStyle: TextStyle(
                  color: textLightColor.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
                filled: true,
                fillColor: cardColor,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: dividerColor, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: dividerColor, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
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
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: textLightColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.subscriptionsEditSubscription,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 16),
                inputField(nameCtrl, l10n.subscriptionNameLabel, sub.name),
                const SizedBox(height: 10),
                inputField(urlCtrl, l10n.subscriptionUrlLabel, sub.url, maxLines: 2),
                if (editError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    editError!,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.red(ctx),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(color: dividerColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.copy, size: 16),
                        label: Text(
                          l10n.subscriptionsCopyUrl,
                          style: const TextStyle(fontSize: 13),
                        ),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: sub.url));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.subscriptionsUrlCopied),
                              backgroundColor: textColor,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ReorderButton(
                      icon: Icons.keyboard_arrow_up,
                      tooltip: l10n.subscriptionsMoveUp,
                      onTap: () {
                        final subs =
                            ref.read(subscriptionsProvider).value ?? [];
                        final idx = subs.indexWhere((s) => s.id == sub.id);
                        if (idx > 0) {
                          ref.read(subscriptionsProvider.notifier).reorder(
                                idx,
                                idx - 1,
                                fromReorderableList: false,
                              );
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    _ReorderButton(
                      icon: Icons.keyboard_arrow_down,
                      tooltip: l10n.subscriptionsMoveDown,
                      onTap: () {
                        final subs =
                            ref.read(subscriptionsProvider).value ?? [];
                        final idx = subs.indexWhere((s) => s.id == sub.id);
                        if (idx < subs.length - 1) {
                          // fromReorderableList: false обязателен — иначе
                          // поправка «-1 при движении вниз» превращала
                          // idx+1 обратно в idx, и кнопка была no-op.
                          ref.read(subscriptionsProvider.notifier).reorder(
                                idx,
                                idx + 1,
                                fromReorderableList: false,
                              );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: dividerColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.qr_code_2, size: 18),
                    label: Text(
                      l10n.subscriptionsShareButton,
                      style: const TextStyle(fontSize: 13),
                    ),
                    onPressed: () => _showShareSheet(context),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentContainerColor,
                      foregroundColor: onAccentContainerColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
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
                              url: newUrl,
                            );
                      } catch (e) {
                        // например, дубликат URL: без catch ошибка молча уходит
                        // в zone, и диалог «не реагирует» на Save
                        if (ctx.mounted) {
                          setSheet(() => editError = friendlyError(e, ctx));
                        }
                        return;
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text(
                      l10n.subscriptionsSave,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
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

  /// Лист «Поделиться»: показывает QR подписки + ссылку и шарит их через
  /// системный share (QR как PNG-файл + текст ссылки) — можно кинуть другу.
  void _showShareSheet(BuildContext context) {
    final sub = widget.sub;
    final l10n = AppLocalizations.of(context)!;
    final qrKey = GlobalKey();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textLight(ctx).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              sub.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.text(ctx),
              ),
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
              style: TextStyle(fontSize: 11, color: AppTheme.textLight(ctx)),
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
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.share, size: 18),
                label: Text(
                  l10n.subscriptionsShareAction,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () => _shareQr(ctx, qrKey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareQr(BuildContext ctx, GlobalKey qrKey) async {
    final sub = widget.sub;
    final l10n = AppLocalizations.of(context)!;
    try {
      final boundary =
          qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final dir = await getTemporaryDirectory();
      final safe = sub.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
      final file = File(
        '${dir.path}/keqdis_sub_${safe.isEmpty ? 'qr' : safe}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(
        ShareParams(text: sub.url, files: [XFile(file.path)]),
      );
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              l10n.subscriptionsShareFailed(friendlyError(e, ctx)),
            ),
          ),
        );
      }
    }
  }

  void _showIntervalPicker(BuildContext context, Subscription sub) {
    const options = [1, 3, 6, 12, 24, 48, 72];
    final bgColor = AppTheme.bg(context);
    final textLightColor = AppTheme.textLight(context);
    final textColor = AppTheme.text(context);
    final accentColor = AppTheme.accent(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final maxHeight = MediaQuery.sizeOf(ctx).height * 0.85;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: textLightColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.subscriptionsAutoUpdateInterval,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.subscriptionsCurrentInterval(sub.updateIntervalHours),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: textLightColor),
                ),
                const SizedBox(height: 8),
                ...options.map(
                  (h) => ListTile(
                    title: Text(
                      h == 1
                          ? l10n.subscriptionsEveryHour
                          : h < 24
                          ? l10n.subscriptionsEveryHours(h)
                          : h == 24
                          ? l10n.subscriptionsEveryDay
                          : l10n.subscriptionsEveryDays(h ~/ 24),
                      style: TextStyle(
                        color: textColor,
                        fontWeight: h == sub.updateIntervalHours
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: h == sub.updateIntervalHours
                        ? Icon(Icons.check, color: accentColor)
                        : null,
                    onTap: () {
                      ref
                          .read(subscriptionsProvider.notifier)
                          .updateInterval(sub.id, h);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: redColor, size: 28),
            const SizedBox(width: 12),
            Text(
              l10n.subscriptionsDeleteSubscription,
              style: TextStyle(color: textColor, fontSize: 18),
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
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
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

  String _formatDate(DateTime dt) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return l10n.subscriptionsJustNow;
    if (diff.inHours < 1) return l10n.subscriptionsMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l10n.subscriptionsHoursAgo(diff.inHours);
    return l10n.subscriptionsDaysAgo(diff.inDays);
  }

  String _formatExpiry(DateTime dt) {
    final l10n = AppLocalizations.of(context)!;
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return l10n.subscriptionsExpired;
    if (diff.inDays >= 1) return l10n.subscriptionsInDays(diff.inDays);
    if (diff.inHours >= 1) return l10n.subscriptionsInHours(diff.inHours);
    return l10n.subscriptionsSoon;
  }
}

class _ReorderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ReorderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = AppTheme.card(context);
    final textColor = AppTheme.text(context);
    final dividerColor = AppTheme.divider(context);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: dividerColor, width: 1.5),
          ),
          child: Icon(icon, size: 22, color: textColor),
        ),
      ),
    );
  }
}
