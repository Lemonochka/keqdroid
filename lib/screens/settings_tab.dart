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
import 'package:keqdroid/shared/ui/smooth_scroll.dart';
import 'package:keqdroid/services/update_service.dart';
import 'package:keqdroid/shared/ui/update_dialog.dart';
import 'package:keqdroid/utils/app_locale.dart';
import 'package:keqdroid/utils/routing_presets.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/split_tunneling_screen.dart';
import 'package:keqdroid/ui/responsive/desktop_page_layout.dart';
import 'package:package_info_plus/package_info_plus.dart';

part 'settings/advanced_settings.dart';
part 'settings/backup_restore.dart';
part 'settings/debug_and_logs.dart';
part 'settings/lan_sharing.dart';
part 'settings/local_proxy_ports.dart';
part 'settings/ping_settings.dart';
part 'settings/routing_screen.dart';
part 'settings/share_hwid.dart';
part 'settings/split_tunneling.dart';
part 'settings/theme_customization.dart';
part 'settings/windows_desktop_settings.dart';
part 'settings/xray_core_settings.dart';

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
              child: SmoothScroll(
                builder: (context, controller) => ListView(
                  controller: controller,
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
      final vpn = ref.read(vpnStateProvider).value;
      final settings = await ref.read(storageProvider).getSettings();
      final info = await UpdateService.checkForUpdate(
        force: true,
        vpnConnected: vpn?.status == VpnStatus.connected,
        httpPort: settings.httpPort,
      );
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
          crossAxisAlignment: CrossAxisAlignment.center,
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.inset(context),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
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

