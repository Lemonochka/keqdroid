part of '../settings_tab.dart';

/// Экран «Разрешения»: системные разрешения, которые требует приложение и
/// которые пользователь может отозвать. Уведомления показываем с реальным
/// статусом; остальные (камера/телефон/установка) — с входом в системные
/// настройки приложения, где их отзывают. На Linux сюда же вынесен root для TUN.
class _PermissionsScreen extends ConsumerStatefulWidget {
  const _PermissionsScreen();

  @override
  ConsumerState<_PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<_PermissionsScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('keqdis_vpn_channel');
  bool? _notifEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshNotifStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Вернулись из системных настроек — статус разрешения мог измениться.
    if (state == AppLifecycleState.resumed) _refreshNotifStatus();
  }

  AndroidFlutterLocalNotificationsPlugin? get _androidNotif =>
      FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

  Future<void> _refreshNotifStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final enabled = await _androidNotif?.areNotificationsEnabled();
      if (mounted) setState(() => _notifEnabled = enabled ?? false);
    } catch (_) {
      if (mounted) setState(() => _notifEnabled = null);
    }
  }

  Future<void> _requestNotif() async {
    try {
      await _androidNotif?.requestNotificationsPermission();
    } catch (_) {}
    await _refreshNotifStatus();
  }

  Future<void> _openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ExpressivePage(
      title: l10n.settingsPermissionsTitle,
      physics: const ClampingScrollPhysics(),
      children: [
        if (Platform.isAndroid) ..._androidPermissions(l10n),
        if (Platform.isLinux) ..._linuxPermissions(l10n),
      ],
    );
  }

  List<Widget> _androidPermissions(AppLocalizations l10n) {
    final accent = AppTheme.accent(context);
    final granted = _notifEnabled == true;
    return [
      // Строки разрешений — в контейнере, как везде в настройках: голыми на
      // фоне этот экран выпадал из общей раскладки.
      ExpressiveCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // Уведомления — единственное разрешение с реальным статусом/запросом.
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Icon(Icons.notifications_active_rounded, color: accent),
              title: Text(l10n.settingsPermNotifTitle),
              subtitle: Text(l10n.settingsPermNotifDesc),
              trailing: _statusChip(granted),
              onTap: granted ? _openAppSettings : _requestNotif,
            ),
            _PermissionInfoTile(
              icon: Icons.qr_code_scanner_rounded,
              title: l10n.settingsPermCameraTitle,
              subtitle: l10n.settingsPermCameraDesc,
              onTap: _openAppSettings,
            ),
            _PermissionInfoTile(
              icon: Icons.system_update_rounded,
              title: l10n.settingsPermInstallTitle,
              subtitle: l10n.settingsPermInstallDesc,
              onTap: _openAppSettings,
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: _openAppSettings,
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(l10n.settingsPermOpenAppSettings),
          style: TextButton.styleFrom(foregroundColor: accent),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        child: Text(
          l10n.settingsPermRevokeHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textLight(context)),
        ),
      ),
    ];
  }

  List<Widget> _linuxPermissions(AppLocalizations l10n) {
    return [
      // Разделителя между платформами больше нет: секцию отбивает её
      // собственный заголовок, ровно как на остальных экранах настроек.
      _sectionHeader(l10n.settingsPermTunHeader),
      const ExpressiveCard(
        padding: EdgeInsets.zero,
        child: _LinuxTunPasswordlessTile(),
      ),
    ];
  }

  Widget _sectionHeader(String text) => ExpressiveSectionHeader(text);

  Widget _statusChip(bool granted) {
    final l10n = AppLocalizations.of(context)!;
    final color = granted ? AppTheme.green(context) : AppTheme.red(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(ExpressiveShape.medium),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        granted ? l10n.settingsPermStatusGranted : l10n.settingsPermStatusDenied,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}

class _PermissionInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _PermissionInfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, color: AppTheme.textLight(context)),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.open_in_new_rounded, size: 18, color: AppTheme.textLight(context)),
      onTap: onTap,
    );
  }
}

/// Linux: тумблер беспарольного TUN. Установка/удаление правки требуют root —
/// каждое переключение поднимает разовый polkit-запрос пароля.
class _LinuxTunPasswordlessTile extends ConsumerStatefulWidget {
  const _LinuxTunPasswordlessTile();

  @override
  ConsumerState<_LinuxTunPasswordlessTile> createState() =>
      _LinuxTunPasswordlessTileState();
}

class _LinuxTunPasswordlessTileState
    extends ConsumerState<_LinuxTunPasswordlessTile> {
  late bool _installed = LinuxTunnelBackend.isPasswordlessTunInstalled();
  bool _busy = false;

  Future<void> _toggle(bool enable) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    final ok = enable
        ? await LinuxTunnelBackend.installPasswordlessTun()
        : await LinuxTunnelBackend.removePasswordlessTun();
    if (!mounted) return;
    // Ручное управление гасит авто-предложение в любом случае.
    final current = ref.read(settingsNotifierProvider).value;
    if (current != null && !current.linuxTunRememberDismissed) {
      await ref
          .read(settingsNotifierProvider.notifier)
          .save(current.copyWith(linuxTunRememberDismissed: true));
    }
    if (!mounted) return;
    setState(() {
      _installed = LinuxTunnelBackend.isPasswordlessTunInstalled();
      _busy = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (enable
                  ? l10n.tunRememberInstalled
                  : l10n.settingsPermTunDisabled)
              : l10n.tunRememberFailed,
        ),
        backgroundColor: ok ? AppTheme.green(context) : AppTheme.red(context),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = AppTheme.accent(context);
    return SwitchListTile(
      value: _installed,
      onChanged: _busy ? null : _toggle,
      activeThumbColor: accent,
      activeTrackColor: accent.withValues(alpha: 0.32),
      secondary: _busy
          ? ShapeLoadingIndicator(size: 24, color: accent)
          : Icon(Icons.lock_open_rounded, color: accent),
      title: Text(l10n.settingsPermTunPasswordlessTitle),
      subtitle: Text(l10n.settingsPermTunPasswordlessSubtitle),
    );
  }
}
