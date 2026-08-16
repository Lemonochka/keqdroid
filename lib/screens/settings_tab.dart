import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_font.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/connection_entry.dart';
import 'package:keqdroid/models/hotkey_config.dart';
import 'package:keqdroid/models/ping_test_config.dart';
import 'package:keqdroid/models/routing_rule.dart';
import 'package:keqdroid/models/tun_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/connections_service.dart';
import 'package:keqdroid/services/debug_log_service.dart';
import 'package:keqdroid/services/hotkey_service.dart';
import 'package:keqdroid/services/settings_backup_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/services/windows_desktop_service.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/screens/settings/connection_tile.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';
import 'package:keqdroid/shared/ui/smooth_scroll.dart';
import 'package:keqdroid/services/update_service.dart';
import 'package:keqdroid/shared/ui/update_dialog.dart';
import 'package:keqdroid/utils/app_locale.dart';
import 'package:keqdroid/utils/bidi.dart';
import 'package:keqdroid/utils/awg_profile.dart';
import 'package:keqdroid/utils/local_vpn_proxy.dart';
import 'package:keqdroid/utils/geo_asset_index.dart';
import 'package:keqdroid/utils/geo_rule_sanitizer.dart';
import 'package:keqdroid/utils/routing_presets.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/screens/split_tunneling_screen.dart';
import 'package:keqdroid/tunnel/linux_tunnel_backend.dart';
import 'package:keqdroid/ui/responsive/desktop_page_layout.dart';
import 'package:package_info_plus/package_info_plus.dart';

part 'settings/advanced_settings.dart';
part 'settings/backup_restore.dart';
part 'settings/connections.dart';
part 'settings/debug_and_logs.dart';
part 'settings/hotkey_settings.dart';
part 'settings/lan_sharing.dart';
part 'settings/local_proxy_ports.dart';
part 'settings/permissions_settings.dart';
part 'settings/ping_settings.dart';
part 'settings/routing_rule_editor.dart';
part 'settings/routing_screen.dart';
part 'settings/share_hwid.dart';
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
                    // Заголовок экрана — headline, а не title: у M3E крупный
                    // заголовок и есть якорь иерархии страницы.
                    style: Theme.of(context).textTheme
                        .emphasized(Theme.of(context).textTheme.headlineMedium)
                        ?.copyWith(color: AppTheme.text(context)),
                  ),
                  const SizedBox(height: 20),
                  // Containment: пункты собраны в группы по смыслу — «как
                  // выглядит», «как ходит трафик», «данные». Прежние шесть
                  // одинаковых карточек с равными зазорами не говорили о
                  // связях между пунктами вообще.
                  ExpressiveGroup(
                    children: [
                      _ThemeCustomizationCard(settingsAsync: settingsAsync),
                      _LanguageSettingsCard(settingsAsync: settingsAsync),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ExpressiveGroup(
                    children: [
                      _LanSharingCard(settingsAsync: settingsAsync),
                      const _SplitTunnelingSettingsCard(),
                      if (Platform.isWindows)
                        _SettingsCard(
                          title: l10n.settingsDesktopTitle,
                          subtitle: l10n.settingsDesktopSubtitle,
                          icon: Icons.desktop_windows_outlined,
                          accent: ExpressiveAccent.secondary,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const _WindowsDesktopSettingsScreen(),
                            ),
                          ),
                        ),
                      _SettingsCard(
                        title: l10n.settingsAdvanced,
                        subtitle: l10n.settingsAdvancedSubtitle,
                        icon: Icons.tune,
                        accent: ExpressiveAccent.primary,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const _AdvancedSettingsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ExpressiveGroup(
                    children: [
                      _SettingsCard(
                        title: l10n.settingsBackupRestore,
                        subtitle: l10n.settingsBackupRestoreSubtitle,
                        icon: Icons.cloud_upload_outlined,
                        accent: ExpressiveAccent.secondary,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const _BackupRestoreScreen(),
                          ),
                        ),
                      ),
                    ],
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
      accent: ExpressiveAccent.tertiary,
      onTap: () => _showLanguageSheet(context, ref, settings),
    );
  }

  void _showLanguageSheet(BuildContext context, WidgetRef ref, AppSettings current) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final options = <(String code, String label)>[
      ('system', l10n.settingsLanguageSystem),
      ('en', l10n.settingsLanguageEnglish),
      ('ru', l10n.settingsLanguageRussian),
      ('de', l10n.settingsLanguageGerman),
      ('zh', l10n.settingsLanguageChinese),
      ('fa', l10n.settingsLanguageFarsi),
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
            // Прозрачный фон здесь намеренный: DraggableScrollableSheet тянется
            // за палец и рисует свой контейнер сам. Но цвет и форма обязаны
            // совпадать с теми, что тема даёт остальным шторкам, иначе
            // единственная «тянущаяся» шторка выглядит чужой.
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(ExpressiveShape.extraLarge)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.divider(context),
                      borderRadius: BorderRadius.circular(ExpressiveShape.full),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text(
                      l10n.settingsLanguageSheetTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppTheme.text(context)),
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
                        final scheme = Theme.of(context).colorScheme;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          // Пункты — на уровень ВЫШЕ шторки, а не на фоне
                          // страницы. Здесь стоял AppTheme.bg, то есть surface,
                          // а в AMOLED-режиме это чистый чёрный: карточки
                          // оказывались темнее собственного родителя (перевёрнутая
                          // тональная иерархия M3) и попадали в ту полосу яркости,
                          // где OLED-панель сильнее всего смазывает движение и
                          // уводит почти-чёрный в фиолетовый. Заодно уходит
                          // полупрозрачная заливка выбранного: альфа поверх
                          // чёрного этот же эффект усиливает.
                          child: Material(
                            color: selected
                                ? scheme.secondaryContainer
                                : scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(ExpressiveShape.large),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(ExpressiveShape.large),
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
                                        // Вес — из шкалы, а не руками: у
                                        // выбранного усиленный вариант роли.
                                        style: (selected
                                                ? textTheme.emphasized(
                                                    textTheme.bodyLarge)
                                                : textTheme.bodyLarge)
                                            ?.copyWith(
                                          color: selected
                                              ? scheme.onSecondaryContainer
                                              : AppTheme.text(context),
                                        ),
                                      ),
                                    ),
                                    if (selected)
                                      Icon(Icons.check_circle,
                                          color: scheme.onSecondaryContainer,
                                          size: 22),
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
      accent: ExpressiveAccent.tertiary,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SplitTunnelingScreen()),
      ),
    );
  }
}

/// Пункт настроек — сегмент [ExpressiveGroup].
///
/// Форму берёт от группы (крупные внешние углы, почти квадратные стыки), цвет
/// иконки — от [accent]: у M3E раскрашенная иконка-контейнер и есть то, что
/// позволяет находить нужный пункт «в четыре раза быстрее», а не читать список
/// сверху вниз.
class _SettingsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final ExpressiveAccent accent;
  final VoidCallback onTap;

  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.accent = ExpressiveAccent.primary,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ExpressiveGroupTile(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.container(scheme),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: accent.onContainer(scheme)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    color: AppTheme.text(context),
                  ),
                ),
                Text(
                  subtitle,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textLight(context),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppTheme.textLight(context)),
        ],
      ),
    );
  }
}

/// Общий диалог подтверждения для деструктивных действий (сброс настроек).
/// Возвращает true, если пользователь подтвердил. Виден всем part-файлам
/// настроек (advanced/local ports/xray core).
Future<bool> _confirmReset(
  BuildContext context, {
  required String message,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final cardColor = AppTheme.card(context);
  final textColor = AppTheme.text(context);
  final textLightColor = AppTheme.textLight(context);
  final redColor = AppTheme.red(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: cardColor,
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: redColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.settingsResetConfirmTitle,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: textColor),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: TextStyle(color: textLightColor, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            l10n.subscriptionsCancel,
            style: TextStyle(color: textLightColor),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: redColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ExpressiveShape.medium),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            l10n.settingsResetConfirmAction,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
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
      final activeServer = ref.read(serversProvider).activeServer;
      final settings = await ref.read(storageProvider).getSettings();
      final info = await UpdateService.checkForUpdate(
        force: true,
        viaLocalProxy: tunnelHasLocalHttpProxy(
          vpnConnected: vpn?.status == VpnStatus.connected,
          awgBackend: activeServer != null &&
              AwgProfile.isAwgConfig(activeServer.config),
        ),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ExpressiveShape.medium)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ExpressiveShape.medium)),
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
                    ltrIsolate('v$_version'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: subtitleColor),
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
                    borderRadius: BorderRadius.circular(ExpressiveShape.large),
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
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: statusColor),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ExpressiveShape.medium)),
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
              borderRadius: BorderRadius.circular(ExpressiveShape.medium),
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: textColor),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'v${updateInfo.displayLatestVersion} (${updateInfo.formattedSize})',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: subtitleColor),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ExpressiveShape.medium)),
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

