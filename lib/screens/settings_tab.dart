import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:keqtris/keqtris.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_font.dart';
import 'package:keqdroid/models/app_info.dart';
import 'package:keqdroid/models/server_name_utils.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/app_internals.dart';
import 'package:keqdroid/models/connection_entry.dart';
import 'package:keqdroid/models/hotkey_config.dart';
import 'package:keqdroid/models/icon_shape.dart';
import 'package:keqdroid/models/ping_test_config.dart';
import 'package:keqdroid/models/routing_profile.dart';
import 'package:keqdroid/models/tun_settings.dart';
import 'package:keqdroid/models/xray_core_settings.dart';
import 'package:keqdroid/core/exceptions.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/services/app_icon_cache.dart';
import 'package:keqdroid/services/app_internals_service.dart';
import 'package:keqdroid/services/app_log_service.dart';
import 'package:keqdroid/services/file_dialog_service.dart';
import 'package:keqdroid/services/geo_base_downloader.dart';
import 'package:keqdroid/services/connections_service.dart';
import 'package:keqdroid/services/debug_log_service.dart';
import 'package:keqdroid/services/hotkey_service.dart';
import 'package:keqdroid/services/linux_autostart.dart';
import 'package:keqdroid/services/linux_firewall.dart';
import 'package:keqdroid/services/settings_backup_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/services/windows_desktop_service.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/screens/settings/connection_tile.dart';
import 'package:keqdroid/shared/ui/add_process_dialog.dart';
import 'package:keqdroid/shared/ui/app_list_tile.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/liquid_nav.dart';
import 'package:keqdroid/shared/ui/commit_on_blur.dart';
import 'package:keqdroid/shared/ui/floating_bar.dart';
import 'package:keqdroid/shared/ui/smooth_fade.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/expressive_elements.dart';
import 'package:keqdroid/shared/ui/expressive_button_group.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';
import 'package:keqdroid/shared/ui/expressive_page.dart';
import 'package:keqdroid/shared/ui/halloween/halloween_season.dart';
import 'package:keqdroid/shared/ui/horizontal_mouse_scroll.dart';
import 'package:keqdroid/shared/ui/scrolled_under.dart';
import 'package:keqdroid/shared/ui/shape_loading_indicator.dart';
import 'package:keqdroid/shared/ui/haptics.dart';
import 'package:keqdroid/shared/ui/smooth_scroll.dart';
import 'package:keqdroid/shared/ui/tv_focus.dart';
import 'package:keqdroid/services/update_service.dart';
import 'package:keqdroid/shared/ui/update_dialog.dart';
import 'package:keqdroid/utils/app_locale.dart';
import 'package:keqdroid/utils/app_routes.dart';
import 'package:keqdroid/utils/error_messages.dart';
import 'package:keqdroid/utils/bidi.dart';
import 'package:keqdroid/utils/byte_format.dart';
import 'package:keqdroid/utils/geo_asset_index.dart';
import 'package:keqdroid/utils/geo_rule_sanitizer.dart';
import 'package:keqdroid/utils/routing_presets.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/traffic_route.dart';
import 'package:keqdroid/utils/process_name_utils.dart';
import 'package:keqdroid/utils/traffic_routes.dart';
import 'package:keqdroid/utils/route_servers.dart';
import 'package:keqdroid/shared/ui/server_avatar.dart';
import 'package:keqdroid/shared/ui/server_picker_sheet.dart';
import 'package:keqdroid/shared/ui/server_row.dart';
import 'package:keqdroid/utils/rule_lists.dart';
import 'package:keqdroid/utils/split_tunneling_entries.dart';
import 'package:keqdroid/utils/time_ago.dart';
import 'package:keqdroid/services/rule_list_service.dart';
import 'package:keqdroid/utils/vpn_core_support.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/screens/split_tunneling_screen.dart';
import 'package:keqdroid/tunnel/linux_tunnel_backend.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';
import 'package:keqdroid/tunnel/local_port_plan.dart';
import 'package:keqdroid/ui/responsive/desktop_page_layout.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:keqdroid/shared/ui/liquid_toast.dart';

part 'settings/advanced_settings.dart';
part 'settings/app_internals.dart';
part 'settings/app_log.dart';
part 'settings/backup_restore.dart';
part 'settings/connections.dart';
part 'settings/custom_color_sheet.dart';
part 'settings/debug_and_logs.dart';
part 'settings/hotkey_settings.dart';
part 'settings/lan_sharing.dart';
part 'settings/local_proxy_ports.dart';
part 'settings/permissions_settings.dart';
part 'settings/ping_settings.dart';
part 'settings/routing_geo_picker.dart';
part 'settings/routing_profiles.dart';
part 'settings/routing_route_editor.dart';
part 'settings/routing_who_picker.dart';
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
                child: EdgeFadeMask(
                  bottom: 32,
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
                        style: Theme.of(context).textTheme
                            .emphasized(
                              Theme.of(context).textTheme.headlineMedium,
                            )
                            ?.copyWith(color: AppTheme.text(context)),
                      ),
                      const SizedBox(height: 20),
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
                          if (Platform.isWindows || Platform.isLinux)
                            _SettingsCard(
                              title: Platform.isLinux
                                  ? l10n.settingsDesktopTitleLinux
                                  : l10n.settingsDesktopTitle,
                              subtitle: l10n.settingsDesktopSubtitle,
                              icon: Icons.desktop_windows_rounded,
                              accent: ExpressiveAccent.secondary,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const _DesktopSettingsScreen(),
                                ),
                              ),
                            ),
                          _SettingsCard(
                            title: l10n.settingsAdvanced,
                            subtitle: l10n.settingsAdvancedSubtitle,
                            icon: Icons.tune_rounded,
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
                            icon: Icons.cloud_upload_rounded,
                            accent: ExpressiveAccent.secondary,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const _BackupRestoreScreen(),
                              ),
                            ),
                          ),
                          _SettingsCard(
                            title: l10n.settingsInternalsTitle,
                            subtitle: l10n.settingsInternalsSubtitle,
                            icon: Icons.info_rounded,
                            accent: ExpressiveAccent.tertiary,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const _AppInternalsScreen(),
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
              ),
              const _AppVersionSection(),
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
      icon: Icons.translate_rounded,
      accent: ExpressiveAccent.tertiary,
      onTap: () => _showLanguageSheet(context, ref, settings),
    );
  }

  void _showLanguageSheet(
    BuildContext context,
    WidgetRef ref,
    AppSettings current,
  ) {
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
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(ExpressiveShape.extraLarge),
                ),
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
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                        final scheme = Theme.of(context).colorScheme;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: selected
                                ? scheme.secondaryContainer
                                : scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(
                              ExpressiveShape.large,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                ExpressiveShape.large,
                              ),
                              onTap: () async {
                                await ref
                                    .read(settingsNotifierProvider.notifier)
                                    .save(
                                      current.copyWith(appLanguageCode: code),
                                    );
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
                                        style:
                                            (selected
                                                    ? textTheme.emphasized(
                                                        textTheme.bodyLarge,
                                                      )
                                                    : textTheme.bodyLarge)
                                                ?.copyWith(
                                                  color: selected
                                                      ? scheme
                                                            .onSecondaryContainer
                                                      : AppTheme.text(context),
                                                ),
                                      ),
                                    ),
                                    if (selected)
                                      Icon(
                                        Icons.check_circle_rounded,
                                        color: scheme.onSecondaryContainer,
                                        size: 22,
                                      ),
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
      icon: Icons.alt_route_rounded,
      accent: ExpressiveAccent.tertiary,
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
    final textTheme = Theme.of(context).textTheme;

    return ExpressiveGroupTile(
      onTap: onTap,
      child: Row(
        children: [
          ExpressiveIconBadge(icon: icon, accent: accent),
          const SizedBox(width: ExpressiveSpacing.large),
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
          Icon(Icons.chevron_right_rounded, color: AppTheme.textLight(context)),
        ],
      ),
    );
  }
}

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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: textColor),
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
            foregroundColor: AppTheme.onRed(context),
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
    final style = FloatingBar.shown(context) ? FloatingBar.styleOf(context) : null;
    final floating = style != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        // лента здесь стоит по центру, и версия встаёт по бокам от неё, если влезает
        final half = style == null
            ? 0.0
            : (constraints.maxWidth -
                    2 * (FloatingBar.margin + LiquidBottomNav.sideGap(style)) -
                    LiquidBottomNav.restWidth(
                      context,
                      AppLocalizations.of(context)!.navSettings,
                    )) /
                2;
        if (style != null && half >= 72) {
          return Padding(
            padding: const EdgeInsets.only(bottom: FloatingBar.bottomMargin),
            child: const _UpdateVersionInfo(split: true),
          );
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(
            tabContentHorizontalInset(),
            0,
            tabContentHorizontalInset(),
            24 + (floating ? FloatingBar.bottomMargin + FloatingBar.height : 0),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              const _UpdateVersionInfo(),
            ],
          ),
        );
      },
    );
  }
}

class _UpdateVersionInfo extends ConsumerStatefulWidget {
  const _UpdateVersionInfo({this.split = false});

  final bool split;

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

  @override
  void dispose() {
    if (FloatingBar.side.value?.owner == this) FloatingBar.side.value = null;
    super.dispose();
  }

  // панель живёт в другом поддереве: менять её посреди нашей сборки нельзя
  void _publishSide(FloatingSide? side) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (side != null || FloatingBar.side.value?.owner == this) {
        FloatingBar.side.value = side;
      }
    });
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
        viaLocalProxy: vpn?.status == VpnStatus.connected,
        // порт сессии: если настроенный был занят, ядро слушает другой
        httpPort: ActiveLocalPorts().httpPortOr(settings.httpPort),
      );
      if (!mounted) return;

      if (info != null) {
        await showUpdateDialog(context, info);
        ref.invalidate(updateInfoProvider);
      } else if (mounted) {
        AppSnack.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.bg(context),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(l10n.settingsLatestVersionInstalled),
              ],
            ),
            backgroundColor: AppTheme.green(context),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ExpressiveShape.medium),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppSnack.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: AppTheme.bg(context),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(l10n.settingsCheckFailedError('$e'))),
            ],
          ),
          backgroundColor: AppTheme.red(context),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ExpressiveShape.medium),
          ),
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
      statusIcon = Icons.hourglass_empty_rounded;
    } else if (error) {
      statusColor = AppTheme.red(context);
      statusIcon = Icons.error_outline_rounded;
    } else if (updateAvailable) {
      statusColor = accent;
      statusIcon = Icons.system_update_alt_rounded;
    } else {
      statusColor = AppTheme.green(context);
      statusIcon = Icons.check_circle_outline_rounded;
    }

    final onContainer = Theme.of(context).colorScheme.onSecondaryContainer;
    final statusLabel = checking
        ? l10n.settingsChecking
        : error
        ? l10n.settingsCheckFailed
        : updateAvailable
        ? l10n.settingsUpdateAvailable
        : l10n.settingsUpToDate;
    final textTheme = Theme.of(context).textTheme;

    final Widget statusIndicator = checking
        ? ShapeLoadingIndicator(
            size: ExpressiveIconSize.inline,
            color: statusColor,
          )
        : Icon(
            statusIcon,
            size: ExpressiveIconSize.inline,
            color: statusColor,
          );
    final checkButton = IconButton.filledTonal(
      onPressed: checking ? null : _forceCheck,
      icon: checking
          ? ShapeLoadingIndicator(
              size: ExpressiveIconSize.large,
              color: accent,
            )
          : const Icon(Icons.refresh_rounded),
      tooltip: l10n.settingsCheckForUpdates,
    );
    final updateCard = updateInfo == null
        ? null
        : Container(
            padding: const EdgeInsets.all(ExpressiveSpacing.large),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: ExpressiveShape.radius(ExpressiveShape.large),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.settingsNewVersionAvailable,
                        style: textTheme.titleSmall?.copyWith(
                          color: onContainer,
                        ),
                      ),
                      const SizedBox(height: ExpressiveSpacing.hairline),
                      Text(
                        'v${updateInfo.displayLatestVersion} (${updateInfo.formattedSize})',
                        style: textTheme.bodySmall?.copyWith(
                          color: onContainer.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: ExpressiveSpacing.medium),
                FilledButton.icon(
                  onPressed: () => showUpdateDialog(context, updateInfo),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(l10n.updateActionNow),
                ),
              ],
            ),
          );

    if (widget.split) {
      // рядом с лентой места на подписи статуса нет: он в цвете плитки и в подсказке.
      // сами плитки рисует нижняя панель, здесь только место под них
      final scheme = Theme.of(context).colorScheme;
      final (Color? tile, Color ink) = error
          ? (scheme.errorContainer, scheme.onErrorContainer)
          : updateAvailable
          ? (scheme.tertiary, scheme.onTertiary)
          : (null, textColor);
      _publishSide(FloatingSide(
        owner: this,
        start: Text(
          ltrIsolate('v$_version'),
          style: textTheme.emphasized(textTheme.titleSmall)?.copyWith(color: ink),
        ),
        end: checkButton,
        startColor: tile,
        startTooltip: statusLabel,
        onStartTap: checking
            ? null
            : updateInfo != null
            ? () => showUpdateDialog(context, updateInfo)
            : _forceCheck,
      ));
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (updateCard != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FloatingBar.margin,
                0,
                FloatingBar.margin,
                ExpressiveSpacing.medium,
              ),
              child: updateCard,
            ),
          const SizedBox(height: FloatingBar.height),
        ],
      );
    }

    _publishSide(null);
    return ExpressiveCard(
      child: Column(
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
                      style: textTheme
                          .emphasized(textTheme.titleMedium)
                          ?.copyWith(color: textColor),
                    ),
                    const SizedBox(height: ExpressiveSpacing.hairline),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: ExpressiveSpacing.small,
                      children: [
                        Text(
                          ltrIsolate('v$_version'),
                          style: textTheme.bodyMedium?.copyWith(
                            color: subtitleColor,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            statusIndicator,
                            const SizedBox(width: ExpressiveSpacing.extraSmall),
                            Text(
                              statusLabel,
                              style: textTheme.labelLarge?.copyWith(
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ExpressiveSpacing.small),
              checkButton,
            ],
          ),
          if (updateCard != null) ...[
            const SizedBox(height: ExpressiveSpacing.large),
            updateCard,
          ],
        ],
      ),
    );
  }
}
