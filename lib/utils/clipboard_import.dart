import 'package:flutter/material.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/subscription.dart';
import '../providers/providers.dart';
import 'error_messages.dart';
import 'import_payload.dart';
import 'package:keqdroid/shared/ui/liquid_toast.dart';

Future<void> pasteSubscriptionFromClipboard(
  BuildContext context,
  WidgetRef ref,
) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text?.trim() ?? '';
  if (text.isEmpty || !context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  final uri = Uri.tryParse(text);
  final isUrl = uri != null && (uri.isScheme('http') || uri.isScheme('https'));
  if (!isUrl) {
    _toast(context, l10n.clipboardNoSubscriptionLink);
    return;
  }
  try {
    final sub = Subscription.create(
      name: uri.host.isNotEmpty ? uri.host : text,
      url: text,
      nameIsAuto: true,
    );
    await ref.read(subscriptionsProvider.notifier).add(sub);
    if (context.mounted) {
      _toast(context, l10n.qrSubscriptionAdded(uri.host));
    }
  } catch (e) {
    if (context.mounted) _toast(context, friendlyError(e, context));
  }
}

Future<void> pasteLinksFromClipboard(
  BuildContext context,
  WidgetRef ref,
) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final raw = data?.text?.trim() ?? '';
  if (raw.isEmpty || !context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  final result = await importPastedLinksInto(ref, raw);
  if (!context.mounted) return;
  final error = result.firstError;
  final lines = [
    ?pastedLinksSummary(l10n, result),
    if (error != null) friendlyError(error, context),
  ];
  if (lines.isNotEmpty) _toast(context, lines.join('\n'));
}

class PastedLinksResult {
  final List<String> subscriptionHosts;
  final int serversAdded;
  final int serversTotal;
  final Object? firstError;

  const PastedLinksResult({
    required this.subscriptionHosts,
    required this.serversAdded,
    required this.serversTotal,
    required this.firstError,
  });

  int get added => subscriptionHosts.length + serversAdded;
}

Future<PastedLinksResult> importPastedLinks(
  String raw, {
  required Future<void> Function(String url) addSubscription,
  required Future<void> Function(String config) addServer,
}) async {
  final hosts = <String>[];
  var serversAdded = 0;
  var serversTotal = 0;
  Object? firstError;
  for (final part in splitServerImportPayload(raw)) {
    final url = subscriptionUrlFromPastedLine(part);
    try {
      if (url != null) {
        await addSubscription(url);
        hosts.add(Uri.parse(url).host);
      } else {
        serversTotal++;
        await addServer(part);
        serversAdded++;
      }
    } catch (e) {
      firstError ??= e;
    }
  }
  return PastedLinksResult(
    subscriptionHosts: hosts,
    serversAdded: serversAdded,
    serversTotal: serversTotal,
    firstError: firstError,
  );
}

Future<PastedLinksResult> importPastedLinksInto(WidgetRef ref, String raw) {
  return importPastedLinks(
    raw,
    addSubscription: (url) => ref.read(subscriptionsProvider.notifier).add(
      Subscription.create(name: Uri.parse(url).host, url: url, nameIsAuto: true),
    ),
    addServer: (config) => ref.read(serversProvider.notifier).addManual(config),
  );
}

String? pastedLinksSummary(AppLocalizations l10n, PastedLinksResult result) {
  final lines = [
    if (result.subscriptionHosts.isNotEmpty)
      l10n.qrSubscriptionAdded(result.subscriptionHosts.join(', ')),
    if (result.serversTotal > 0)
      l10n.serversImportedSummary(result.serversAdded, result.serversTotal),
  ];
  return lines.isEmpty ? null : lines.join('\n');
}

void _toast(BuildContext context, String msg) {
  AppSnack.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ExpressiveShape.medium)),
    ),
  );
}
