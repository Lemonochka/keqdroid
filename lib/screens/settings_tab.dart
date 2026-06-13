import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/ping_test_config.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/debug_log_service.dart';
import 'package:keqdroid/services/settings_backup_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/services/windows_desktop_service.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/services/update_service.dart';
import 'package:keqdroid/shared/ui/update_dialog.dart';
import 'package:keqdroid/utils/app_locale.dart';
import 'package:keqdroid/utils/routing_presets.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/split_tunneling_screen.dart';
import 'package:keqdroid/ui/responsive/desktop_page_layout.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settingsAsync = ref.watch(settingsNotifierProvider);

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      body: SafeArea(
        child: DesktopPageLayout(
          maxWidth: 720,
          child: Column(
          children: [
            Expanded(
              child: ListView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  tabContentHorizontalInset(),
                  24,
                  tabContentHorizontalInset(),
                  24,
                ),
                children: [
                  Text(
                    l10n.settingsTitle,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.text(context)),
                  ),
                  const SizedBox(height: 20),
                  _ThemeCustomizationCard(settingsAsync: settingsAsync),
                  const SizedBox(height: 12),
                  _LanSharingCard(settingsAsync: settingsAsync),
                  const SizedBox(height: 12),
                  const _SplitTunnelingSettingsCard(),
                  if (Platform.isWindows) ...[
                    const SizedBox(height: 12),
                    _SettingsCard(
                      title: l10n.settingsDesktopTitle,
                      subtitle: l10n.settingsDesktopSubtitle,
                      icon: Icons.desktop_windows_outlined,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const _WindowsDesktopSettingsScreen(),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _SettingsCard(
                    title: l10n.settingsAdvanced,
                    subtitle: l10n.settingsAdvancedSubtitle,
                    icon: Icons.tune,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const _AdvancedSettingsScreen()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _LanguageSettingsCard(settingsAsync: settingsAsync),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    title: l10n.settingsBackupRestore,
                    subtitle: l10n.settingsBackupRestoreSubtitle,
                    icon: Icons.cloud_upload_outlined,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const _BackupRestoreScreen()),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                tabContentHorizontalInset(),
                0,
                tabContentHorizontalInset(),
                24,
              ),
              child: const _AppVersionSection(),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _LanguageSettingsCard extends ConsumerWidget {
  final AsyncValue<AppSettings> settingsAsync;
  const _LanguageSettingsCard({required this.settingsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = settingsAsync.value ?? const AppSettings();
    final label = appLanguageLabel(
      settings,
      systemLabel: l10n.settingsLanguageSystem,
    );
    return _SettingsCard(
      title: l10n.settingsLanguageTitle,
      subtitle: l10n.settingsLanguageSubtitle(label),
      icon: Icons.translate,
      onTap: () => _showLanguageSheet(context, ref, settings),
    );
  }

  void _showLanguageSheet(BuildContext context, WidgetRef ref, AppSettings current) {
    final l10n = AppLocalizations.of(context)!;
    final accent = AppTheme.accent(context);
    final options = <(String code, String label)>[
      ('system', l10n.settingsLanguageSystem),
      ('en', l10n.settingsLanguageEnglish),
      ('ru', l10n.settingsLanguageRussian),
      ('de', l10n.settingsLanguageGerman),
      ('zh', l10n.settingsLanguageChinese),
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.42,
          minChildSize: 0.32,
          maxChildSize: 0.72,
          builder: (_, scrollCtrl) {
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.card(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: AppTheme.divider(context).withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.divider(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text(
                      l10n.settingsLanguageSheetTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text(context),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: options.length,
                      itemBuilder: (_, i) {
                        final (code, label) = options[i];
                        final selected = current.appLanguageCode == code;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: selected
                                ? accent.withValues(alpha: 0.12)
                                : AppTheme.bg(context),
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                await ref
                                    .read(settingsNotifierProvider.notifier)
                                    .save(current.copyWith(appLanguageCode: code));
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: AppTheme.text(context),
                                        ),
                                      ),
                                    ),
                                    if (selected)
                                      Icon(Icons.check_circle,
                                          color: accent, size: 22),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SplitTunnelingSettingsCard extends ConsumerWidget {
  const _SplitTunnelingSettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final packageCount = ref.watch(
      splitTunnelingProvider.select(
        (s) => s.excludePackages.length + s.includePackages.length,
      ),
    );

    return _SettingsCard(
      title: l10n.settingsSplitTitle,
      subtitle: l10n.settingsSplitConfigured(packageCount),
      icon: Icons.alt_route,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SplitTunnelingScreen()),
      ),
    );
  }
}

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
      body: ListView(
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
    );
  }
}

class _AdvancedSettingsScreen extends ConsumerWidget {
  const _AdvancedSettingsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settingsAsync = ref.watch(settingsNotifierProvider);

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        elevation: 0,
        title: Text(l10n.settingsAdvanced),
      ),
      body: ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _SettingsCard(
            title: l10n.settingsPingTitle,
            subtitle: _pingSettingsSubtitle(l10n, settingsAsync.value),
            icon: Icons.network_ping,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _PingSettingsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            title: l10n.settingsXrayCoreTitle,
            subtitle: _xrayCoreSettingsSubtitle(l10n, settingsAsync.value),
            icon: Icons.settings_ethernet,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _XrayCoreSettingsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            title: l10n.settingsLocalPortsTitle,
            subtitle: l10n.settingsLocalPortsSubtitle(
              (settingsAsync.value ?? const AppSettings()).localPort.toString(),
              (settingsAsync.value ?? const AppSettings()).httpPort.toString(),
            ),
            icon: Icons.settings_input_component,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _LocalProxyPortsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            title: l10n.settingsRoutingTitle,
            subtitle: l10n.settingsRoutingSubtitle,
            icon: Icons.account_tree,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _RoutingScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            title: l10n.settingsResetRoutingTitle,
            subtitle: l10n.settingsResetRoutingSubtitle,
            icon: Icons.restore,
            isDestructive: false,
            onTap: () async {
              final current = ref.read(settingsNotifierProvider).value;
              if (current == null) return;
              await ref.read(settingsNotifierProvider.notifier).save(
                    current.copyWith(
                      directRules: RoutingPresets.defaultDirectRules,
                      proxyRules: RoutingPresets.defaultProxyRules,
                      blockedRules: RoutingPresets.defaultBlockedRules,
                    ),
                  );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.settingsRoutingResetDone)),
                );
              }
            },
          ),
          const SizedBox(height: 12),
          _DebugModeCard(settingsAsync: settingsAsync),
          const SizedBox(height: 12),
          _ShareHwidCard(settingsAsync: settingsAsync),
        ],
      ),
    );
  }
}

class _LocalProxyPortsScreen extends ConsumerStatefulWidget {
  const _LocalProxyPortsScreen();

  @override
  ConsumerState<_LocalProxyPortsScreen> createState() =>
      _LocalProxyPortsScreenState();
}

class _LocalProxyPortsScreenState
    extends ConsumerState<_LocalProxyPortsScreen> {
  final _socksCtrl = TextEditingController();
  final _httpCtrl = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _socksCtrl.dispose();
    _httpCtrl.dispose();
    super.dispose();
  }

  void _syncControllers(AppSettings settings) {
    if (_initialized) return;
    _socksCtrl.text = settings.localPort.toString();
    _httpCtrl.text = settings.httpPort.toString();
    _initialized = true;
  }

  Future<void> _apply(AppSettings settings) async {
    final l10n = AppLocalizations.of(context)!;
    final socks = int.tryParse(_socksCtrl.text.trim());
    final http = int.tryParse(_httpCtrl.text.trim());

    bool valid(int? p) => p != null && p > 0 && p < 65536;
    if (!valid(socks) || !valid(http)) {
      _socksCtrl.text = settings.localPort.toString();
      _httpCtrl.text = settings.httpPort.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsPortInvalid)),
      );
      return;
    }
    if (socks == http) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsPortsMustDiffer)),
      );
      return;
    }
    if (socks == settings.localPort && http == settings.httpPort) return;

    await ref.read(settingsNotifierProvider.notifier).save(
          settings.copyWith(localPort: socks, httpPort: http),
        );
  }

  Future<void> _resetDefaults(AppSettings settings) async {
    const defaults = AppSettings();
    _socksCtrl.text = defaults.localPort.toString();
    _httpCtrl.text = defaults.httpPort.toString();
    await ref.read(settingsNotifierProvider.notifier).save(
          settings.copyWith(
            localPort: defaults.localPort,
            httpPort: defaults.httpPort,
          ),
        );
  }

  Widget _portField(
    BuildContext context,
    String label,
    TextEditingController ctrl,
    bool enabled,
    VoidCallback onSubmit,
  ) {
    return TextField(
      controller: ctrl,
      enabled: enabled,
      keyboardType: TextInputType.number,
      style: TextStyle(fontSize: 14, color: AppTheme.text(context)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12, color: AppTheme.textLight(context)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppTheme.textLight(context).withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.accent(context)),
        ),
        isDense: true,
      ),
      onSubmitted: (_) => onSubmit(),
      onEditingComplete: onSubmit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    _syncControllers(settings);

    final isConnected = ref.watch(
      vpnStateProvider.select((a) {
        final status = a.value?.status;
        return status == VpnStatus.connected || status == VpnStatus.connecting;
      }),
    );

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        elevation: 0,
        title: Text(l10n.settingsLocalPortsTitle),
      ),
      body: ListView(
        physics: const ClampingScrollPhysics(),
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
                Row(
                  children: [
                    Expanded(
                      child: _portField(
                        context,
                        l10n.settingsSocks5PortLabel,
                        _socksCtrl,
                        !isConnected,
                        () => _apply(settings),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _portField(
                        context,
                        l10n.settingsHttpPortLabel,
                        _httpCtrl,
                        !isConnected,
                        () => _apply(settings),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.settingsLocalPortsHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textLight(context),
                    height: 1.35,
                  ),
                ),
                if (isConnected) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.settingsTurnOffToChange,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.orange(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: isConnected ? null : () => _resetDefaults(settings),
              icon: const Icon(Icons.restore, size: 18),
              label: Text(l10n.settingsLocalPortsResetTitle),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowsDesktopSettingsScreen extends ConsumerWidget {
  const _WindowsDesktopSettingsScreen();

  Future<void> _save(WidgetRef ref, AppSettings next) async {
    await ref.read(settingsNotifierProvider.notifier).save(next);
    await WindowsDesktopService.applySettings(next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();

    Widget toggleRow({
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool>? onChanged,
    }) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.divider(context), width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textLight(context),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              activeThumbColor: AppTheme.accent(context),
              onChanged: onChanged,
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        elevation: 0,
        title: Text(l10n.settingsDesktopTitle),
      ),
      body: ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          toggleRow(
            title: l10n.settingsMinimizeToTray,
            subtitle: l10n.settingsMinimizeToTrayHint,
            value: settings.minimizeToTray,
            onChanged: (v) => _save(ref, settings.copyWith(minimizeToTray: v)),
          ),
          const SizedBox(height: 12),
          toggleRow(
            title: l10n.settingsLaunchAtStartup,
            subtitle: l10n.settingsLaunchAtStartupHint,
            value: settings.launchAtStartup,
            onChanged: (v) => _save(ref, settings.copyWith(launchAtStartup: v)),
          ),
          const SizedBox(height: 12),
          toggleRow(
            title: l10n.settingsAutoConnectOnAutostart,
            subtitle: l10n.settingsAutoConnectOnAutostartHint,
            value: settings.autoConnectLastServer,
            onChanged: settings.launchAtStartup
                ? (v) => _save(
                      ref,
                      settings.copyWith(autoConnectLastServer: v),
                    )
                : null,
          ),
          if (!settings.launchAtStartup)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
              child: Text(
                l10n.settingsAutoConnectRequiresAutostart,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textLight(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _XrayCoreSectionHeader extends StatelessWidget {
  const _XrayCoreSectionHeader({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppTheme.accent(context).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: AppTheme.accent(context)),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.text(context),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

Widget _xraySettingsDivider(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, color: AppTheme.divider(context)),
    );

Widget _xraySettingsCard(BuildContext context, {required List<Widget> children}) =>
    Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.divider(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );

TextStyle _xrayTileSubtitleStyle(BuildContext context) => TextStyle(
      fontSize: 12,
      color: AppTheme.textLight(context),
      height: 1.35,
    );

class _XrayCoreSettingsScreen extends ConsumerStatefulWidget {
  const _XrayCoreSettingsScreen();

  @override
  ConsumerState<_XrayCoreSettingsScreen> createState() =>
      _XrayCoreSettingsScreenState();
}

class _XrayCoreSettingsScreenState extends ConsumerState<_XrayCoreSettingsScreen> {
  final _dnsServersCtrl = TextEditingController();

  @override
  void dispose() {
    _dnsServersCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(AppSettings settings, XrayCoreSettings core) async {
    await ref
        .read(settingsNotifierProvider.notifier)
        .save(settings.copyWith(xrayCore: core));
  }

  Future<void> _resetDefaults(AppSettings settings) async {
    await _save(settings, const XrayCoreSettings());
    _dnsServersCtrl.text = const XrayCoreSettings().dnsServers;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.settingsXrayResetDone)),
    );
  }

  Widget _choiceTile({
    required BuildContext context,
    required String value,
    required String groupValue,
    required Color accent,
    required String title,
    String? subtitle,
    required ValueChanged<String> onSelect,
  }) {
    return RadioListTile<String>(
      value: value,
      groupValue: groupValue,
      activeColor: accent,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      onChanged: (v) {
        if (v != null) onSelect(v);
      },
      title: Text(title, style: TextStyle(fontSize: 14, color: AppTheme.text(context))),
      subtitle: subtitle != null
          ? Text(subtitle, style: _xrayTileSubtitleStyle(context))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final core = settings.xrayCore;
    final accent = AppTheme.accent(context);

    if (_dnsServersCtrl.text.isEmpty && core.dnsServers.isNotEmpty) {
      _dnsServersCtrl.text = core.dnsServers;
    }

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        elevation: 0,
        title: Text(l10n.settingsXrayCoreTitle),
        actions: [
          TextButton(
            onPressed: () => _resetDefaults(settings),
            child: Text(
              l10n.settingsXrayResetDefaults,
              style: TextStyle(color: accent, fontSize: 13),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.settings_ethernet, size: 20, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    l10n.settingsXrayCoreIntro,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.text(context),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _XrayCoreSectionHeader(icon: Icons.dns_outlined, title: l10n.settingsXrayDnsSection),
          _xraySettingsCard(
            context,
            children: [
              SwitchListTile(
                value: core.dnsUseCustom,
                onChanged: (v) => _save(settings, core.copyWith(dnsUseCustom: v)),
                activeThumbColor: accent,
                title: Text(l10n.settingsXrayDnsCustom),
                subtitle: Text(
                  core.dnsUseCustom
                      ? l10n.settingsXrayDnsCustomHint
                      : l10n.settingsXrayDnsDefaultNote,
                  style: _xrayTileSubtitleStyle(context),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  children: [
                    _xraySettingsDivider(context),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: TextField(
                        controller: _dnsServersCtrl,
                        maxLines: 4,
                        style: TextStyle(color: AppTheme.text(context), fontSize: 13),
                        decoration: InputDecoration(
                          labelText: l10n.settingsXrayDnsServers,
                          hintText: 'https+local://1.1.1.1/dns-query',
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: AppTheme.bg(context).withValues(alpha: 0.55),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppTheme.divider(context)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppTheme.divider(context)),
                          ),
                        ),
                        onSubmitted: (v) =>
                            _save(settings, core.copyWith(dnsServers: v)),
                        onEditingComplete: () => _save(
                          settings,
                          core.copyWith(dnsServers: _dnsServersCtrl.text),
                        ),
                      ),
                    ),
                  ],
                ),
                crossFadeState: core.dnsUseCustom
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
                sizeCurve: Curves.easeOutCubic,
              ),
              _xraySettingsDivider(context),
              SwitchListTile(
                value: core.dnsSplitDirectDomains,
                onChanged: (v) =>
                    _save(settings, core.copyWith(dnsSplitDirectDomains: v)),
                activeThumbColor: accent,
                title: Text(l10n.settingsXrayDnsSplitDirect),
                subtitle: Text(
                  l10n.settingsXrayDnsSplitDirectHint,
                  style: _xrayTileSubtitleStyle(context),
                ),
              ),
              _xraySettingsDivider(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  l10n.settingsXrayDnsQueryStrategy,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text(context),
                  ),
                ),
              ),
              for (final strategy in XrayCoreSettings.dnsQueryStrategies)
                _choiceTile(
                  context: context,
                  value: strategy,
                  groupValue: core.dnsQueryStrategy,
                  accent: accent,
                  title: strategy,
                  onSelect: (v) => _save(settings, core.copyWith(dnsQueryStrategy: v)),
                ),
              _xraySettingsDivider(context),
              SwitchListTile(
                value: core.dnsDisableCache,
                onChanged: (v) =>
                    _save(settings, core.copyWith(dnsDisableCache: v)),
                activeThumbColor: accent,
                title: Text(l10n.settingsXrayDnsDisableCache),
              ),
            ],
          ),
          _XrayCoreSectionHeader(icon: Icons.merge_type, title: l10n.settingsXrayXmuxSection),
          _xraySettingsCard(
            context,
            children: [
              SwitchListTile(
                value: core.xmuxEnabled,
                onChanged: (v) => _save(settings, core.copyWith(xmuxEnabled: v)),
                activeThumbColor: accent,
                title: Text(l10n.settingsXrayXmuxEnable),
                subtitle: Text(
                  l10n.settingsXrayXmuxEnableHint,
                  style: _xrayTileSubtitleStyle(context),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _xraySettingsDivider(context),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.settingsXrayXmuxParamsTitle,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.text(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.settingsXrayXmuxParamsHint,
                            style: _xrayTileSubtitleStyle(context),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppTheme.bg(context).withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.divider(context)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _XrayCoreTextField(
                                      key: ValueKey('xmux_mc_${core.xmuxMaxConcurrency}'),
                                      label: l10n.settingsXrayXmuxMaxConcurrency,
                                      hint: '16-32',
                                      initialValue: core.xmuxMaxConcurrency,
                                      onSave: (v) => _save(
                                        settings,
                                        core.copyWith(xmuxMaxConcurrency: v),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _XrayCoreTextField(
                                      key: ValueKey('xmux_mconn_${core.xmuxMaxConnections}'),
                                      label: l10n.settingsXrayXmuxMaxConnections,
                                      hint: '0',
                                      initialValue: core.xmuxMaxConnections,
                                      onSave: (v) => _save(
                                        settings,
                                        core.copyWith(xmuxMaxConnections: v),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _XrayCoreTextField(
                                      key: ValueKey('xmux_reuse_${core.xmuxCMaxReuseTimes}'),
                                      label: l10n.settingsXrayXmuxCMaxReuseTimes,
                                      hint: '64-128',
                                      initialValue: core.xmuxCMaxReuseTimes,
                                      onSave: (v) => _save(
                                        settings,
                                        core.copyWith(xmuxCMaxReuseTimes: v),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _XrayCoreTextField(
                                      key: ValueKey('xmux_hreq_${core.xmuxHMaxRequestTimes}'),
                                      label: l10n.settingsXrayXmuxHMaxRequestTimes,
                                      hint: '600-900',
                                      initialValue: core.xmuxHMaxRequestTimes,
                                      onSave: (v) => _save(
                                        settings,
                                        core.copyWith(xmuxHMaxRequestTimes: v),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _XrayCoreTextField(
                                      key: ValueKey('xmux_hsec_${core.xmuxHMaxReusableSecs}'),
                                      label: l10n.settingsXrayXmuxHMaxReusableSecs,
                                      hint: '1800-3000',
                                      initialValue: core.xmuxHMaxReusableSecs,
                                      onSave: (v) => _save(
                                        settings,
                                        core.copyWith(xmuxHMaxReusableSecs: v),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _XrayCoreTextField(
                                      key: ValueKey('xmux_keep_${core.xmuxHKeepAlivePeriod}'),
                                      label: l10n.settingsXrayXmuxHKeepAlivePeriod,
                                      hint: '0',
                                      initialValue: core.xmuxHKeepAlivePeriod > 0
                                          ? '${core.xmuxHKeepAlivePeriod}'
                                          : '',
                                      keyboardType: TextInputType.number,
                                      onSave: (v) {
                                        final n = int.tryParse(v.trim()) ?? 0;
                                        _save(
                                          settings,
                                          core.copyWith(xmuxHKeepAlivePeriod: n),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                crossFadeState: core.xmuxEnabled
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 220),
                sizeCurve: Curves.easeOutCubic,
              ),
            ],
          ),
          _XrayCoreSectionHeader(icon: Icons.tune, title: l10n.settingsXrayGeneralSection),
          _xraySettingsCard(
            context,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  l10n.settingsXrayLogLevel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text(context),
                  ),
                ),
              ),
              for (final level in XrayCoreSettings.logLevels)
                _choiceTile(
                  context: context,
                  value: level,
                  groupValue: core.logLevel,
                  accent: accent,
                  title: level,
                  onSelect: (v) => _save(settings, core.copyWith(logLevel: v)),
                ),
              _xraySettingsDivider(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  l10n.settingsXrayDomainStrategy,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text(context),
                  ),
                ),
              ),
              for (final strategy in XrayCoreSettings.routingDomainStrategies)
                _choiceTile(
                  context: context,
                  value: strategy,
                  groupValue: core.routingDomainStrategy,
                  accent: accent,
                  title: strategy,
                  onSelect: (v) =>
                      _save(settings, core.copyWith(routingDomainStrategy: v)),
                ),
              _xraySettingsDivider(context),
              SwitchListTile(
                value: core.sniffingEnabled,
                onChanged: (v) {
                  _save(
                    settings,
                    core.copyWith(
                      sniffingEnabled: v,
                      sniffingRouteOnly: v ? core.sniffingRouteOnly : false,
                    ),
                  );
                },
                activeThumbColor: accent,
                title: Text(l10n.settingsXraySniffing),
                subtitle: Text(
                  l10n.settingsXraySniffingHint,
                  style: _xrayTileSubtitleStyle(context),
                ),
              ),
              AnimatedOpacity(
                opacity: core.sniffingEnabled ? 1 : 0.45,
                duration: const Duration(milliseconds: 180),
                child: SwitchListTile(
                  value: core.sniffingRouteOnly,
                  onChanged: core.sniffingEnabled
                      ? (v) => _save(settings, core.copyWith(sniffingRouteOnly: v))
                      : null,
                  activeThumbColor: accent,
                  title: Text(l10n.settingsXraySniffingRouteOnly),
                  subtitle: Text(
                    l10n.settingsXraySniffingRouteOnlyHint,
                    style: _xrayTileSubtitleStyle(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _resetDefaults(settings),
            icon: const Icon(Icons.restore, size: 18),
            label: Text(l10n.settingsXrayResetDefaults),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textLight(context),
              side: BorderSide(color: AppTheme.divider(context)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _XrayCoreTextField extends StatefulWidget {
  const _XrayCoreTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.onSave,
    this.keyboardType = TextInputType.text,
  });

  final String label;
  final String hint;
  final String initialValue;
  final ValueChanged<String> onSave;
  final TextInputType keyboardType;

  @override
  State<_XrayCoreTextField> createState() => _XrayCoreTextFieldState();
}

class _XrayCoreTextFieldState extends State<_XrayCoreTextField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _XrayCoreTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        _ctrl.text != widget.initialValue) {
      _ctrl.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: _ctrl,
        keyboardType: widget.keyboardType,
        style: TextStyle(color: AppTheme.text(context), fontSize: 13),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          isDense: true,
          filled: true,
          fillColor: AppTheme.card(context),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.divider(context)),
          ),
        ),
        onSubmitted: widget.onSave,
        onEditingComplete: () => widget.onSave(_ctrl.text),
      ),
    );
  }
}

String _xrayCoreSettingsSubtitle(AppLocalizations l10n, AppSettings? settings) {
  final core = settings?.xrayCore ?? const XrayCoreSettings();
  if (core == const XrayCoreSettings()) {
    return l10n.settingsXrayCoreSubtitle;
  }
  final parts = <String>[core.logLevel];
  if (core.dnsUseCustom) parts.insert(0, 'DNS');
  if (core.xmuxEnabled) parts.add('XMUX');
  return parts.join(' · ');
}

String _pingSettingsSubtitle(AppLocalizations l10n, AppSettings? settings) {
  final s = settings ?? const AppSettings();
  final mode = switch (s.pingType) {
    'url' => l10n.settingsPingMethodUrl,
    'speed' => l10n.settingsPingMethodSpeed,
    _ => l10n.settingsPingMethodTcp,
  };
  if (s.pingType != 'url') return mode;
  final target = _pingTargetLabel(l10n, s.pingTestTarget);
  return '$mode · $target';
}

String _pingTargetLabel(AppLocalizations l10n, String target) =>
    switch (PingTestConfig.normalizeTarget(target)) {
      PingTestConfig.targetGstatic => l10n.settingsPingTargetGstatic,
      PingTestConfig.targetCloudflare => l10n.settingsPingTargetCloudflare,
      PingTestConfig.targetMicrosoft => l10n.settingsPingTargetMicrosoft,
      PingTestConfig.targetCustom => l10n.settingsPingTargetCustom,
      _ => l10n.settingsPingTargetGstatic,
    };

class _PingSettingsScreen extends ConsumerStatefulWidget {
  const _PingSettingsScreen();

  @override
  ConsumerState<_PingSettingsScreen> createState() => _PingSettingsScreenState();
}

class _PingSettingsScreenState extends ConsumerState<_PingSettingsScreen> {
  final _customUrlCtrl = TextEditingController();

  @override
  void dispose() {
    _customUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(AppSettings settings) async {
    await ref.read(settingsNotifierProvider.notifier).save(settings);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final accent = AppTheme.accent(context);
    final isUrl = settings.pingType == 'url';
    final isCustom = settings.pingTestTarget == PingTestConfig.targetCustom;

    if (_customUrlCtrl.text.isEmpty && settings.pingTestUrlCustom.isNotEmpty) {
      _customUrlCtrl.text = settings.pingTestUrlCustom;
    }

    Widget sectionTitle(String title) => Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textLight(context),
              letterSpacing: 0.4,
            ),
          ),
        );

    Widget card({required List<Widget> children}) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.card(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.divider(context)),
          ),
          child: Column(children: children),
        );

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        elevation: 0,
        title: Text(l10n.settingsPingTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          sectionTitle(l10n.settingsPingMethodTitle),
          card(
            children: [
              RadioListTile<String>(
                value: 'tcp',
                groupValue: settings.pingType,
                activeColor: accent,
                onChanged: (v) {
                  if (v != null) _save(settings.copyWith(pingType: v));
                },
                title: Text(l10n.settingsPingMethodTcp),
                subtitle: Text(l10n.settingsPingMethodTcpHint),
              ),
              RadioListTile<String>(
                value: 'url',
                groupValue: settings.pingType,
                activeColor: accent,
                onChanged: (v) {
                  if (v != null) _save(settings.copyWith(pingType: v));
                },
                title: Text(l10n.settingsPingMethodUrl),
                subtitle: Text(l10n.settingsPingMethodUrlHint),
              ),
              RadioListTile<String>(
                value: 'speed',
                groupValue: settings.pingType,
                activeColor: accent,
                onChanged: (v) {
                  if (v != null) _save(settings.copyWith(pingType: v));
                },
                title: Text(l10n.settingsPingMethodSpeed),
                subtitle: Text(l10n.settingsPingMethodSpeedHint),
              ),
            ],
          ),
          if (isUrl) ...[
            sectionTitle(l10n.settingsPingTargetTitle),
            card(
              children: [
                for (final target in PingTestConfig.targets) ...[
                  if (target != PingTestConfig.targetCustom)
                    RadioListTile<String>(
                      value: target,
                      groupValue: settings.pingTestTarget,
                      activeColor: accent,
                      onChanged: (v) {
                        if (v != null) {
                          _save(settings.copyWith(pingTestTarget: v));
                        }
                      },
                      title: Text(_pingTargetLabel(l10n, target)),
                      subtitle: Text(
                        PingTestConfig.presetUrls[target] ?? '',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textLight(context),
                        ),
                      ),
                    ),
                ],
                RadioListTile<String>(
                  value: PingTestConfig.targetCustom,
                  groupValue: settings.pingTestTarget,
                  activeColor: accent,
                  onChanged: (v) {
                    if (v != null) {
                      _save(settings.copyWith(pingTestTarget: v));
                    }
                  },
                  title: Text(l10n.settingsPingTargetCustom),
                  subtitle: Text(l10n.settingsPingCustomUrlHint),
                ),
                if (isCustom)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TextField(
                      controller: _customUrlCtrl,
                      style: TextStyle(
                        color: AppTheme.text(context),
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.settingsPingCustomUrl,
                        hintText: 'https://example.com/generate_204',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onSubmitted: (v) {
                        final err = PingTestConfig.validateCustomUrl(v);
                        if (err != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.settingsPingCustomUrlInvalid)),
                          );
                          return;
                        }
                        _save(settings.copyWith(pingTestUrlCustom: v.trim()));
                      },
                      onEditingComplete: () {
                        final v = _customUrlCtrl.text;
                        final err = PingTestConfig.validateCustomUrl(v);
                        if (err != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.settingsPingCustomUrlInvalid)),
                          );
                          return;
                        }
                        _save(settings.copyWith(pingTestUrlCustom: v.trim()));
                      },
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LanSharingCard extends ConsumerStatefulWidget {
  final AsyncValue<AppSettings> settingsAsync;
  const _LanSharingCard({required this.settingsAsync});

  @override
  ConsumerState<_LanSharingCard> createState() => _LanSharingCardState();
}

class _DebugModeCard extends ConsumerWidget {
  final AsyncValue<AppSettings> settingsAsync;
  const _DebugModeCard({required this.settingsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = settingsAsync.value ?? const AppSettings();
    final enabled = settings.debugMode;

    Future<void> save(bool value) async {
      await ref.read(settingsNotifierProvider.notifier).save(settings.copyWith(debugMode: value));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: enabled ? AppTheme.orange(context).withValues(alpha: 0.55) : AppTheme.divider(context),
          width: enabled ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.orange(context).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.bug_report_outlined, size: 20, color: AppTheme.orange(context)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsDebugMode,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.text(context),
                      ),
                    ),
                    Text(
                      enabled ? l10n.settingsDebugModeOn : l10n.settingsDebugModeOff,
                      style: TextStyle(
                        fontSize: 12,
                        color: enabled ? AppTheme.orange(context) : AppTheme.textLight(context),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                activeThumbColor: AppTheme.orange(context),
                onChanged: save,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            PlatformBootstrap.isDesktop
                ? l10n.settingsDebugHintDesktop
                : l10n.settingsDebugHintMobile,
            style: TextStyle(fontSize: 12, color: AppTheme.textLight(context), height: 1.35),
          ),
          if (enabled) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _XrayLogsScreen()),
              ),
              icon: const Icon(Icons.terminal),
              label: Text(l10n.settingsOpenXrayLogs),
            ),
          ],
        ],
      ),
    );
  }
}

class _XrayLogsScreen extends ConsumerStatefulWidget {
  const _XrayLogsScreen();

  @override
  ConsumerState<_XrayLogsScreen> createState() => _XrayLogsScreenState();
}

class _XrayLogsScreenState extends ConsumerState<_XrayLogsScreen> {
  String _logs = '';
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refreshLogs();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshLogs());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLogs() async {
    try {
      final text = await DebugLogService.getXrayLogs(maxLines: 400);
      if (!mounted) return;
      setState(() {
        _logs = text.trim().isEmpty ? 'No Xray logs yet.' : text;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _logs = 'Failed to read logs: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        title: Text(l10n.settingsXrayCoreLogs),
        actions: [
          IconButton(
            tooltip: l10n.settingsRefresh,
            onPressed: _refreshLogs,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accent(context)))
          : Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.inset(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider(context)),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              _logs,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: AppTheme.text(context),
                height: 1.35,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareHwidCard extends ConsumerWidget {
  final AsyncValue<AppSettings> settingsAsync;
  const _ShareHwidCard({required this.settingsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = settingsAsync.value ?? const AppSettings();
    final enabled = settings.shareDeviceHwid;

    Future<void> save(bool value) async {
      await ref.read(settingsNotifierProvider.notifier).save(settings.copyWith(shareDeviceHwid: value));
      // Also update subscription service preference
      ref.read(subscriptionServiceProvider).updateShareDeviceHwid(value);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(18),
        border: enabled
            ? Border.all(color: AppTheme.accent(context).withValues(alpha: 0.5), width: 1.5)
            : Border.all(color: AppTheme.divider(context), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accent(context).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.fingerprint,
                  size: 20,
                  color: enabled ? AppTheme.accent(context) : AppTheme.text(context),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share device HWID',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.text(context),
                      ),
                    ),
                    Text(
                      enabled ? 'HWID will be sent with subscription requests' : 'HWID not shared',
                      style: TextStyle(
                        fontSize: 12,
                        color: enabled ? AppTheme.accent(context) : AppTheme.textLight(context),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                activeThumbColor: AppTheme.accent(context),
                onChanged: save,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'When enabled, your device\'s unique ID (HWID) is sent to subscription servers. '
            'Required by some providers for HWID binding. Disable to increase privacy.',
            style: TextStyle(fontSize: 12, color: AppTheme.textLight(context), height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _LanSharingCardState extends ConsumerState<_LanSharingCard> {
  String? _localIp;
  late TextEditingController _socksCtrl;
  late TextEditingController _httpCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.settingsAsync.value ?? const AppSettings();
    _socksCtrl = TextEditingController(text: s.lanSocksPort.toString());
    _httpCtrl = TextEditingController(text: s.lanHttpPort.toString());
    _fetchLocalIp();
  }

  @override
  void dispose() {
    _socksCtrl.dispose();
    _httpCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback &&
              (addr.address.startsWith('192.168') ||
                  addr.address.startsWith('10.') ||
                  addr.address.startsWith('172.'))) {
            if (mounted) setState(() => _localIp = addr.address);
            return;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            if (mounted) setState(() => _localIp = addr.address);
            return;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveSettings(AppSettings current, {bool? lanSharing, int? socksPort, int? httpPort}) async {
    await ref.read(settingsNotifierProvider.notifier).save(current.copyWith(
      lanSharing: lanSharing,
      lanSocksPort: socksPort,
      lanHttpPort: httpPort,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = widget.settingsAsync.value ?? const AppSettings();
    final isLan = settings.lanSharing;
    final isConnected = ref.watch(
      vpnStateProvider.select((a) {
        final status = a.value?.status;
        return status == VpnStatus.connected ||
            status == VpnStatus.connecting;
      }),
    );
    final ip = _localIp ?? '...';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(18),
        border: isLan
            ? Border.all(color: AppTheme.accent(context).withValues(alpha: 0.5), width: 1.5)
            : Border.all(color: AppTheme.divider(context), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accent(context).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lan_outlined,
                  size: 20,
                  color: isLan ? AppTheme.accent(context) : AppTheme.text(context),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.settingsLanProxyTitle,
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.text(context))),
                    Text(
                      isLan ? l10n.settingsLanSharingOnIp(ip) : l10n.settingsOff,
                      style: TextStyle(
                        fontSize: 12,
                        color: isLan ? AppTheme.accent(context) : AppTheme.textLight(context),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isLan,
                activeThumbColor: AppTheme.accent(context),
                onChanged: isConnected ? null : (_) => _saveSettings(settings, lanSharing: !isLan),
              ),
            ],
          ),
          if (isLan) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.inset(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.settingsDeviceIpListTitle,
                      style: TextStyle(fontSize: 12, color: AppTheme.textLight(context))),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        ip,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: AppTheme.text(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: ip));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.settingsIpCopied), duration: const Duration(seconds: 1)),
                          );
                        },
                        child: Icon(Icons.copy, size: 16, color: AppTheme.textLight(context)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.settingsSetupAnotherDeviceTitle,
                      style: TextStyle(fontSize: 12, color: AppTheme.textLight(context))),
                  const SizedBox(height: 4),
                  _proxyLine(context, 'SOCKS5', ip, settings.lanSocksPort),
                  const SizedBox(height: 2),
                  _proxyLine(context, 'HTTP', ip, settings.lanHttpPort),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _portField(context, l10n.settingsSocks5PortLabel, _socksCtrl, (v) {
                    final port = int.tryParse(v);
                    if (port != null && port > 0 && port < 65536) {
                      _saveSettings(settings, socksPort: port);
                    }
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _portField(context, l10n.settingsHttpPortLabel, _httpCtrl, (v) {
                    final port = int.tryParse(v);
                    if (port != null && port > 0 && port < 65536) {
                      _saveSettings(settings, httpPort: port);
                    }
                  }),
                ),
              ],
            ),
          ],
          if (isConnected && isLan)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.settingsTurnOffToChange,
                  style: TextStyle(fontSize: 11, color: AppTheme.orange(context))),
            ),
        ],
      ),
    );
  }

  Widget _proxyLine(BuildContext context, String label, String ip, int port) {
    final l10n = AppLocalizations.of(context)!;
    final text = '$ip:$port';
    return Row(
      children: [
        SizedBox(width: 52, child: Text(label, style: TextStyle(fontSize: 11, color: AppTheme.textLight(context)))),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
              color: AppTheme.text(context),
            ),
          ),
        ),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.settingsProxyCopied(label, text)), duration: const Duration(seconds: 1)),
            );
          },
          child: Icon(Icons.copy, size: 14, color: AppTheme.textLight(context)),
        ),
      ],
    );
  }

  Widget _portField(BuildContext context, String label, TextEditingController ctrl, ValueChanged<String> onSubmit) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: TextStyle(fontSize: 14, color: AppTheme.text(context)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12, color: AppTheme.textLight(context)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.textLight(context).withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.accent(context)),
        ),
        isDense: true,
      ),
      onSubmitted: onSubmit,
      onEditingComplete: () => onSubmit(ctrl.text),
    );
  }
}

class _ThemeCustomizationCard extends ConsumerWidget {
  final AsyncValue<AppSettings> settingsAsync;
  const _ThemeCustomizationCard({required this.settingsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = settingsAsync.value ?? const AppSettings();
    final preset = resolveThemePreset(settings.themePresetId);
    final modeLabel = settings.darkTheme ? l10n.themeModeDark : l10n.themeModeLight;
    final isDesktop = PlatformBootstrap.isDesktop;
    final subtitle = settings.followSystemTheme
        ? (isDesktop
            ? l10n.settingsSystemColorsSubtitle(modeLabel)
            : l10n.settingsAndroidColorsSubtitle(modeLabel))
        : '${preset.name} · $modeLabel';
    return _SettingsCard(
      title: AppLocalizations.of(context)!.settingsThemeTitle,
      subtitle: subtitle,
      icon: isDesktop ? Icons.desktop_windows_outlined : Icons.palette_outlined,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => _ThemeCustomizationScreen(settings: settings)),
      ),
    );
  }
}

class _ThemeCustomizationScreen extends ConsumerWidget {
  final AppSettings settings;
  const _ThemeCustomizationScreen({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(settingsNotifierProvider).value ?? settings;
    final previewDark = current.darkTheme;
    final controlsAccent = AppTheme.accent(context);
    final isDesktop = PlatformBootstrap.isDesktop;

    Future<void> save(AppSettings next) async {
      await ref.read(settingsNotifierProvider.notifier).save(next);
    }

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        elevation: 0,
        title: Text(l10n.themeCustomizationTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: current.followSystemTheme,
            onChanged: (v) => save(current.copyWith(followSystemTheme: v)),
            activeThumbColor: controlsAccent,
            activeTrackColor: controlsAccent.withValues(alpha: 0.32),
            secondary: Icon(
              isDesktop ? Icons.desktop_windows_outlined : Icons.android,
              color: controlsAccent,
            ),
            title: Text(
              isDesktop ? l10n.themeUseSystemColors : l10n.themeUseDynamicColors,
            ),
            subtitle: Text(
              isDesktop
                  ? l10n.themeUseSystemColorsSubtitle
                  : l10n.themeUseDynamicColorsSubtitle,
            ),
          ),
          const SizedBox(height: 12),
          _LightDarkThemeSlider(
            isDark: current.darkTheme,
            accentColor: controlsAccent,
            onChanged: (isDark) => save(current.copyWith(darkTheme: isDark)),
          ),
          const SizedBox(height: 6),
          Text(
            current.followSystemTheme
                ? (isDesktop ? l10n.themeSystemPaletteHint : l10n.themeDynamicPaletteHint)
                : l10n.themeCustomPaletteHint,
            style: TextStyle(fontSize: 12, color: AppTheme.textLight(context)),
          ),
          const SizedBox(height: 14),
          Text(l10n.themeColorThemesTitle,
              style: TextStyle(color: AppTheme.text(context), fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final crossCount = isDesktop
                  ? (maxW >= 820 ? 4 : maxW >= 560 ? 3 : 2)
                  : 2;
              final aspectRatio = isDesktop ? 1.35 : 0.72;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: kThemePresets.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  mainAxisSpacing: isDesktop ? 10 : 12,
                  crossAxisSpacing: isDesktop ? 10 : 12,
                  childAspectRatio: aspectRatio,
                ),
                itemBuilder: (context, i) {
                  final p = kThemePresets[i];
                  final selected =
                      !current.followSystemTheme && p.id == current.themePresetId;
                  final scheme = buildPresetScheme(
                    p,
                    previewDark ? Brightness.dark : Brightness.light,
                  );
                  return GestureDetector(
                    onTap: () => save(current.copyWith(themePresetId: p.id)),
                    child: _ThemePreviewCard(
                      name: p.name,
                      scheme: scheme,
                      darkPreview: previewDark,
                      selected: selected,
                      compact: isDesktop,
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LightDarkThemeSlider extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final ValueChanged<bool> onChanged;
  const _LightDarkThemeSlider({
    required this.isDark,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.inset(context);
    final border = AppTheme.divider(context);
    final thumb = accentColor;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: border),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final thumbW = (c.maxWidth - 8) / 2;
          return Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
                child: RepaintBoundary(
                  child: Container(
                    width: thumbW,
                    height: 44,
                    decoration: BoxDecoration(
                      color: thumb,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  _sliderItem(
                    context,
                    active: !isDark,
                    icon: Icons.light_mode,
                    label: AppLocalizations.of(context)!.themeModeLight,
                    onTap: () => onChanged(false),
                  ),
                  _sliderItem(
                    context,
                    active: isDark,
                    icon: Icons.dark_mode,
                    label: AppLocalizations.of(context)!.themeModeDark,
                    onTap: () => onChanged(true),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sliderItem(
      BuildContext context, {
        required bool active,
        required IconData icon,
        required String label,
        required VoidCallback onTap,
      }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: active ? AppTheme.bg(context) : AppTheme.textLight(context),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: active ? AppTheme.bg(context) : AppTheme.text(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePreviewCard extends StatelessWidget {
  final String name;
  final ColorScheme scheme;
  final bool darkPreview;
  final bool selected;
  final bool compact;
  const _ThemePreviewCard({
    required this.name,
    required this.scheme,
    required this.darkPreview,
    required this.selected,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = scheme.surface;
    final card = darkPreview ? scheme.surfaceContainer : scheme.surfaceContainerHigh;
    final cardBorder = scheme.outlineVariant.withValues(alpha: darkPreview ? 0.45 : 0.65);
    if (compact) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle : Icons.palette_outlined,
                  size: 16,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                    border: Border.all(color: cardBorder),
                  ),
                  child: Icon(Icons.play_arrow, size: 16, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _miniSubscriptionCard(
                    bg: card,
                    border: cardBorder,
                    text: scheme.onSurface,
                    subText: scheme.onSurfaceVariant,
                    accent: scheme.primary,
                    height: 24,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Center(
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: card,
                shape: BoxShape.circle,
                border: Border.all(color: cardBorder),
              ),
              child: Icon(Icons.play_arrow, size: 23, color: scheme.onSurface),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Container(
              width: 84,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Container(
            height: 2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(
                colors: [
                  scheme.secondary.withValues(alpha: 0.0),
                  scheme.secondary,
                  scheme.secondary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          _miniSubscriptionCard(
            bg: card,
            border: cardBorder,
            text: scheme.onSurface,
            subText: scheme.onSurfaceVariant,
            accent: scheme.primary,
          ),
          const SizedBox(height: 4),
          _miniSubscriptionCard(
            bg: card,
            border: cardBorder,
            text: scheme.onSurface,
            subText: scheme.onSurfaceVariant,
            accent: scheme.secondary,
          ),
          const Spacer(),
          Container(
            height: 18,
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(Icons.hub, size: 10, color: scheme.onSurface),
                Icon(Icons.public, size: 10, color: scheme.onSurfaceVariant),
                Icon(Icons.settings, size: 10, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                selected ? Icons.check : Icons.palette,
                size: 16,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniSubscriptionCard({
    required Color bg,
    required Color border,
    required Color text,
    required Color subText,
    required Color accent,
    double height = 29,
  }) {
    if (height <= 26) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        child: Row(
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.85),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: text.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: subText.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
        height: height,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 3, 4, 2),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(color: text.withValues(alpha: 0.8), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 3),
                  Container(
                    width: 26,
                    height: 2,
                    decoration: BoxDecoration(
                      color: text.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              height: 13,
              decoration: BoxDecoration(
                color: subText.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.85), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 20,
                    height: 2,
                    decoration: BoxDecoration(
                      color: text.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Container(
                    width: 11,
                    height: 1.8,
                    decoration: BoxDecoration(
                      color: subText.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 8, color: subText),
                  const SizedBox(width: 2),
                ],
              ),
            ),
          ],
        ),
      );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isDestructive;
  final VoidCallback onTap;

  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.divider(context), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isDestructive ? AppTheme.red(context) : AppTheme.accent(context)).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: isDestructive ? AppTheme.red(context) : AppTheme.text(context)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDestructive ? AppTheme.red(context) : AppTheme.text(context),
                    ),
                  ),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: AppTheme.textLight(context))),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppTheme.textLight(context)),
          ],
        ),
      ),
    );
  }
}

class _AppVersionSection extends StatelessWidget {
  const _AppVersionSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Divider(color: AppTheme.divider(context), thickness: 1),
        const SizedBox(height: 16),
        const _UpdateVersionInfo(),
      ],
    );
  }
}

class _UpdateVersionInfo extends ConsumerStatefulWidget {
  const _UpdateVersionInfo();

  @override
  ConsumerState<_UpdateVersionInfo> createState() => _UpdateVersionInfoState();
}

class _UpdateVersionInfoState extends ConsumerState<_UpdateVersionInfo> {
  String _version = '...';
  bool _forceChecking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {}
  }

  Future<void> _forceCheck() async {
    if (_forceChecking) return;
    final l10n = AppLocalizations.of(context)!;

    setState(() => _forceChecking = true);
    try {
      final info = await UpdateService.checkForUpdate(force: true);
      if (!mounted) return;

      if (info != null) {
        await showUpdateDialog(context, info);
        ref.invalidate(updateInfoProvider);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.bg(context), size: 20),
                const SizedBox(width: 10),
                Text(l10n.settingsLatestVersionInstalled),
              ],
            ),
            backgroundColor: AppTheme.green(context),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: AppTheme.bg(context), size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(l10n.settingsCheckFailedError('$e'))),
            ],
          ),
          backgroundColor: AppTheme.red(context),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _forceChecking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.text(context);
    final subtitleColor = AppTheme.textLight(context);
    final l10n = AppLocalizations.of(context)!;
    final accent = AppTheme.accent(context);
    final updateState = ref.watch(updateInfoProvider);
    final updateInfo = updateState.value;
    final checking = updateState.isLoading || _forceChecking;
    final error = updateState.hasError;
    final updateAvailable = updateInfo != null;

    Color statusColor;
    IconData statusIcon;
    if (checking) {
      statusColor = subtitleColor;
      statusIcon = Icons.hourglass_empty;
    } else if (error) {
      statusColor = AppTheme.red(context);
      statusIcon = Icons.error_outline;
    } else if (updateAvailable) {
      statusColor = accent;
      statusIcon = Icons.system_update_alt;
    } else {
      statusColor = AppTheme.green(context);
      statusIcon = Icons.check_circle_outline;
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsAppVersion,
                    style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
                  ),
                  Text(
                    'v$_version',
                    style: TextStyle(fontSize: 12, color: subtitleColor),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (checking)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: statusColor,
                      ),
                    )
                  else
                    Icon(statusIcon, size: 14, color: statusColor),
                  const SizedBox(width: 6),
                  Text(
                    checking
                        ? l10n.settingsChecking
                        : error
                            ? l10n.settingsCheckFailed
                            : updateAvailable
                                ? l10n.settingsUpdateAvailable
                                : l10n.settingsUpToDate,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: checking ? null : _forceCheck,
              icon: checking
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                    )
                  : const Icon(Icons.refresh),
              tooltip: l10n.settingsCheckForUpdates,
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.inset(context),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        if (updateInfo != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.settingsNewVersionAvailable,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'v${updateInfo.displayLatestVersion} (${updateInfo.formattedSize})',
                        style: TextStyle(fontSize: 12, color: subtitleColor),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => showUpdateDialog(context, updateInfo),
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(l10n.updateActionNow),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ignore: unused_element
class _SplitTunnelingScreen extends ConsumerWidget {
  const _SplitTunnelingScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appsAsync = ref.watch(installedAppsProvider(false));
    final splitState = ref.watch(splitTunnelingProvider);

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        title: Text('Split Tunneling', style: TextStyle(color: AppTheme.text(context))),
        iconTheme: IconThemeData(color: AppTheme.text(context)),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () => ref.read(splitTunnelingProvider.notifier).clearAll(),
            child: Text('Clear all', style: TextStyle(color: AppTheme.textLight(context))),
          ),
        ],
      ),
      body: appsAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: AppTheme.accent(context))),
        error: (e, _) => Center(child: Text('Error loading apps: $e')),
        data: (apps) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '${splitState.excludePackages.length} apps bypass VPN',
                style: TextStyle(fontSize: 12, color: AppTheme.textLight(context)),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: apps.length,
                itemBuilder: (_, i) {
                  final app = apps[i];
                  final excluded = splitState.excludePackages.contains(app.packageName);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.card(context),
                      child: Text(app.appName[0], style: TextStyle(color: AppTheme.text(context))),
                    ),
                    title: Text(app.appName, style: TextStyle(color: AppTheme.text(context), fontSize: 14)),
                    subtitle: Text(
                      app.packageName,
                      style: TextStyle(color: AppTheme.textLight(context), fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Switch(
                      value: excluded,
                      activeThumbColor: AppTheme.accent(context),
                      onChanged: (_) => ref.read(splitTunnelingProvider.notifier).toggleExclude(app.packageName),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutingScreen extends ConsumerStatefulWidget {
  const _RoutingScreen();

  @override
  ConsumerState<_RoutingScreen> createState() => _RoutingScreenState();
}

class _RoutingScreenState extends ConsumerState<_RoutingScreen> {
  late final TextEditingController _directRules;
  late final TextEditingController _proxyRules;
  late final TextEditingController _blockedRules;
  Timer? _debounce;
  String? _selectedPresetId;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsNotifierProvider).value;
    _directRules = TextEditingController(
      text: s?.directRules ?? RoutingPresets.defaultDirectRules,
    );
    _proxyRules = TextEditingController(
      text: s?.proxyRules ?? RoutingPresets.defaultProxyRules,
    );
    _blockedRules = TextEditingController(
      text: s?.blockedRules ?? RoutingPresets.defaultBlockedRules,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _directRules.dispose();
    _proxyRules.dispose();
    _blockedRules.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    setState(() {}); // keep entry counts in sync while typing
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _persist);
  }

  Future<void> _persist() async {
    final current = ref.read(settingsNotifierProvider).value;
    if (current == null) return;
    await ref.read(settingsNotifierProvider.notifier).save(
          current.copyWith(
            directRules: _directRules.text,
            proxyRules: _proxyRules.text,
            blockedRules: _blockedRules.text,
          ),
        );
  }

  TextEditingController _controllerFor(RoutingField f) => switch (f) {
        RoutingField.direct => _directRules,
        RoutingField.proxy => _proxyRules,
        RoutingField.blocked => _blockedRules,
      };

  Future<void> _applyPreset(RoutingPreset preset, String label) async {
    final ctrl = _controllerFor(preset.field);
    ctrl.text = RoutingPresets.mergeValues(ctrl.text, preset.values);
    await _persist();
    if (!mounted) return;
    setState(() {});
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settingsRoutingPresetApplied(label))),
    );
  }

  Future<void> _resetToDefaults() async {
    _directRules.text = RoutingPresets.defaultDirectRules;
    _proxyRules.text = RoutingPresets.defaultProxyRules;
    _blockedRules.text = RoutingPresets.defaultBlockedRules;
    await _persist();
    if (!mounted) return;
    setState(() {});
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settingsRoutingResetDone)),
    );
  }

  String _presetTitle(AppLocalizations l10n, String id) => switch (id) {
        'ru' => l10n.settingsRoutingPresetRuTitle,
        'ru_geoip' => l10n.settingsRoutingPresetRuGeoipTitle,
        'banks' => l10n.settingsRoutingPresetBanksTitle,
        'lan_ips' => l10n.settingsRoutingPresetLanIpsTitle,
        'ads' => l10n.settingsRoutingPresetAdsTitle,
        'streaming' => l10n.settingsRoutingPresetStreamingTitle,
        'messengers' => l10n.settingsRoutingPresetMessengersTitle,
        _ => id,
      };

  String _presetDesc(AppLocalizations l10n, String id) => switch (id) {
        'ru' => l10n.settingsRoutingPresetRuDesc,
        'ru_geoip' => l10n.settingsRoutingPresetRuGeoipDesc,
        'banks' => l10n.settingsRoutingPresetBanksDesc,
        'lan_ips' => l10n.settingsRoutingPresetLanIpsDesc,
        'ads' => l10n.settingsRoutingPresetAdsDesc,
        'streaming' => l10n.settingsRoutingPresetStreamingDesc,
        'messengers' => l10n.settingsRoutingPresetMessengersDesc,
        _ => '',
      };

  IconData _presetIcon(String id) => switch (id) {
        'ru' => Icons.flag_outlined,
        'ru_geoip' => Icons.public,
        'banks' => Icons.account_balance_outlined,
        'lan_ips' => Icons.lan_outlined,
        'ads' => Icons.block,
        'streaming' => Icons.play_circle_outline,
        'messengers' => Icons.chat_bubble_outline,
        _ => Icons.tune,
      };

  Color _presetColor(BuildContext context, RoutingField f) => switch (f) {
        RoutingField.direct => AppTheme.green(context),
        RoutingField.proxy => AppTheme.accent(context),
        RoutingField.blocked => AppTheme.red(context),
      };

  static int _countEntries(String raw) => raw
      .split(RegExp(r'[\n,]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .length;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.text(context)),
        title: Text(
          l10n.settingsRoutingTitle,
          style: TextStyle(color: AppTheme.text(context)),
        ),
        actions: [
          IconButton(
            tooltip: l10n.settingsResetRoutingTitle,
            icon: Icon(Icons.restore, color: AppTheme.text(context)),
            onPressed: _resetToDefaults,
          ),
        ],
      ),
      body: ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _intro(context, l10n),
          const SizedBox(height: 16),
          _presetsCard(context, l10n),
          const SizedBox(height: 16),
          _section(
            context: context,
            color: AppTheme.green(context),
            icon: Icons.call_made,
            title: l10n.settingsRoutingDirectTitle,
            desc: l10n.settingsRoutingDirectDesc,
            controller: _directRules,
            hint: 'ru, vk.com, .example.com, 10.0.0.0/8',
            l10n: l10n,
          ),
          const SizedBox(height: 12),
          _section(
            context: context,
            color: AppTheme.accent(context),
            icon: Icons.vpn_lock,
            title: l10n.settingsRoutingProxyTitle,
            desc: l10n.settingsRoutingProxyDesc,
            controller: _proxyRules,
            hint: 'youtube.com, discord.com, 1.1.1.1',
            l10n: l10n,
          ),
          const SizedBox(height: 12),
          _section(
            context: context,
            color: AppTheme.red(context),
            icon: Icons.block,
            title: l10n.settingsRoutingBlockTitle,
            desc: l10n.settingsRoutingBlockDesc,
            controller: _blockedRules,
            hint: 'doubleclick.net, 0.0.0.0/8',
            l10n: l10n,
          ),
          const SizedBox(height: 16),
          _syntaxLegend(context, l10n),
        ],
      ),
    );
  }

  Widget _syntaxLegend(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.help_outline, size: 18, color: AppTheme.textLight(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.settingsRoutingSyntaxHint,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppTheme.textLight(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _intro(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accent(context).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.alt_route, size: 20, color: AppTheme.accent(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.settingsRoutingHeaderDesc,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppTheme.text(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetsCard(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsRoutingPresetsTitle,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.text(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.settingsRoutingPresetsHint,
            style: TextStyle(fontSize: 11.5, color: AppTheme.textLight(context)),
          ),
          const SizedBox(height: 12),
          _presetDropdown(context, l10n),
        ],
      ),
    );
  }

  Widget _presetDropdown(BuildContext context, AppLocalizations l10n) {
    RoutingPreset? findSelected() {
      for (final p in RoutingPresets.all) {
        if (p.id == _selectedPresetId) return p;
      }
      return null;
    }

    final selected = findSelected();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppTheme.bg(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedPresetId,
                    borderRadius: BorderRadius.circular(14),
                    hint: Text(
                      l10n.settingsRoutingPresetChoose,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.textLight(context),
                      ),
                    ),
                    dropdownColor: AppTheme.card(context),
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: AppTheme.textLight(context),
                    ),
                    items: RoutingPresets.all.map((preset) {
                      final color = _presetColor(context, preset.field);
                      return DropdownMenuItem<String>(
                        value: preset.id,
                        child: Row(
                          children: [
                            Icon(_presetIcon(preset.id), size: 18, color: color),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _presetTitle(l10n, preset.id),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: AppTheme.text(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (id) => setState(() => _selectedPresetId = id),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: selected == null
                  ? null
                  : () => _applyPreset(
                        selected,
                        _presetTitle(l10n, selected.id),
                      ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.settingsRoutingPresetAdd),
            ),
          ],
        ),
        if (selected != null) ...[
          const SizedBox(height: 8),
          Text(
            _presetDesc(l10n, selected.id),
            style: TextStyle(fontSize: 11.5, color: AppTheme.textLight(context)),
          ),
        ],
      ],
    );
  }

  Widget _section({
    required BuildContext context,
    required Color color,
    required IconData icon,
    required String title,
    required String desc,
    required TextEditingController controller,
    required String hint,
    required AppLocalizations l10n,
  }) {
    final count = _countEntries(controller.text);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text(context),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l10n.settingsRoutingItemCount(count),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: TextStyle(fontSize: 11.5, color: AppTheme.textLight(context)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 8,
            style: TextStyle(fontSize: 13, color: AppTheme.text(context)),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: TextStyle(color: AppTheme.textLight(context)),
              helperText: l10n.settingsRoutingValuesHint,
              helperStyle: TextStyle(
                fontSize: 10.5,
                color: AppTheme.textLight(context),
              ),
              filled: true,
              fillColor: AppTheme.bg(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) => _scheduleSave(),
          ),
        ],
      ),
    );
  }
}
