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
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/expressive_elements.dart';
import 'package:keqdroid/shared/ui/expressive_button_group.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';
import 'package:keqdroid/shared/ui/shape_loading_indicator.dart';
import 'package:keqdroid/shared/ui/smooth_scroll.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/subscription.dart';
import '../models/subscription_card_layout.dart';
import '../models/subscription_card_theme.dart';
import '../services/card_image_service.dart';
import '../platform/platform_bootstrap.dart';
import '../providers/providers.dart';
import 'qr_scan_screen.dart';
import '../ui/responsive/desktop_page_layout.dart';
import '../utils/bidi.dart';
import '../utils/error_messages.dart';
import '../utils/external_link.dart';
import '../utils/identity_presets.dart';

part 'subscriptions/card_look_sheet.dart';
part 'subscriptions/identity_sheet.dart';

class SubscriptionsTab extends ConsumerWidget {
  const SubscriptionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final subsAsync = ref.watch(subscriptionsProvider);

    // кэшируем цвета
    final bgColor = AppTheme.bg(context);
    final textColor = AppTheme.text(context);
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
                      // Заголовок экрана — headline: та же роль, что и на
                      // остальных вкладках, иначе иерархия страниц разъезжается.
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
                                                  BorderRadius.circular(ExpressiveShape.largeIncreased),
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
            icon: const Icon(Icons.add_rounded),
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
    // Идентичность задаётся ДО первой загрузки: панель с привязкой по HWID
    // считает устройство уже на ней, и «добавить, а потом подменить» стоило бы
    // лишнего слота привязки.
    var identity = SubscriptionFetchIdentity.empty;
    bool loading = false;
    // Ошибки (скан QR, загрузка подписки) — в самой шторке: snackbar был бы
    // скрыт за модальным барьером, а закрытие шторки теряло бы введённый URL.
    String? sheetError;

    final textColor = AppTheme.text(context);
    final accentContainerColor = AppTheme.accentContainer(context);
    final onAccentContainerColor = AppTheme.onAccentContainer(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // Настоящая ручка вместо нарисованной: прежняя была просто Container
      // внутри содержимого — выглядела как ручка, но тянуть за неё было
      // нельзя, и шторка закрывалась только тапом мимо неё.
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
                // у mobile_scanner нет имплементации под Windows/Linux
                suffix: PlatformBootstrap.isDesktop
                    ? null
                    : IconButton(
                        icon: Icon(
                          Icons.qr_code_scanner_rounded,
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
                // Как и в шторке редактирования: FilledButton вместо
                // ElevatedButton, форма-пилюля из темы.
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
                            // Поле имени пустое — подставляем хост, но помечаем
                            // имя автоматическим: придёт profile-title от
                            // панели, и он его заменит.
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
  }) {
    final textColor = AppTheme.text(context);
    final textLightColor = AppTheme.textLight(context);
    final cardColor = AppTheme.card(context);
    final accentColor = AppTheme.accent(context);

    return TextField(
      controller: ctrl,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        labelStyle: TextStyle(color: textLightColor),
        hintStyle: TextStyle(color: textLightColor.withValues(alpha: 0.5)),
        // Заливка ИЛИ обводка: у filled-поля рамки нет, её роль играет сама
        // заливка. Обводка остаётся индикатором фокуса.
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
    final redColor = AppTheme.red(context);
    final orangeColor = AppTheme.orange(context);
    final isDesktop = PlatformBootstrap.isDesktop;

    final cardTheme = resolveCardTheme(sub.cardThemeId);
    final cardRadius = BorderRadius.circular(ExpressiveShape.largeIncreased);

    // Состав карточки — настройка подписки (редактор оформления). Убрать можно
    // только оформление и факты второго плана: предупреждения о просроченной
    // подписке, о `http` и о неудачном обновлении рисуются всегда, что бы ни
    // было выбрано, — спрятанная проблема выглядит как её отсутствие.
    final showsUsage = sub.showsCard(SubscriptionCardElement.usage);

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: cardRadius,
          // Нейтральная тень как высота — см. то же в server_groups.
          boxShadow: [
            BoxShadow(
              color:
                  Theme.of(context).colorScheme.shadow.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        // Подложка темы обрезается формой карточки и лежит ПОД содержимым,
        // не перехватывая нажатия: карточка целиком остаётся кликабельной.
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
            Padding(
              padding: EdgeInsets.fromLTRB(16, 14, isDesktop ? 16 : 8, 0),
              child: Row(
                children: [
                  if (isDesktop) ...[
                    ReorderableDragStartListener(
                      index: widget.listIndex,
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
                                // Чей это сервис на самом деле — показываем,
                                // только если имя карточки задано своё и от
                                // названия провайдера отличается.
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
                    icon: isRefreshing
                        ? ShapeLoadingIndicator(size: 18, color: accentColor)
                        : Icon(
                            Icons.refresh_rounded,
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
                  SizedBox(width: isDesktop ? 10 : 4),
                  // Правка, «поделиться» и удаление ушли под одну кнопку.
                  //
                  // Три иконки в шапке конкурировали с именем и делили место с
                  // ним же, а нужны они редко — в отличие от обновления, оно
                  // осталось снаружи. Удаление заодно перестало стоять в один
                  // ряд с безобидной правкой.
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    color: textLightColor,
                    tooltip: l10n.subscriptionsCardMenu,
                    onPressed: () => _showCardMenu(context),
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
            // Истёкшая подписка — всегда на виду, вне сворачиваемой части:
            // провайдер о конце срока клиенту не сообщает, а панель обычно
            // продолжает отдавать те же серверы, поэтому раньше «просто не
            // обновляется» выглядело как баг приложения.
            // Объявление провайдера: техработы, смена адреса и подобное.
            // Роль tertiary — «обратите внимание», ровно её назначение; красный
            // здесь был бы неверен, это не ошибка. Свёрнутая карточка режет
            // текст до двух строк, раскрытая показывает целиком — отдельного
            // органа управления заводить не пришлось, чевron уже есть.
            if (sub.announce != null &&
                sub.showsCard(SubscriptionCardElement.announce))
              Padding(
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
              ),
            if (sub.isExpired)
              Padding(
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
                                      _formatDate(sub.expiresAt!),
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
                    // ЯКОРЬ карточки: сколько потрачено, крупно.
                    //
                    // Раньше всё содержимое было набрано одним мелким кеглем —
                    // URL, трафик, срок, интервал, — и глазу не за что было
                    // зацепиться, приходилось читать подряд. Размер здесь и
                    // делает иерархию: у M3E это один из пяти механизмов
                    // наравне с цветом и формой.
                    if (sub.usedDisplay != null && showsUsage)
                      // «Потрачено / лимит» — одно значение из двух виджетов, и
                      // порядок в нём держит LtrBlock, а не изолят: в персидской
                      // локали Row зеркалился, и вместо `621.8 GiB / 100 GiB`
                      // на экране получалось `/ 100 GiB 621.8 GiB`. Изолят чинил
                      // каждый кусок по отдельности и на порядок детей не влиял.
                      LtrBlock(
                        child: Row(
                          // Row обязан обжимать содержимое: растянутый на всю
                          // ширину, он утащил бы блок к левому краю, а по-
                          // персидски он должен стоять у правого.
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
                    if (_isInsecureHttp)
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
                              onPressed: _switchToHttps,
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
                    // МЕТА: факты второго плана — одной тихой строкой.
                    //
                    // Раньше срок годности стоял в ряду с чипами управления, а
                    // «когда обновлялось» — этажом выше рядом с трафиком. Два
                    // однородных факта в разных местах и разных ролях; теперь
                    // они вместе и оба `labelMedium`.
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
                                : _formatExpiry(sub.expiresAt!),
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
                            _formatDate(sub.lastUpdatedAt!),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: textLightColor),
                          ),
                        ],
                      ],
                    ),
                    ],
                    // УПРАВЛЕНИЕ: чипы одного вида в одном ряду.
                    //
                    // Автообновление было тремя элементами — подпись, значок
                    // ON/OFF и интервал с карандашом — ради одной настройки, и
                    // переключалось скрытым тапом по значку. Теперь это один
                    // чип: он же показывает состояние, он же открывает выбор,
                    // где «Выключить» стоит первым пунктом.
                    if (sub.showsCard(SubscriptionCardElement.actions)) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        // Настройка приложения — primary; ссылки провайдера —
                        // secondary и tertiary. Три роли, три разных чипа: ряд
                        // перестаёт быть однородной полосой.
                        _CardChip(
                          icon: Icons.update_rounded,
                          label: sub.autoUpdate
                              ? l10n.subscriptionsIntervalShort(
                                  sub.updateIntervalHours,
                                )
                              : l10n.subscriptionsOff,
                          accent: ExpressiveAccent.primary,
                          muted: !sub.autoUpdate,
                          onTap: () => _showIntervalPicker(context, sub),
                        ),
                        if (sub.webPageUrl != null)
                          _CardChip(
                            icon: Icons.open_in_new_rounded,
                            label: l10n.subscriptionsProviderPage,
                            accent: ExpressiveAccent.secondary,
                            onTap: () =>
                                _openProviderLink(context, sub.webPageUrl!),
                          ),
                        if (sub.supportUrl != null)
                          _CardChip(
                            icon: Icons.support_agent_rounded,
                            label: l10n.subscriptionsSupport,
                            accent: ExpressiveAccent.tertiary,
                            onTap: () =>
                                _openProviderLink(context, sub.supportUrl!),
                          ),
                      ],
                    ),
                    ],
                  ],
                ),
              ),
              secondChild: const SizedBox(height: 10),
            ),
              ],
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
    var identity = sub.fetchIdentity;
    // Ошибка сохранения (например, дубликат URL) — показываем в самой шторке:
    // snackbar был бы скрыт за модальным барьером.
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
      // Настоящая ручка вместо нарисованной: прежняя была просто Container
      // внутри содержимого — выглядела как ручка, но тянуть за неё было
      // нельзя, и шторка закрывалась только тапом мимо неё.
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget inputField(
            TextEditingController ctrl,
            String label,
            String hint, {
            int maxLines = 1,
            Widget? suffix,
          }) {
            return TextField(
              controller: ctrl,
              maxLines: maxLines,
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
                // Заливка ИЛИ обводка, а не то и другое разом: у M3 filled-поле
                // рамки не носит, её роль там играет сама заливка. Обводка
                // остаётся только на фокусе — как индикатор, а не как контур.
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
                // Заголовок как в остальных шторках: по центру и в усиленном
                // варианте роли — раньше он один был выключен влево и без веса.
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
                // Копирование — микро-кнопкой в самом поле, а не отдельной
                // широкой кнопкой ниже: действие относится к этой строке, и
                // рядом с ней ему и место. Заодно шторка теряет целый ряд.
                inputField(
                  urlCtrl,
                  l10n.subscriptionUrlLabel,
                  sub.url,
                  maxLines: 2,
                  suffix: IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: l10n.subscriptionsCopyUrl,
                    color: textLightColor,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: urlCtrl.text));
                      ScaffoldMessenger.of(context).showSnackBar(
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
                // Оформления здесь нет намеренно: вход в него — пункт «Вид
                // карточки» в меню подписки, и второй вход внутри редактора был
                // лишним. Настройки оформления применяются сразу, а редактор
                // живёт под кнопкой «Сохранить» — держать их в одном списке
                // значит показывать рядом две кнопки с разными правилами.
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
                // Ни «поделиться», ни стрелок перестановки здесь нет: делиться
                // предлагает меню карточки, а порядок задаётся перетаскиванием
                // самой карточки. Дублировать их в редакторе — превращать его
                // в панель со всем сразу; здесь правят подписку, и только.
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  // Главное действие — FilledButton, а не ElevatedButton:
                  // у M3 приподнятая кнопка с тенью это отдельная, куда более
                  // скромная роль. Форма снова из темы.
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
                              // Очистили поле — просим вернуть автоматическое
                              // имя, а не «оставить как было».
                              resetName: newName.isEmpty,
                              url: newUrl,
                              fetchIdentity: identity,
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

  /// Меню карточки подписки.
  ///
  /// Шторка, а не `PopupMenuButton`: все прочие меню действий в приложении
  /// (долгое нажатие на сервер, добавление конфигов, сортировка) уже сделаны
  /// этим компонентом, и всплывающее меню оставалось единственным местом с
  /// чужой анатомией — оттого и выглядело «обычным».
  void _showCardMenu(BuildContext context) {
    final sub = widget.sub;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        // Прокрутка, а не просто Column: пунктов в меню уже пять, и на
        // невысоком экране (или при крупном системном шрифте) неподвижная
        // колонка рвётся по нижнему краю вместо того, чтобы прокрутиться.
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
                  // Оформление — рядом с правкой, а не внутри неё: менять вид
                  // карточки хочется чаще, чем её адрес, и идти за этим в
                  // форму с полем URL незачем.
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
              // Удаление — отдельной группой и в роли error, как в меню сервера.
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

  /// Открывает ссылку провайдера, а если открыть нечем — говорит об этом,
  /// вместо того чтобы молча ничего не сделать.
  Future<void> _openProviderLink(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final ok = await openExternalLink(url);
    if (ok) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.subscriptionsLinkOpenFailed)),
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
                icon: const Icon(Icons.share_rounded, size: 18),
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
    final textLightColor = AppTheme.textLight(context);
    final textColor = AppTheme.text(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final maxHeight = MediaQuery.sizeOf(ctx).height * 0.85;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                Text(
                  l10n.subscriptionsAutoUpdateInterval,
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx)
                      .textTheme
                      .emphasized(Theme.of(ctx).textTheme.titleLarge)
                      ?.copyWith(color: textColor),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.subscriptionsCurrentInterval(sub.updateIntervalHours),
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: textLightColor),
                ),
                const SizedBox(height: 12),
                // Это выбор, а не список действий: текущий интервал виден
                // заливкой сегмента, а не только жирной подписью с галочкой.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ExpressiveGroup(
                    children: [
                      // Выключение живёт здесь, а не отдельным значком в
                      // карточке: это одна настройка, и орган управления у неё
                      // должен быть один.
                      ExpressiveActionTile(
                        icon: Icons.update_disabled_rounded,
                        title: l10n.subscriptionsAutoUpdateOff,
                        selected: !sub.autoUpdate,
                        onTap: () {
                          ref
                              .read(subscriptionsProvider.notifier)
                              .setUpdateSchedule(sub.id, autoUpdate: false);
                          Navigator.pop(ctx);
                        },
                      ),
                      for (final h in options)
                        ExpressiveActionTile(
                          icon: h < 24
                              ? Icons.schedule_rounded
                              : Icons.calendar_today_rounded,
                          title: h == 1
                              ? l10n.subscriptionsEveryHour
                              : h < 24
                              ? l10n.subscriptionsEveryHours(h)
                              : h == 24
                              ? l10n.subscriptionsEveryDay
                              : l10n.subscriptionsEveryDays(h ~/ 24),
                          selected:
                              sub.autoUpdate && h == sub.updateIntervalHours,
                          onTap: () {
                            // Выбор интервала означает «включить и поставить
                            // его» — одной операцией, а не двумя подряд.
                            ref
                                .read(subscriptionsProvider.notifier)
                                .setUpdateSchedule(
                                  sub.id,
                                  autoUpdate: true,
                                  hours: h,
                                );
                            Navigator.pop(ctx);
                          },
                        ),
                    ],
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
              foregroundColor: Colors.white,
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

/// Ссылка провайдера в карточке подписки.
///
/// Ровно та же анатомия, что у чипа интервала рядом: тональная заливка,
/// радиус `small`, роль `label`. Отличается только тем, что несёт иконку и
/// рипл — рипл здесь и говорит, что по чипу жмут.
/// Чип в карточке подписки.
///
/// Цвет несёт смысл, а не украшает: пока все чипы сидели на одном акценте с
/// одинаковой альфой, ряд читался как сплошная полоса и глаз в ней терялся.
/// Роли разведены по назначению — `primary` у настройки самого приложения,
/// `secondary` и `tertiary` у ссылок провайдера, — то есть тем же способом,
/// которым раскрашены иконки в настройках.
/// Слайдер оформления карточки в редакторе подписки.
///
/// Образцы — та же самая подложка, что рисуется на карточке, только маленькая:
/// превью, нарисованное отдельно, рано или поздно разойдётся с настоящим видом.
class _CardThemePicker extends StatefulWidget {
  final String currentId;

  /// Выбранная тема целиком, а не «переключи»: снятие темы повторным тапом —
  /// дело самого слайдера, а выбор своей картинки её всегда включает.
  final ValueChanged<String> onSelect;

  /// Нужен, чтобы назвать файл картинки: у каждой подписки своя, и они не
  /// должны затирать друг друга.
  final String subscriptionId;

  /// Показывать ли подложку и в шапке группы серверов.
  final bool inServers;
  final ValueChanged<bool> onInServersChanged;

  /// Затемнение, с которым рисуются образцы: то же, что у самой карточки.
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
  /// Почему картинку не взяли — под самим слайдером.
  String? _error;

  Future<void> _pick() async {
    final l10n = AppLocalizations.of(context)!;
    final CardImageResult result;
    try {
      result = await CardImageService.pick(subscriptionId: widget.subscriptionId);
    } catch (e) {
      // Системный выбор файла может не открыться вовсе (Linux без портала и
      // без zenity) — причину показываем там же, где и отказ по картинке.
      if (mounted) setState(() => _error = friendlyErrorDetailed(e, context));
      return;
    }
    if (result.cancelled || !mounted) return;

    final rejection = result.rejection;
    if (rejection != null) {
      // Прямо в шторке, а не снекбаром: снекбар рисует Scaffold под модальной
      // шторкой, и объяснение осталось бы за ней — со стороны выглядело бы,
      // что нажатие вообще ничего не сделало.
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
        // Карусель M3, а не полоса одинаковых миниатюр.
        //
        // Раскладка multi-browse: крупный элемент, средний и мелкий, и они
        // меняют размер по мере прокрутки — выбор картинки этим и живёт, крупный
        // элемент показывает её так, как она ляжет на карточку, а прежние
        // одинаковые 92 px не показывали толком ничего.
        //
        // Числа из измерений спеки: радиус элемента 28dp, между элементами 8dp
        // (по 4 вокруг каждого — это и есть умолчание `padding`).
        SizedBox(
          height: _cardThemeCarouselHeight,
          child: CarouselView.weighted(
            flexWeights: const [3, 2, 1],
            consumeMaxWeight: true,
            itemSnapping: true,
            padding: const EdgeInsets.all(ExpressiveSpacing.extraSmall),
            shape: RoundedRectangleBorder(
              borderRadius: ExpressiveShape.radius(ExpressiveShape.extraLarge),
            ),
            backgroundColor: AppTheme.card(context),
            // Первым элементом — «своя картинка». Раньше там стояла пустая
            // карточка «без темы»: место занимала, а делать с ней было нечего.
            // Отказаться от темы можно, выбрав её же повторно.
            onTap: (index) {
              if (index == 0) {
                unawaited(_pick());
                return;
              }
              final theme = kSubscriptionCardThemes[index - 1];
              // Повторный тап по выбранной теме снимает её.
              widget.onSelect(theme.id == currentId ? '' : theme.id);
            },
            children: [
              _CustomImageSlot(themeId: currentId),
              for (final theme in kSubscriptionCardThemes)
                _CardThemeSlot(
                  theme: theme,
                  veil: widget.veil,
                  selected: theme.id == currentId,
                ),
            ],
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
        // Тумблер появляется только когда выбрана КАРТИНКА: он и обещает
        // ровно её («картинка заполнит и шапку группы»), а у палитры
        // переносить нечего — цвета уезжают в группу и без него. Пока условием
        // было «тема выбрана», включённый тумблер на палитре растил шапку
        // группы на пустую полосу.
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
              subtitle: Text(
                l10n.subscriptionCardThemeInServersHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textLight(context),
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Первый слот слайдера: своя картинка.
///
/// Пока не выбрана — кнопка с плюсом и допустимым размером: требование к
/// картинке читается ДО того, как файл выбран и отвергнут. Выбрана — её же
/// миниатюра.
///
/// Путь к файлу слот достаёт сам по id темы, а не получает сверху: иначе его
/// пришлось бы асинхронно резолвить при открытии шторки и протаскивать через
/// весь редактор ради одной картинки.
/// Высота карусели тем: элемент плюс отступы `padding` сверху и снизу.
///
/// Крупный элемент карусели заметно шире прежних 92 px, и низкая полоса рядом с
/// ним читалась бы обрезком: пропорции элемента должны напоминать саму карточку.
const _cardThemeCarouselHeight = 88.0;

/// Содержимое элемента карусели, которое не должно ездить при прокрутке.
///
/// Элемент карусели непрерывно меняет ширину — в этом весь смысл раскладки
/// multi-browse. Центрированное содержимое пересчитывает свою позицию на каждый
/// такой кадр и потому бегает туда-сюда внутри сжимающегося элемента: движение
/// есть, а смысла в нём нет.
///
/// Поэтому содержимое держится за ЛЕВЫЙ край и стоит на месте, а лишнее просто
/// уезжает под обрез — так же, как уезжает под него картинка.
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

/// Кольцо выбранного элемента карусели.
///
/// Обводкой по всему краю, а не рамкой снаружи: элементы карусели меняют ширину
/// на ходу и обрезаются её формой, так что рамке снаружи просто негде жить.
/// Радиус тот же, что у карусели, — кольцо ложится ровно по её краю.
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

/// Элемент карусели с готовой темой.
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
        // Образец с ТЕМ ЖЕ затемнением, что выбрано у карточки: иначе картинка
        // в карусели и на карточке выглядели бы по-разному, а выбирают здесь
        // именно по виду.
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

  const _CustomImageSlot({required this.themeId});

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accent(context);
    final selected = themeId.startsWith(SubscriptionCardTheme.filePrefix);

    return Stack(
      fit: StackFit.expand,
      children: [
          FutureBuilder<String?>(
            // Ключ по id: сменили картинку — future пересоздаётся и миниатюра
            // обновляется, иначе на месте новой осталась бы старая.
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
                    image: FileImage(File(path)),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  // За левый край, как и подписи: у правого края элемент
                  // карусели сжимается, и значок ехал бы по картинке.
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
      ],
    );
  }
}

class _CardChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ExpressiveAccent accent;

  /// Выключенное состояние: чип остаётся на месте и нажимается, но уходит в
  /// нейтральный тон и перестаёт звать цветом.
  final bool muted;

  const _CardChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = ExpressiveAccent.primary,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
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

