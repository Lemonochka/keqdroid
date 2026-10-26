import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/shape_loading_indicator.dart';

import '../models/subscription.dart';
import '../providers/providers.dart';
import '../services/tv_handoff.dart';
import 'package:keqdroid/shared/ui/liquid_toast.dart';

Future<void> sendSubscriptionToTv(
  BuildContext context,
  WidgetRef ref,
  TvPairing tv,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = AppSnack.of(context);
  final subscriptions = ref.read(subscriptionsProvider).value ??
      await ref.read(storageProvider).getSubscriptions();
  if (!context.mounted) return;
  if (subscriptions.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.tvSendNothing)));
    return;
  }
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => TvSendDialog(tv: tv, subscriptions: subscriptions),
  );
  if (sent == true) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.tvSendDone)));
  }
}

class TvSendDialog extends StatefulWidget {
  const TvSendDialog({
    super.key,
    required this.tv,
    required this.subscriptions,
  });

  final TvPairing tv;
  final List<Subscription> subscriptions;

  @override
  State<TvSendDialog> createState() => _TvSendDialogState();
}

class _TvSendDialogState extends State<TvSendDialog> {
  late String _selectedId = widget.subscriptions.first.id;
  bool _sending = false;
  String? _error;

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context)!;
    final sub = widget.subscriptions.firstWhere((s) => s.id == _selectedId);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await sendToTv(
        widget.tv,
        TvSubscriptionOffer(
          url: sub.url,
          name: sub.name,
          nameIsAuto: sub.nameIsAuto,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on TvSendException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = switch (e.failure) {
          TvSendFailure.unreachable => l10n.tvSendUnreachable,
          TvSendFailure.expired => l10n.tvSendExpired,
          TvSendFailure.rejected => l10n.tvSendRejected(e.message ?? ''),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(l10n.tvSendTitle),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tvSendPick,
            style: textTheme.bodyMedium
                ?.copyWith(color: AppTheme.textLight(context)),
          ),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _selectedId,
            onChanged: (id) {
              if (id != null && !_sending) setState(() => _selectedId = id);
            },
            child: Column(
              children: [
                for (final sub in widget.subscriptions)
                  RadioListTile<String>(
                    value: sub.id,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      sub.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: textTheme.bodySmall
                  ?.copyWith(color: AppTheme.red(context)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context, false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: _sending
              ? ShapeLoadingIndicator(
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                )
              : Text(l10n.tvSendAction),
        ),
      ],
    );
  }
}
