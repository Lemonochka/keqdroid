part of '../subscriptions_tab.dart';

void _showSubscriptionEditSheet(
  BuildContext context,
  WidgetRef ref,
  Subscription sub,
) {
  final l10n = AppLocalizations.of(context)!;
  final nameCtrl = TextEditingController(text: sub.name);
  final urlCtrl = TextEditingController(text: sub.url);
  var identity = sub.fetchIdentity;
  var excludedProtocols = sub.excludedProtocols;
  String? editError;

  final textColor = AppTheme.text(context);
  final accentContainerColor = AppTheme.accentContainer(context);
  final onAccentContainerColor = AppTheme.onAccentContainer(context);

  showModalBottomSheet<void>(
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
          return TvTextField(
            radius: BorderRadius.circular(ExpressiveShape.large),
            builder: (fieldCtx, canRequestFocus) {
              final fieldText = AppTheme.text(fieldCtx);
              final fieldLight = AppTheme.textLight(fieldCtx);
              final fieldCard = AppTheme.card(fieldCtx);
              final fieldAccent = AppTheme.accent(fieldCtx);
              return TextField(
                controller: ctrl,
                canRequestFocus: canRequestFocus,
                maxLines: maxLines,
                textDirection: technical ? technicalInputDirection : null,
                style: Theme.of(
                  fieldCtx,
                ).textTheme.bodyMedium?.copyWith(color: fieldText),
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  suffixIcon: suffix,
                  labelStyle: TextStyle(color: fieldLight),
                  hintStyle: Theme.of(fieldCtx).textTheme.bodySmall?.copyWith(
                    color: fieldLight.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: fieldCard,
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
                    borderSide: BorderSide(color: fieldAccent, width: 2),
                  ),
                ),
              );
            },
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
                suffix: Builder(
                  builder: (btnCtx) => IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: l10n.subscriptionsCopyUrl,
                    style: TvFocus.iconButtonStyle(
                      btnCtx,
                      color: AppTheme.textLight(btnCtx),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: urlCtrl.text));
                      AppSnack.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.subscriptionsUrlCopied),
                          backgroundColor: textColor,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              ExpressiveShape.medium,
                            ),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _IdentityTile(
                identity: identity,
                onTap: () async {
                  final picked = await _showIdentitySheet(
                    ctx,
                    initial: identity,
                  );
                  if (picked == null) return;
                  setSheet(() => identity = picked);
                },
              ),
              Consumer(
                builder: (context, ref, _) {
                  final counts = _protocolCountsOf(sub, ref);
                  if (counts.length < 2) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _ProtocolsTile(
                      counts: counts,
                      excluded: excludedProtocols,
                      onTap: () async {
                        final picked = await _showProtocolsSheet(
                          ctx,
                          counts: counts,
                          excluded: excludedProtocols,
                        );
                        if (picked == null) return;
                        setSheet(() => excludedProtocols = picked);
                      },
                    ),
                  );
                },
              ),
              if (editError != null) ...[
                const SizedBox(height: 8),
                Text(
                  editError!,
                  style: Theme.of(
                    ctx,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.red(ctx)),
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
                            excludedProtocols: excludedProtocols,
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
                    style: Theme.of(
                      ctx,
                    ).textTheme.emphasized(Theme.of(ctx).textTheme.labelLarge),
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
