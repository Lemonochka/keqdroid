import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/subscription.dart';
import '../providers/providers.dart';
import 'awg_profile.dart';
import 'error_messages.dart';

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
  final uri = Uri.tryParse(text);
  final isUrl = uri != null && (uri.isScheme('http') || uri.isScheme('https'));
  if (!isUrl) {
    _toast(context, 'В буфере нет ссылки подписки (http/https)');
    return;
  }
  try {
    final sub = Subscription.create(
      name: uri.host.isNotEmpty ? uri.host : text,
      url: text,
    );
    await ref.read(subscriptionsProvider.notifier).add(sub);
    if (context.mounted) _toast(context, 'Подписка добавлена: ${uri.host}');
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
  if (AwgProfile.isAwgConfig(raw)) {
    _toast(context, 'AmneziaWG добавляйте через «Импорт файла»');
    return;
  }
  final configs = raw
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (configs.isEmpty) return;
  var added = 0;
  try {
    for (final c in configs) {
      await ref.read(serversProvider.notifier).addManual(c);
      added++;
    }
    if (context.mounted) _toast(context, 'Добавлено серверов: $added');
  } catch (e) {
    if (context.mounted) _toast(context, friendlyError(e, context));
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
