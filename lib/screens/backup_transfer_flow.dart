import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../services/backup_crypto.dart';
import '../services/backup_transfer.dart';
import '../services/settings_backup_service.dart';
import '../shared/ui/app_theme.dart';
import '../shared/ui/expressive.dart';
import '../shared/ui/liquid_toast.dart';
import '../shared/ui/shape_loading_indicator.dart';
import 'qr_scan_screen.dart';

const allBackupSections = {
  BackupSection.splitTunneling,
  BackupSection.subscriptions,
  BackupSection.servers,
  BackupSection.appSettings,
};

Future<Set<BackupSection>?> showBackupRestorePicker(
  BuildContext context,
  Set<BackupSection> available,
) {
  final l10n = AppLocalizations.of(context)!;
  var split = available.contains(BackupSection.splitTunneling);
  var subs = available.contains(BackupSection.subscriptions);
  var servers = available.contains(BackupSection.servers);
  var settings = available.contains(BackupSection.appSettings);

  return showModalBottomSheet<Set<BackupSection>>(
    context: context,
    showDragHandle: true,
    // без этого шторка не выше 9/16 экрана, и на телевизоре кнопка импорта уезжала за край
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        Widget checkbox({
          required String title,
          required bool value,
          required bool enabled,
          required ValueChanged<bool> onChanged,
        }) {
          return CheckboxListTile(
            value: value,
            onChanged: enabled ? (v) => onChanged(v ?? false) : null,
            title: Text(title, style: TextStyle(color: AppTheme.text(context))),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppTheme.accent(context),
          );
        }

        Set<BackupSection> current() => {
          if (split) BackupSection.splitTunneling,
          if (subs) BackupSection.subscriptions,
          if (servers) BackupSection.servers,
          if (settings) BackupSection.appSettings,
        };

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsImportBackup,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.text(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.settingsChooseWhatToImport,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textLight(context),
                  ),
                ),
                const SizedBox(height: 10),
                checkbox(
                  title: l10n.settingsSplitTunnelingApps,
                  value: split,
                  enabled: available.contains(BackupSection.splitTunneling),
                  onChanged: (v) => setSheet(() => split = v),
                ),
                checkbox(
                  title: l10n.settingsSubscriptions,
                  value: subs,
                  enabled: available.contains(BackupSection.subscriptions),
                  onChanged: (v) => setSheet(() => subs = v),
                ),
                checkbox(
                  title: l10n.settingsServersActive,
                  value: servers,
                  enabled: available.contains(BackupSection.servers),
                  onChanged: (v) => setSheet(() => servers = v),
                ),
                checkbox(
                  title: l10n.settingsAppSettings,
                  value: settings,
                  enabled: available.contains(BackupSection.appSettings),
                  onChanged: (v) => setSheet(() => settings = v),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentContainer(context),
                      foregroundColor: AppTheme.onAccentContainer(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          ExpressiveShape.medium,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, current()),
                    child: Text(l10n.settingsImport),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

// null, если пользователь передумал в выборе разделов
Future<int?> restoreBackupInteractive(
  BuildContext context,
  WidgetRef ref,
  KeqdroidBackup backup,
) async {
  final available = SettingsBackupService.detectSections(backup);
  if (available.isEmpty) {
    throw const FormatException('No supported sections found in backup');
  }
  final selected = await showBackupRestorePicker(context, available);
  if (selected == null || selected.isEmpty) return null;

  final storage = ref.read(storageProvider);
  await SettingsBackupService.applyBackup(
    storage,
    backup: backup,
    sections: selected,
  );
  await storage.reloadFromDisk();
  ref.invalidate(serversProvider);
  ref.invalidate(subscriptionsProvider);
  ref.invalidate(splitTunnelingProvider);
  // без сброса импортированное доехало бы до диска, а на экране осталось прежнее до перезапуска
  ref.invalidate(settingsNotifierProvider);
  ref.invalidate(routesProvider);
  ref.invalidate(routingProfilesProvider);
  return selected.length;
}

String backupErrorText(AppLocalizations l10n, Object error) => switch (error) {
  BackupKeyUnavailable() => l10n.backupFromReleaseBuild,
  BackupTransferException(failure: BackupTransferFailure.unreachable) =>
    l10n.backupTransferUnreachable,
  BackupTransferException(failure: BackupTransferFailure.expired) =>
    l10n.backupTransferExpired,
  BackupTransferException(:final detail) => l10n.backupTransferRejected(
    detail ?? '',
  ),
  _ => '$error',
};

Future<void> scanBackupCode(BuildContext context, WidgetRef ref) async {
  final raw = await QrScanScreen.scan(context);
  if (raw == null || raw.isEmpty || !context.mounted) return;
  final link = BackupTransferLink.parse(raw);
  if (link == null) {
    AppSnack.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.backupTransferNotOurCode),
      ),
    );
    return;
  }
  await runBackupTransferLink(context, ref, link);
}

// код с другого устройства: из своего сканера, из сканера серверов или ссылкой от камеры системы
Future<void> runBackupTransferLink(
  BuildContext context,
  WidgetRef ref,
  BackupTransferLink link,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = AppSnack.of(context);
  if (link.direction == BackupTransferDirection.receive) {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _BackupSendDialog(link: link, ref: ref),
    );
    if (sent == true) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupTransferSent)));
    }
    return;
  }
  final backup = await showDialog<KeqdroidBackup>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BackupFetchDialog(link: link),
  );
  if (backup == null || !context.mounted) return;
  try {
    final restored = await restoreBackupInteractive(context, ref, backup);
    if (restored != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsImportedSections(restored))),
      );
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.settingsImportFailed(backupErrorText(l10n, e))),
        backgroundColor: context.mounted ? AppTheme.red(context) : null,
      ),
    );
  }
}

class _BackupSendDialog extends StatefulWidget {
  const _BackupSendDialog({required this.link, required this.ref});

  final BackupTransferLink link;
  final WidgetRef ref;

  @override
  State<_BackupSendDialog> createState() => _BackupSendDialogState();
}

class _BackupSendDialogState extends State<_BackupSendDialog> {
  bool _sending = false;
  String? _error;

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final backup = await SettingsBackupService.buildBackup(
        widget.ref.read(storageProvider),
        sections: allBackupSections,
      );
      await sendBackup(
        widget.link,
        utf8.encode(backup.toJsonString(pretty: false)),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = backupErrorText(l10n, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(l10n.backupTransferSendTitle),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.backupTransferSendMessage(widget.link.host),
            style: textTheme.bodyMedium?.copyWith(
              color: AppTheme.textLight(context),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: textTheme.bodySmall?.copyWith(
                color: AppTheme.red(context),
              ),
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
              : Text(l10n.backupTransferSendAction),
        ),
      ],
    );
  }
}

class _BackupFetchDialog extends StatefulWidget {
  const _BackupFetchDialog({required this.link});

  final BackupTransferLink link;

  @override
  State<_BackupFetchDialog> createState() => _BackupFetchDialogState();
}

class _BackupFetchDialogState extends State<_BackupFetchDialog> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _error = null);
    try {
      final Uint8List plain = await fetchBackup(widget.link);
      final backup = KeqdroidBackup.parse(plain);
      if (mounted) Navigator.pop(context, backup);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = backupErrorText(AppLocalizations.of(context)!, e),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final error = _error;
    return AlertDialog(
      title: Text(l10n.backupTransferFetchTitle),
      content: error == null
          ? Row(
              children: [
                ShapeLoadingIndicator(
                  size: 24,
                  color: AppTheme.accent(context),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    l10n.backupTransferFetching(widget.link.host),
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textLight(context),
                    ),
                  ),
                ),
              ],
            )
          : Text(
              error,
              style: textTheme.bodyMedium?.copyWith(
                color: AppTheme.red(context),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        if (error != null)
          FilledButton(
            onPressed: _fetch,
            child: Text(l10n.backupTransferRetry),
          ),
      ],
    );
  }
}
