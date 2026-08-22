part of '../settings_tab.dart';

/// Локальные порты SOCKS5/HTTP — секция экрана настроек ядра
/// ([_XrayCoreSettingsScreen]), а не отдельный экран: порты едут в те же
/// inbounds генерируемого конфига, что и остальные параметры ядра.
/// Отдельной кнопки сброса нет — порты возвращает к дефолту общий сброс
/// экрана (`_resetDefaults` там же), поэтому поля умеют подхватывать
/// изменение настроек извне.
class _LocalPortsSection extends ConsumerStatefulWidget {
  const _LocalPortsSection();

  @override
  ConsumerState<_LocalPortsSection> createState() => _LocalPortsSectionState();
}

class _LocalPortsSectionState extends ConsumerState<_LocalPortsSection> {
  final _socksCtrl = TextEditingController();
  final _httpCtrl = TextEditingController();
  final _socksFocus = FocusNode();
  final _httpFocus = FocusNode();
  late final VoidCallback _socksBlur;
  late final VoidCallback _httpBlur;
  bool _initialized = false;

  // Снимок для dispose(). Трогать там `ref` нельзя: Riverpod помечает элемент
  // defunct в super.unmount() ДО State.dispose(), а watch-подписки закрывает
  // ПОСЛЕ него — брошенный из ref.read StateError обрывает unmount, подписки
  // остаются живыми на мёртвом элементе, и дальше каждое изменение любого
  // провайдера валится ассертом markNeedsBuild на defunct-элементе.
  SettingsNotifier? _settingsNotifier;
  AppSettings? _lastSettings;
  bool _portsLocked = false;

  @override
  void initState() {
    super.initState();
    // Применение по потере фокуса, а не только по Enter: тап мимо поля или
    // переход к соседнему не должен молча терять введённое значение.
    VoidCallback blurListener(FocusNode focus) => () {
          if (focus.hasFocus) return;
          final settings = ref.read(settingsNotifierProvider).value;
          if (settings != null) unawaited(_apply(settings));
        };
    _socksFocus.addListener(_socksBlur = blurListener(_socksFocus));
    _httpFocus.addListener(_httpBlur = blurListener(_httpFocus));
  }

  @override
  void dispose() {
    // Слушатели снимаем ПЕРВЫМИ: FocusNode.dispose() снимает фокус и дёрнул бы
    // _apply, который лезет в context (снекбары) уже на умирающем экране.
    _socksFocus.removeListener(_socksBlur);
    _httpFocus.removeListener(_httpBlur);
    // Сохранение при уходе с экрана: «назад» без Enter не должен молча
    // терять введённые порты.
    _persistSilently();
    _socksFocus.dispose();
    _httpFocus.dispose();
    _socksCtrl.dispose();
    _httpCtrl.dispose();
    super.dispose();
  }

  /// Тихое сохранение валидных портов без снекбаров (контекст экрана уже
  /// умирает). Невалидный ввод просто отбрасывается. Работает только по
  /// снимку из build — см. комментарий у полей.
  void _persistSilently() {
    if (!_initialized || _portsLocked) return;
    final settings = _lastSettings;
    final notifier = _settingsNotifier;
    if (settings == null || notifier == null) return;
    final socks = int.tryParse(_socksCtrl.text.trim());
    final http = int.tryParse(_httpCtrl.text.trim());
    bool valid(int? p) => p != null && p > 0 && p < 65536;
    if (!valid(socks) || !valid(http) || socks == http) return;
    if (socks == settings.localPort && http == settings.httpPort) return;
    unawaited(notifier.save(
      settings.copyWith(localPort: socks, httpPort: http),
    ));
  }

  /// Внешнее изменение настроек (общий сброс экрана). Вызывается из
  /// `ref.listen`, то есть ПОСЛЕ фазы build: присваивать текст контроллеру
  /// прямо в build нельзя — это markNeedsBuild у уже смонтированного TextField.
  void _adoptExternal(AppSettings settings) {
    void adopt(TextEditingController ctrl, FocusNode focus, int value) {
      // Поле в фокусе — пользователь печатает, не перебиваем.
      if (focus.hasFocus) return;
      final text = value.toString();
      if (ctrl.text != text) ctrl.text = text;
    }

    adopt(_socksCtrl, _socksFocus, settings.localPort);
    adopt(_httpCtrl, _httpFocus, settings.httpPort);
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

  Widget _portField(
    BuildContext context,
    String label,
    TextEditingController ctrl,
    FocusNode focus,
    bool enabled,
    VoidCallback onSubmit,
  ) {
    return TextField(
      controller: ctrl,
      focusNode: focus,
      enabled: enabled,
      keyboardType: TextInputType.number,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.text(context)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textLight(context)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
        filled: true,
        fillColor: AppTheme.bg(context).withValues(alpha: 0.45),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ExpressiveShape.medium)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ExpressiveShape.medium),
          borderSide: BorderSide(color: AppTheme.divider(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ExpressiveShape.medium),
          borderSide: BorderSide(color: AppTheme.accent(context)),
        ),
      ),
      onSubmitted: (_) => onSubmit(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();

    if (!_initialized) {
      _socksCtrl.text = settings.localPort.toString();
      _httpCtrl.text = settings.httpPort.toString();
      _initialized = true;
    }
    ref.listen(settingsNotifierProvider, (_, next) {
      final value = next.value;
      if (value != null) _adoptExternal(value);
    });

    final isConnected = ref.watch(
      vpnStateProvider.select((a) {
        final status = a.value?.status;
        return status == VpnStatus.connected || status == VpnStatus.connecting;
      }),
    );

    _settingsNotifier = ref.read(settingsNotifierProvider.notifier);
    _lastSettings = settings;
    _portsLocked = isConnected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _XrayCoreSectionHeader(
          icon: Icons.settings_input_component_rounded,
          title: l10n.settingsLocalPortsTitle,
        ),
        _xraySettingsCard(
          context,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _portField(
                      context,
                      l10n.settingsSocks5PortLabel,
                      _socksCtrl,
                      _socksFocus,
                      !isConnected,
                      () => _apply(settings),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _portField(
                      context,
                      l10n.settingsHttpPortLabel,
                      _httpCtrl,
                      _httpFocus,
                      !isConnected,
                      () => _apply(settings),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsLocalPortsHint,
                    style: _xrayTileSubtitleStyle(context),
                  ),
                  if (isConnected) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.settingsTurnOffToChange,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.orange(context)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
