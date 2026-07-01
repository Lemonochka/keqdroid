part of '../settings_tab.dart';

class _BackupRestoreScreen extends ConsumerStatefulWidget {
  const _BackupRestoreScreen();

  @override
  ConsumerState<_BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<_BackupRestoreScreen> {
  bool _exportSplit = true;
  bool _exportSubs = true;
  bool _exportServers = true;

  bool _busy = false;

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final storage = ref.read(storageProvider);
      final sections = <BackupSection>{};
      if (_exportSplit) sections.add(BackupSection.splitTunneling);
      if (_exportSubs) sections.add(BackupSection.subscriptions);
      if (_exportServers) sections.add(BackupSection.servers);
        if (sections.isEmpty) {
          if (mounted) setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.settingsSelectAtLeastOne)),
          );
          return;
        }

      final backup = await SettingsBackupService.buildBackup(storage, sections: sections);
      final jsonText = backup.toJsonString(pretty: true);

      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final fileName = 'keqdis-backup-$stamp.json';

      final savedPath = await FilePicker.saveFile(
        dialogTitle: l10n.settingsSelectLocation,
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(jsonText)),
      );

      if (savedPath == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.settingsBackupSaved),
          backgroundColor: AppTheme.green(context),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsExportFailed('$e')), backgroundColor: AppTheme.red(context)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'keqdis'],
      );
      final res = picked?.files.single;
      if (res == null) return;

      final bytes = await res.readAsBytes();
      final text = utf8.decode(bytes);
      final parsed = jsonDecode(text);
      if (parsed is! Map<String, dynamic>) throw const FormatException('Invalid JSON file');

      final backup = KeqdisBackup.fromJson(parsed);
      final available = SettingsBackupService.detectSections(backup);
      if (available.isEmpty) {
        throw const FormatException('No supported sections found in backup');
      }

      final selected = await _showImportPicker(available);
      if (selected == null || selected.isEmpty) return;

      await SettingsBackupService.applyBackup(
        ref.read(storageProvider),
        backup: backup,
        sections: selected,
      );

      // Refresh in-memory state.
      await ref.read(storageProvider).reloadFromDisk();
      ref.invalidate(serversProvider);
      ref.invalidate(subscriptionsProvider);
      ref.invalidate(splitTunnelingProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsImportedSections(selected.length))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsImportFailed('$e')), backgroundColor: AppTheme.red(context)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Set<BackupSection>?> _showImportPicker(Set<BackupSection> available) async {
    var split = available.contains(BackupSection.splitTunneling);
    var subs = available.contains(BackupSection.subscriptions);
    var servers = available.contains(BackupSection.servers);

    return showModalBottomSheet<Set<BackupSection>>(
      context: context,
      backgroundColor: AppTheme.bg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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

          Set<BackupSection> current() {
            final s = <BackupSection>{};
            if (split) s.add(BackupSection.splitTunneling);
            if (subs) s.add(BackupSection.subscriptions);
            if (servers) s.add(BackupSection.servers);
            return s;
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsImportBackup,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.text(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.settingsChooseWhatToImport,
                    style: TextStyle(fontSize: 12, color: AppTheme.textLight(context)),
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
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentContainer(context),
                        foregroundColor: AppTheme.onAccentContainer(context),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        elevation: 0,
        title: Text(l10n.settingsBackupRestore),
      ),
      body: SmoothScroll(
        builder: (context, controller) => ListView(
          controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.divider(context), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsExport,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.settingsCreateFileToSave,
                  style: TextStyle(fontSize: 12, color: AppTheme.textLight(context), height: 1.35),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _exportSplit,
                  activeThumbColor: AppTheme.accent(context),
                  title: Text(l10n.settingsSplitTunnelingApps),
                  onChanged: _busy ? null : (v) => setState(() => _exportSplit = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _exportSubs,
                  activeThumbColor: AppTheme.accent(context),
                  title: Text(l10n.settingsSubscriptions),
                  onChanged: _busy ? null : (v) => setState(() => _exportSubs = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _exportServers,
                  activeThumbColor: AppTheme.accent(context),
                  title: Text(l10n.settingsServersActive),
                  onChanged: _busy ? null : (v) => setState(() => _exportServers = v),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentContainer(context),
                      foregroundColor: AppTheme.onAccentContainer(context),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _busy ? null : _export,
                    icon: _busy
                        ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.onAccentContainer(context),
                      ),
                    )
                        : const Icon(Icons.download),
                    label: Text(_busy ? l10n.settingsWorking : l10n.settingsExportFile),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.divider(context), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsImport,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.settingsPickExportedFile,
                  style: TextStyle(fontSize: 12, color: AppTheme.textLight(context), height: 1.35),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.text(context),
                      side: BorderSide(color: AppTheme.divider(context)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _busy ? null : _import,
                    icon: const Icon(Icons.upload),
                    label: Text(l10n.settingsImportFile),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}
