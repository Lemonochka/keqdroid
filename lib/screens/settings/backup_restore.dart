part of '../settings_tab.dart';

class _BackupRestoreScreen extends ConsumerStatefulWidget {
  const _BackupRestoreScreen();

  @override
  ConsumerState<_BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<_BackupRestoreScreen> {
  bool _exportSplit = true;
  bool _exportSubs = true;
  bool _exportServers = true;
  bool _exportSettings = true;

  bool _busy = false;

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  String _failureReason(Object e) => e is FileDialogUnavailableException
      ? friendlyErrorDetailed(e, context)
      : backupErrorText(l10n, e);

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final storage = ref.read(storageProvider);
      final sections = <BackupSection>{};
      if (_exportSplit) sections.add(BackupSection.splitTunneling);
      if (_exportSubs) sections.add(BackupSection.subscriptions);
      if (_exportServers) sections.add(BackupSection.servers);
      if (_exportSettings) sections.add(BackupSection.appSettings);
      if (sections.isEmpty) {
        if (mounted) setState(() => _busy = false);
        AppSnack.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.settingsSelectAtLeastOne)));
        return;
      }

      final backup = await SettingsBackupService.buildBackup(
        storage,
        sections: sections,
      );
      final bytes = await SettingsBackupService.encodeFile(backup);

      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final fileName =
          'keqdroid-backup-$stamp.${SettingsBackupService.fileExtension}';

      final savedPath = await AppFileDialogs.saveFile(
        dialogTitle: l10n.settingsSelectLocation,
        fileName: fileName,
        bytes: bytes,
      );

      if (savedPath == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      if (!mounted) return;
      AppSnack.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.settingsBackupSaved),
          backgroundColor: AppTheme.green(context),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ExpressiveShape.medium),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnack.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.settingsExportFailed(_failureReason(e))),
          backgroundColor: AppTheme.red(context),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await AppFileDialogs.pickFile(
        dialogTitle: l10n.settingsImportBackup,
        type: FileType.custom,
        allowedExtensions: const [
          SettingsBackupService.fileExtension,
          'json',
          'keqdis',
        ],
      );
      if (res == null) return;

      final backup = await SettingsBackupService.decodeFile(
        await res.readAsBytes(),
      );
      if (!mounted) return;
      await _restore(backup);
    } catch (e) {
      if (!mounted) return;
      AppSnack.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.settingsImportFailed(_failureReason(e))),
          backgroundColor: AppTheme.red(context),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(KeqdroidBackup backup) async {
    final restored = await restoreBackupInteractive(context, ref, backup);
    if (restored == null || !mounted) return;
    AppSnack.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settingsImportedSections(restored))),
    );
  }

  Future<void> _openTransfer(BackupTransferDirection direction) async {
    final received = await BackupTransferScreen.open(context, direction);
    if (received == null || !mounted) return;
    try {
      await _restore(received);
    } catch (e) {
      if (!mounted) return;
      AppSnack.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.settingsImportFailed(_failureReason(e))),
          backgroundColor: AppTheme.red(context),
        ),
      );
    }
  }

  // камера есть у телефона и планшета; ПК и телевизор только показывают код
  bool get _canScan =>
      !PlatformBootstrap.isDesktop && !PlatformBootstrap.isTelevision;

  // вид шторки тот же, что у меню «Добавить» на вкладке серверов
  void _showTransferSheet() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetCtx) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  l10n.backupTransferTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetCtx).textTheme
                      .emphasized(Theme.of(sheetCtx).textTheme.titleLarge)
                      ?.copyWith(color: AppTheme.text(sheetCtx)),
                ),
              ),
              ExpressiveGroup(
                children: [
                  ExpressiveActionTile(
                    icon: Icons.download_for_offline_rounded,
                    title: l10n.backupTransferReceive,
                    subtitle: l10n.backupTransferReceiveHint,
                    accent: ExpressiveAccent.primary,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      unawaited(_openTransfer(BackupTransferDirection.receive));
                    },
                  ),
                  ExpressiveActionTile(
                    icon: Icons.ios_share_rounded,
                    title: l10n.backupTransferGive,
                    subtitle: l10n.backupTransferGiveHint,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      unawaited(_openTransfer(BackupTransferDirection.give));
                    },
                  ),
                  if (_canScan)
                    ExpressiveActionTile(
                      icon: Icons.qr_code_scanner_rounded,
                      title: l10n.backupTransferScan,
                      subtitle: l10n.backupTransferScanHint,
                      accent: ExpressiveAccent.tertiary,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        unawaited(scanBackupCode(context, ref));
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

  @override
  Widget build(BuildContext context) {
    return ExpressivePage(
      title: l10n.settingsBackupRestore,
      children: [
        ExpressiveGroup(
          children: [
            ExpressiveActionTile(
              icon: Icons.devices_rounded,
              title: l10n.backupTransferOpen,
              accent: ExpressiveAccent.primary,
              onTap: _showTransferSheet,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ExpressiveCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.settingsExport,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.text(context),
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _exportSplit,
                activeThumbColor: AppTheme.accent(context),
                title: Text(l10n.settingsSplitTunnelingApps),
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _exportSplit = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _exportSubs,
                activeThumbColor: AppTheme.accent(context),
                title: Text(l10n.settingsSubscriptions),
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _exportSubs = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _exportServers,
                activeThumbColor: AppTheme.accent(context),
                title: Text(l10n.settingsServersActive),
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _exportServers = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _exportSettings,
                activeThumbColor: AppTheme.accent(context),
                title: Text(l10n.settingsAppSettings),
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _exportSettings = v),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
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
                  onPressed: _busy ? null : _export,
                  icon: _busy
                      ? ShapeLoadingIndicator(
                          size: 16,
                          color: AppTheme.onAccentContainer(context),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(
                    _busy ? l10n.settingsWorking : l10n.settingsExportFile,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ExpressiveCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.settingsImport,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.text(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.settingsPickExportedFile,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textLight(context),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.text(context),
                    side: BorderSide(color: AppTheme.divider(context)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        ExpressiveShape.medium,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _busy ? null : _import,
                  icon: const Icon(Icons.upload_rounded),
                  label: Text(l10n.settingsImportFile),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
