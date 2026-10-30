part of '../settings_tab.dart';

class _PermissionsScreen extends ConsumerStatefulWidget {
  const _PermissionsScreen();

  @override
  ConsumerState<_PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<_PermissionsScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('keqdis_vpn_channel');
  bool? _notifEnabled;
  bool? _batteryUnrestricted;

  String? _autostart;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshNotifStatus();
    _refreshBatteryStatus();
    _loadAutostart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotifStatus();
      _refreshBatteryStatus();
    }
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

  Future<void> _refreshBatteryStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      if (mounted) setState(() => _batteryUnrestricted = ok ?? false);
    } catch (_) {
      if (mounted) setState(() => _batteryUnrestricted = null);
    }
  }

  Future<void> _requestBattery() async {
    try {
      await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  Future<void> _openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } catch (_) {}
  }

  Future<void> _loadAutostart() async {
    if (!Platform.isAndroid) return;
    try {
      final kind = await _channel.invokeMethod<String>('getOemAutostart');
      if (mounted) setState(() => _autostart = kind == 'none' ? null : kind);
    } catch (_) {}
  }

  Future<void> _openAutostart() async {
    if (_autostart == 'appDetails') {
      final l10n = AppLocalizations.of(context)!;
      final material = MaterialLocalizations.of(context);
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.settingsPermAutostartTitle),
          content: Text(l10n.settingsPermAutostartHint),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(material.cancelButtonLabel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(material.continueButtonLabel),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    try {
      await _channel.invokeMethod<void>('openOemAutostart');
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
      ExpressiveCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Icon(Icons.notifications_active_rounded, color: accent),
              title: Text(l10n.settingsPermNotifTitle),
              subtitle: Text(l10n.settingsPermNotifDesc),
              trailing: _statusChip(granted),
              onTap: granted ? _openAppSettings : _requestNotif,
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Icon(Icons.battery_saver_rounded, color: accent),
              title: Text(l10n.settingsPermBatteryTitle),
              subtitle: Text(l10n.settingsPermBatteryDesc),
              trailing: _statusChip(_batteryUnrestricted == true),
              onTap: _batteryUnrestricted == true
                  ? _openAppSettings
                  : _requestBattery,
            ),
            if (_autostart != null)
              _PermissionInfoTile(
                icon: Icons.rocket_launch_rounded,
                title: l10n.settingsPermAutostartTitle,
                subtitle: l10n.settingsPermAutostartDesc,
                onTap: _openAutostart,
                accent: true,
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

  final bool accent;

  const _PermissionInfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(
        icon,
        color: accent ? AppTheme.accent(context) : AppTheme.textLight(context),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.open_in_new_rounded, size: 18, color: AppTheme.textLight(context)),
      onTap: onTap,
    );
  }
}

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
    setState(() {
      _installed = LinuxTunnelBackend.isPasswordlessTunInstalled();
      _busy = false;
    });
    AppSnack.of(context).showSnackBar(
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
    );
  }
}
