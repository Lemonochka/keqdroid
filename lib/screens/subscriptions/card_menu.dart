part of '../subscriptions_tab.dart';

void _showSubscriptionCardMenu(
  BuildContext context, {
  required Subscription sub,
  required VoidCallback onEdit,
  required VoidCallback onShare,
  required VoidCallback onDelete,
}) {
  final l10n = AppLocalizations.of(context)!;
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
                    onEdit();
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
                    onShare();
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
                    onDelete();
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

void _showSubscriptionDeleteDialog(
  BuildContext context, {
  required Subscription sub,
  required VoidCallback onConfirmed,
}) {
  final l10n = AppLocalizations.of(context)!;
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
            onConfirmed();
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
