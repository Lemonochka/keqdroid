part of '../settings_tab.dart';

/// Настройка хоткеев в стиле Discord: клик по чипу справа переводит строку в
/// режим записи, следующее нажатое сочетание сохраняется. Esc — отмена,
/// Backspace — очистить. Все хоткеи по умолчанию не назначены.
class _HotkeySettingsScreen extends ConsumerStatefulWidget {
  const _HotkeySettingsScreen();

  @override
  ConsumerState<_HotkeySettingsScreen> createState() =>
      _HotkeySettingsScreenState();
}

class _HotkeySettingsScreenState extends ConsumerState<_HotkeySettingsScreen> {
  HotkeyAction? _recording;
  bool _needsModifierHint = false;
  final FocusNode _captureFocus = FocusNode(debugLabel: 'hotkeyCapture');

  @override
  void dispose() {
    // Уход с экрана посреди записи: вернуть снятую регистрацию хоткеев.
    if (_recording != null) {
      _reapplyBindings();
    }
    HotkeyService.captureMode = false;
    _captureFocus.dispose();
    super.dispose();
  }

  void _reapplyBindings() {
    final settings = ref.read(settingsNotifierProvider).value;
    if (settings != null) {
      unawaited(
        HotkeyService.apply(HotkeyService.parseBindings(settings.hotkeys)),
      );
    }
  }

  void _startRecording(HotkeyAction action) {
    setState(() {
      _recording = action;
      _needsModifierHint = false;
    });
    // Пока идёт запись, in-app обработчик (Linux) не должен исполнять действия.
    HotkeyService.captureMode = true;
    // На Windows зарегистрированное глобальное сочетание съедается системой и
    // до записи не дойдёт (сработает действие) — на время записи снимаем всё.
    unawaited(HotkeyService.apply(const {}));
    _captureFocus.requestFocus();
  }

  void _stopRecording() {
    HotkeyService.captureMode = false;
    // Вернуть регистрацию. При сохранении нового сочетания поверх этого её же
    // переприменит listener настроек в DesktopHomeScreen — порядок вызовов
    // канала сохраняется, финальное состояние корректно.
    _reapplyBindings();
    if (_recording != null) {
      setState(() {
        _recording = null;
        _needsModifierHint = false;
      });
    }
  }

  Future<void> _saveBinding(HotkeyAction action, HotkeyBinding? binding) async {
    final settings =
        ref.read(settingsNotifierProvider).value ?? const AppSettings();
    final map = Map<String, String>.of(settings.hotkeys);
    if (binding == null) {
      map.remove(action.id);
    } else {
      // Одно сочетание — одному действию: забираем его у другого действия.
      map.removeWhere(
        (key, value) => value == binding.toToken() && key != action.id,
      );
      map[action.id] = binding.toToken();
    }
    await ref
        .read(settingsNotifierProvider.notifier)
        .save(settings.copyWith(hotkeys: map));
    // Применяет DesktopHomeScreen через ref.listen на настройках; при
    // конфликте с чужим приложением он же покажет snackbar.
  }

  KeyEventResult _onCaptureKey(FocusNode node, KeyEvent event) {
    final action = _recording;
    if (action == null) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.handled;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _stopRecording();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete) {
      unawaited(_saveBinding(action, null));
      _stopRecording();
      return KeyEventResult.handled;
    }

    final token = HotkeyKeys.tokenForPhysical(event.physicalKey);
    if (token == null) {
      // Модификатор или неподдерживаемая клавиша — ждём основную.
      return KeyEventResult.handled;
    }
    final hk = HardwareKeyboard.instance;
    final binding = HotkeyBinding(
      ctrl: hk.isControlPressed,
      alt: hk.isAltPressed,
      shift: hk.isShiftPressed,
      meta: hk.isMetaPressed,
      key: token,
    );
    if (!binding.isValid) {
      setState(() => _needsModifierHint = true);
      return KeyEventResult.handled;
    }
    unawaited(_saveBinding(action, binding));
    _stopRecording();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();

    final actions = <(HotkeyAction, IconData, String, String)>[
      (
        HotkeyAction.toggleConnection,
        Icons.power_settings_new,
        l10n.hotkeyActionToggleConnection,
        l10n.hotkeyActionToggleConnectionDesc,
      ),
      (
        HotkeyAction.toggleTunMode,
        Icons.vpn_lock_outlined,
        l10n.hotkeyActionToggleTun,
        l10n.hotkeyActionToggleTunDesc,
      ),
      (
        HotkeyAction.bestPingServer,
        Icons.network_check,
        l10n.hotkeyActionBestPing,
        l10n.hotkeyActionBestPingDesc,
      ),
      (
        HotkeyAction.toggleWindow,
        Icons.flip_to_front,
        l10n.hotkeyActionToggleWindow,
        l10n.hotkeyActionToggleWindowDesc,
      ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        elevation: 0,
        title: Text(l10n.settingsHotkeysTitle),
      ),
      body: Focus(
        focusNode: _captureFocus,
        onKeyEvent: _onCaptureKey,
        child: GestureDetector(
          // Клик мимо чипа отменяет запись (как в Discord).
          behavior: HitTestBehavior.translucent,
          onTap: _recording != null ? _stopRecording : null,
          child: SmoothScroll(
            builder: (context, controller) => ListView(
              controller: controller,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.accent(context).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.accent(context).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: AppTheme.accent(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          HotkeyService.isGlobal
                              ? l10n.hotkeysHintGlobal
                              : l10n.hotkeysHintInApp,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: AppTheme.textLight(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                for (final (action, icon, title, subtitle) in actions) ...[
                  _HotkeyRow(
                    icon: icon,
                    title: title,
                    subtitle: subtitle,
                    binding:
                        HotkeyBinding.fromToken(settings.hotkeys[action.id]),
                    recording: _recording == action,
                    recordingHint: _needsModifierHint
                        ? l10n.hotkeyNeedsModifier
                        : l10n.hotkeyRecordingHint,
                    needsModifier: _needsModifierHint,
                    notSetLabel: l10n.hotkeyNotSet,
                    pressKeysLabel: l10n.hotkeyPressKeys,
                    clearTooltip: l10n.hotkeyClearTooltip,
                    onChipTap: () {
                      if (_recording == action) {
                        _stopRecording();
                      } else {
                        _startRecording(action);
                      }
                    },
                    onClear: () => unawaited(_saveBinding(action, null)),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HotkeyRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final HotkeyBinding? binding;
  final bool recording;
  final String recordingHint;
  final bool needsModifier;
  final String notSetLabel;
  final String pressKeysLabel;
  final String clearTooltip;
  final VoidCallback onChipTap;
  final VoidCallback onClear;

  const _HotkeyRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.binding,
    required this.recording,
    required this.recordingHint,
    required this.needsModifier,
    required this.notSetLabel,
    required this.pressKeysLabel,
    required this.clearTooltip,
    required this.onChipTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accent(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: recording ? accent.withValues(alpha: 0.6) : AppTheme.divider(context),
          width: recording ? 1.5 : 1,
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
                  color: accent.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: AppTheme.text(context)),
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
                        color: AppTheme.text(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textLight(context),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _bindingChip(context),
            ],
          ),
          if (recording) ...[
            const SizedBox(height: 10),
            Text(
              recordingHint,
              style: TextStyle(
                fontSize: 11,
                color: needsModifier
                    ? AppTheme.red(context)
                    : AppTheme.textLight(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bindingChip(BuildContext context) {
    final accent = AppTheme.accent(context);

    if (recording) {
      return GestureDetector(
        onTap: onChipTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent, width: 1.5),
          ),
          child: Text(
            pressKeysLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ),
      );
    }

    final b = binding;
    if (b == null) {
      return GestureDetector(
        onTap: onChipTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.inset(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.divider(context)),
          ),
          child: Text(
            notSetLabel,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textLight(context),
            ),
          ),
        ),
      );
    }

    // Назначенное сочетание — «клавиши» по отдельности, как кейкапы.
    final parts = b.label.split(' + ');
    return GestureDetector(
      onTap: onChipTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(
                  '+',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textLight(context),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.inset(context),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppTheme.divider(context)),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.divider(context).withValues(alpha: 0.6),
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              child: Text(
                parts[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text(context),
                ),
              ),
            ),
          ],
          const SizedBox(width: 6),
          Tooltip(
            message: clearTooltip,
            child: InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 15,
                  color: AppTheme.textLight(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
