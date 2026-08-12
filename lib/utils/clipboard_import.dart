import 'package:flutter/material.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/subscription.dart';
import '../providers/providers.dart';
import 'error_messages.dart';
import 'import_payload.dart';

/// Ctrl/Cmd+V helpers shared by the subscriptions and servers screens. Kept as
/// free functions so the desktop home (which owns the keyboard focus across the
/// IndexedStack tabs) can dispatch them by active tab.

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

Future<void> pasteServersFromClipboard(
  BuildContext context,
  WidgetRef ref,
) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final raw = data?.text?.trim() ?? '';
  if (raw.isEmpty || !context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  // AmneziaWG .conf и готовый json-конфиг ядра — единые многострочные блоки
  // (addManual принимает их целиком); иначе список ссылок построчно.
  final configs = splitServerImportPayload(raw);
  if (configs.isEmpty) return;
  // Каждую строку добавляем независимо (как _addConfigsResilient в
  // servers_tab): первый же дубликат не должен обрывать импорт и молча
  // терять остальные валидные строки.
  var added = 0;
  Object? firstError;
  for (final c in configs) {
    try {
      await ref.read(serversProvider.notifier).addManual(c);
      added++;
    } catch (e) {
      firstError ??= e;
    }
  }
  if (!context.mounted) return;
  final summary = l10n.serversImportedSummary(added, configs.length);
  if (firstError == null) {
    _toast(context, summary);
  } else {
    _toast(context, '$summary\n${friendlyError(firstError, context)}');
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ExpressiveShape.medium)),
    ),
  );
}
