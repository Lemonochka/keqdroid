part of '../settings_tab.dart';

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
    // Сохранение при уходе с экрана: «назад» без Enter не должен молча
    // терять введённые порты.
    _persistSilently();
    _socksCtrl.dispose();
    _httpCtrl.dispose();
    super.dispose();
  }

  /// Тихое сохранение валидных портов без снекбаров (контекст экрана уже
  /// умирает). Невалидный ввод просто отбрасывается.
  void _persistSilently() {
    if (!_initialized) return;
    final settings = ref.read(settingsNotifierProvider).value;
    if (settings == null) return;
    final vpn = ref.read(vpnStateProvider).value?.status;
    if (vpn == VpnStatus.connected || vpn == VpnStatus.connecting) return;
    final socks = int.tryParse(_socksCtrl.text.trim());
    final http = int.tryParse(_httpCtrl.text.trim());
    bool valid(int? p) => p != null && p > 0 && p < 65536;
    if (!valid(socks) || !valid(http) || socks == http) return;
    if (socks == settings.localPort && http == settings.httpPort) return;
    unawaited(ref.read(settingsNotifierProvider.notifier).save(
          settings.copyWith(localPort: socks, httpPort: http),
        ));
  }

  void _syncControllers(AppSettings settings) {
    if (_initialized) return;
    _socksCtrl.text = settings.localPort.toString();
    _httpCtrl.text = settings.httpPort.toString();
    _initialized = true;
  }

  Future<void> _apply(AppSettings settings) async {
    if (!mounted) return;
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
    // Применение и по потере фокуса, а не только по Enter: тап мимо поля
    // или переход к другому полю не должен молча терять введённое значение.
    return Focus(
      skipTraversal: true,
      onFocusChange: (focused) {
        if (!focused) onSubmit();
      },
      child: TextField(
        controller: ctrl,
        enabled: enabled,
        keyboardType: TextInputType.number,
        style: TextStyle(fontSize: 14, color: AppTheme.text(context)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              TextStyle(fontSize: 12, color: AppTheme.textLight(context)),
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
      ),
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
      body: SmoothScroll(
        builder: (context, controller) => ListView(
          controller: controller,
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
      ),
    );
  }
}
