part of '../settings_tab.dart';

/// Заголовок секции с иконкой — тонкая обёртка над общим
/// [ExpressiveSectionHeader]. Собственного вида у него больше нет: раньше он
/// расходился с остальными настройками и цветом, и ролью текста.
class _XrayCoreSectionHeader extends StatelessWidget {
  const _XrayCoreSectionHeader({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) =>
      ExpressiveSectionHeader(title, icon: icon);
}

/// Карточка секции — ровно та же, что на остальных подэкранах настроек
/// (см. `card()` в ping/lan/permissions).
///
/// Волосяных дивайдеров внутри больше нет. В M3E строки разделяет containment,
/// а не линия: карточка уже сказала «это одна группа», и рисовать внутри неё
/// ещё и границы — значит говорить это дважды. Отдельная группа отделяется
/// заголовком секции, а не швом.
Widget _xraySettingsCard(BuildContext context, {required List<Widget> children}) =>
    ExpressiveCard(
      padding: const EdgeInsets.symmetric(
        horizontal: ExpressiveSpacing.extraSmall,
        vertical: ExpressiveSpacing.extraSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );

TextStyle? _xrayTileSubtitleStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall?.copyWith(
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
  Future<void> _save(AppSettings settings, XrayCoreSettings core) async {
    await ref
        .read(settingsNotifierProvider.notifier)
        .save(settings.copyWith(xrayCore: core));
  }

  Future<void> _saveTun(AppSettings settings, TunSettings tun) async {
    await ref
        .read(settingsNotifierProvider.notifier)
        .save(settings.copyWith(tun: tun));
  }

  Future<void> _saveFakeIp(AppSettings settings, bool value) async {
    await ref
        .read(settingsNotifierProvider.notifier)
        .save(settings.copyWith(mihomoFakeIp: value));
  }

  Future<void> _resetDefaults(AppSettings settings) async {
    if (!await _confirmReset(
      context,
      message: AppLocalizations.of(context)!.settingsXrayResetConfirm,
    )) {
      return;
    }
    if (!mounted) return;
    // Порты при активном туннеле не трогаем — их и руками менять нельзя, пока
    // ядро слушает старые (см. _LocalPortsSection).
    final vpn = ref.read(vpnStateProvider).value?.status;
    final portsLocked =
        vpn == VpnStatus.connected || vpn == VpnStatus.connecting;
    const defaults = AppSettings();
    await ref.read(settingsNotifierProvider.notifier).save(
          settings.copyWith(
            xrayCore: const XrayCoreSettings(),
            tun: const TunSettings(),
            // Кнопка сбрасывает ВСЁ, что стоит на этом экране, — включая
            // секцию mihomo. Забытое поле здесь выглядит как «сброс не
            // сработал».
            mihomoFakeIp: defaults.mihomoFakeIp,
            localPort: portsLocked ? null : defaults.localPort,
            httpPort: portsLocked ? null : defaults.httpPort,
          ),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.settingsXrayResetDone)),
    );
  }

  /// Строка выбора. Значение подхватывает [RadioGroup] выше по дереву, поэтому
  /// сама строка объявляет только [value].
  ///
  /// Ни `dense`, ни `visualDensity.compact`, ни собственных стилей текста тут
  /// больше нет: строки этого экрана были на полкегля мельче и на восемь
  /// пикселей теснее, чем такие же строки на всех остальных подэкранах. Разница
  /// слишком мала, чтобы прочитаться как решение, и ровно настолько велика,
  /// чтобы прочитаться как небрежность.
  Widget _choiceTile({
    required BuildContext context,
    required String value,
    required Color accent,
    required String title,
    String? subtitle,
  }) =>
      RadioListTile<String>(
        value: value,
        activeColor: accent,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final core = settings.xrayCore;
    final tun = settings.tun;
    final accent = AppTheme.accent(context);

    return ExpressivePage(
      title: l10n.settingsXrayCoreTitle,
      padding: const EdgeInsets.fromLTRB(
        ExpressiveSpacing.large,
        ExpressiveSpacing.none,
        ExpressiveSpacing.large,
        ExpressiveSpacing.extraLargeIncreased,
      ),
      actions: [
        TextButton(
          onPressed: () => _resetDefaults(settings),
          child: Text(
            l10n.settingsXrayResetDefaults,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: accent),
          ),
        ),
      ],
      children: [
          // Вводной плашки «параметры уходят в конфиг, меняйте осторожно»
          // здесь больше нет. Она не сообщала ничего, чего не сообщает
          // название экрана, зато первым делом занимала полтора сантиметра
          // высоты и отодвигала настройки вниз.
          const _LocalPortsSection(),
          _XrayCoreSectionHeader(icon: Icons.dns_rounded, title: l10n.settingsXrayDnsSection),
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
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: _DnsServersField(
                        initialValue: core.dnsServers,
                        label: l10n.settingsXrayDnsServers,
                        onSave: (v) =>
                            _save(settings, core.copyWith(dnsServers: v)),
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
              SwitchListTile(
                value: core.dnsSplitDirectDomains,
                onChanged: (v) =>
                    _save(settings, core.copyWith(dnsSplitDirectDomains: v)),
                activeThumbColor: accent,
                title: Text(l10n.settingsXrayDnsSplitDirect),
                subtitle: Text(
                  l10n.settingsXrayDnsSplitDirectHint,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  l10n.settingsXrayDnsQueryStrategy,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: AppTheme.text(context)),
                ),
              ),
              RadioGroup<String>(
                groupValue: core.dnsQueryStrategy,
                onChanged: (v) {
                  if (v != null) _save(settings, core.copyWith(dnsQueryStrategy: v));
                },
                child: Column(
                  children: [
                    for (final strategy in XrayCoreSettings.dnsQueryStrategies)
                      _choiceTile(
                        context: context,
                        value: strategy,
                        accent: accent,
                        title: strategy,
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                value: core.dnsDisableCache,
                onChanged: (v) =>
                    _save(settings, core.copyWith(dnsDisableCache: v)),
                activeThumbColor: accent,
                title: Text(l10n.settingsXrayDnsDisableCache),
              ),
            ],
          ),
          _XrayCoreSectionHeader(icon: Icons.merge_type_rounded, title: l10n.settingsXrayXmuxSection),
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
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.settingsXrayXmuxParamsTitle,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(color: AppTheme.text(context)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.settingsXrayXmuxParamsHint,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      // Утопленная подложка под парой полей: роль поверхности
                      // вместо полупрозрачного фона с рамкой. Рамка тут была
                      // третьей границей подряд (страница → карточка → панель),
                      // а тональной ступеньки для вложенности достаточно.
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLowest,
                          borderRadius:
                              ExpressiveShape.radius(ExpressiveShape.large),
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
          _XrayCoreSectionHeader(
            icon: Icons.content_cut_rounded,
            title: l10n.settingsXrayFragmentSection,
          ),
          _xraySettingsCard(
            context,
            children: [
              SwitchListTile(
                value: core.fragmentEnabled,
                onChanged: (v) =>
                    _save(settings, core.copyWith(fragmentEnabled: v)),
                activeThumbColor: accent,
                title: Text(l10n.settingsXrayFragmentEnable),
                subtitle: Text(
                  l10n.settingsXrayFragmentEnableHint,
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        l10n.settingsXrayFragmentPacketsTitle,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: AppTheme.text(context)),
                      ),
                    ),
                    RadioGroup<String>(
                      groupValue: core.fragmentPackets,
                      onChanged: (v) {
                        if (v != null) {
                          _save(settings, core.copyWith(fragmentPackets: v));
                        }
                      },
                      child: Column(
                        children: [
                          for (final mode in XrayCoreSettings.fragmentPacketModes)
                            _choiceTile(
                              context: context,
                              value: mode,
                              accent: accent,
                              title: mode ==
                                      XrayCoreSettings.fragmentPacketsTlsHello
                                  ? l10n.settingsXrayFragmentPacketsTlsHello
                                  : l10n.settingsXrayFragmentPacketsFirst,
                              subtitle: mode,
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.settingsXrayFragmentParamsTitle,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(color: AppTheme.text(context)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.settingsXrayFragmentParamsHint,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLowest,
                          borderRadius:
                              ExpressiveShape.radius(ExpressiveShape.large),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _XrayCoreTextField(
                                  key: ValueKey(
                                    'fragment_len_${core.fragmentLength}',
                                  ),
                                  label: l10n.settingsXrayFragmentLength,
                                  hint: XrayCoreSettings.defaultFragmentLength,
                                  initialValue: core.fragmentLength,
                                  onSave: (v) => _save(
                                    settings,
                                    core.copyWith(fragmentLength: v),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _XrayCoreTextField(
                                  key: ValueKey(
                                    'fragment_int_${core.fragmentInterval}',
                                  ),
                                  label: l10n.settingsXrayFragmentInterval,
                                  hint:
                                      XrayCoreSettings.defaultFragmentInterval,
                                  initialValue: core.fragmentInterval,
                                  onSave: (v) => _save(
                                    settings,
                                    core.copyWith(fragmentInterval: v),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                crossFadeState: core.fragmentEnabled
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 220),
                sizeCurve: Curves.easeOutCubic,
              ),
            ],
          ),
          _XrayCoreSectionHeader(icon: Icons.tune_rounded, title: l10n.settingsXrayGeneralSection),
          _xraySettingsCard(
            context,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  l10n.settingsXrayLogLevel,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: AppTheme.text(context)),
                ),
              ),
              RadioGroup<String>(
                groupValue: core.logLevel,
                onChanged: (v) {
                  if (v != null) _save(settings, core.copyWith(logLevel: v));
                },
                child: Column(
                  children: [
                    for (final level in XrayCoreSettings.logLevels)
                      _choiceTile(
                        context: context,
                        value: level,
                        accent: accent,
                        title: level,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  l10n.settingsXrayDomainStrategy,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: AppTheme.text(context)),
                ),
              ),
              RadioGroup<String>(
                groupValue: core.routingDomainStrategy,
                onChanged: (v) {
                  if (v != null) {
                    _save(settings, core.copyWith(routingDomainStrategy: v));
                  }
                },
                child: Column(
                  children: [
                    for (final strategy in XrayCoreSettings.routingDomainStrategies)
                      _choiceTile(
                        context: context,
                        value: strategy,
                        accent: accent,
                        title: strategy,
                      ),
                  ],
                ),
              ),
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
                  ),
                ),
              ),
            ],
          ),
          // sing-box TUN есть только на десктопе: Android держит TUN через
          // VpnService + tun2socks, эти опции там ни на что не влияют.
          if (Platform.isWindows || Platform.isLinux) ...[
            _XrayCoreSectionHeader(
              icon: Icons.lan_rounded,
              title: l10n.settingsTunSection,
            ),
            _xraySettingsCard(
              context,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    l10n.settingsTunSectionNote,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    l10n.settingsTunStackTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: AppTheme.text(context)),
                  ),
                ),
                RadioGroup<String>(
                  groupValue: tun.stack,
                  onChanged: (v) {
                    if (v != null) _saveTun(settings, tun.copyWith(stack: v));
                  },
                  child: Column(
                    children: [
                      _choiceTile(
                        context: context,
                        value: TunSettings.stackSystem,
                        accent: accent,
                        title: 'system',
                        subtitle: l10n.settingsTunStackSystemHint,
                      ),
                      _choiceTile(
                        context: context,
                        value: TunSettings.stackGvisor,
                        accent: accent,
                        title: 'gVisor',
                        subtitle: l10n.settingsTunStackGvisorHint,
                      ),
                      _choiceTile(
                        context: context,
                        value: TunSettings.stackMixed,
                        accent: accent,
                        title: 'mixed',
                        subtitle: l10n.settingsTunStackMixedHint,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _XrayCoreTextField(
                          key: ValueKey('tun_mtu_${tun.mtu}'),
                          label: l10n.settingsTunMtu,
                          hint: '${TunSettings.defaultMtu}',
                          initialValue: '${tun.mtu}',
                          keyboardType: TextInputType.number,
                          onSave: (v) {
                            final n = int.tryParse(v.trim());
                            if (n == null) return;
                            _saveTun(
                              settings,
                              tun.copyWith(mtu: TunSettings.clampMtu(n)),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _XrayCoreTextField(
                          key: ValueKey('tun_udp_${tun.udpTimeoutSec}'),
                          label: l10n.settingsTunUdpTimeout,
                          hint: '${TunSettings.defaultUdpTimeoutSec}',
                          initialValue: '${tun.udpTimeoutSec}',
                          keyboardType: TextInputType.number,
                          onSave: (v) {
                            final n = int.tryParse(v.trim());
                            if (n == null) return;
                            _saveTun(
                              settings,
                              tun.copyWith(
                                udpTimeoutSec: TunSettings.clampUdpTimeout(n),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.settingsTunMtuHint,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.settingsTunUdpTimeoutHint,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    l10n.settingsTunStrictRouteTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: AppTheme.text(context)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Text(
                    l10n.settingsTunStrictRouteHint,
                  ),
                ),
                RadioGroup<String>(
                  groupValue: tun.strictRoute,
                  onChanged: (v) {
                    if (v != null) {
                      _saveTun(settings, tun.copyWith(strictRoute: v));
                    }
                  },
                  child: Column(
                    children: [
                      _choiceTile(
                        context: context,
                        value: TunSettings.strictRouteAuto,
                        accent: accent,
                        title: l10n.settingsTunStrictRouteAuto,
                        subtitle: l10n.settingsTunStrictRouteAutoHint,
                      ),
                      _choiceTile(
                        context: context,
                        value: TunSettings.strictRouteOn,
                        accent: accent,
                        title: l10n.settingsTunStrictRouteOn,
                      ),
                      _choiceTile(
                        context: context,
                        value: TunSettings.strictRouteOff,
                        accent: accent,
                        title: l10n.settingsTunStrictRouteOff,
                      ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: tun.stack != TunSettings.stackSystem ? 1 : 0.45,
                  duration: const Duration(milliseconds: 180),
                  child: SwitchListTile(
                    value: tun.endpointIndependentNat,
                    onChanged: tun.stack != TunSettings.stackSystem
                        ? (v) => _saveTun(
                              settings,
                              tun.copyWith(endpointIndependentNat: v),
                            )
                        : null,
                    activeThumbColor: accent,
                    title: Text(l10n.settingsTunEin),
                    subtitle: Text(
                      l10n.settingsTunEinHint,
                    ),
                  ),
                ),
                SwitchListTile(
                  value: tun.autoRoute,
                  onChanged: (v) =>
                      _saveTun(settings, tun.copyWith(autoRoute: v)),
                  activeThumbColor: accent,
                  title: Text(l10n.settingsTunAutoRoute),
                  subtitle: Text(
                    l10n.settingsTunAutoRouteHint,
                  ),
                ),
                SwitchListTile(
                  value: tun.blockIpv6Leak,
                  onChanged: (v) =>
                      _saveTun(settings, tun.copyWith(blockIpv6Leak: v)),
                  activeThumbColor: accent,
                  title: Text(l10n.settingsTunIpv6),
                  subtitle: Text(
                    l10n.settingsTunIpv6Hint,
                  ),
                ),
              ],
            ),
          ],
          // mihomo поставляется на всех трёх платформах, поэтому секция здесь
          // безусловна — в отличие от TUN-настроек выше, которые описывают
          // sing-box-инбаунд и на Android не значат ничего.
          _XrayCoreSectionHeader(
            icon: Icons.alt_route_rounded,
            title: l10n.settingsMihomoSection,
          ),
          _xraySettingsCard(
            context,
            children: [
              SwitchListTile(
                value: settings.mihomoFakeIp,
                onChanged: (v) => _saveFakeIp(settings, v),
                activeThumbColor: accent,
                title: Text(l10n.settingsMihomoFakeIp),
                subtitle: Text(
                  l10n.settingsMihomoFakeIpHint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _resetDefaults(settings),
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: Text(l10n.settingsXrayResetDefaults),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textLight(context),
              side: BorderSide(color: AppTheme.divider(context)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ExpressiveShape.large),
              ),
            ),
          ),
        ],
    );
  }
}

/// Поле со списком DNS-серверов. Оно многострочное (`maxLines > 1`), а такой
/// TextField не шлёт onSubmitted/onEditingComplete — Enter вставляет перенос
/// строки, поэтому раньше введённые адреса нигде не сохранялись и «слетали»
/// при выходе с экрана. Сохраняем по потере фокуса и при уходе с экрана.
class _DnsServersField extends StatefulWidget {
  const _DnsServersField({
    required this.initialValue,
    required this.label,
    required this.onSave,
  });

  final String initialValue;
  final String label;
  final ValueChanged<String> onSave;

  @override
  State<_DnsServersField> createState() => _DnsServersFieldState();
}

class _DnsServersFieldState extends State<_DnsServersField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;
  late String _savedValue;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
    _savedValue = widget.initialValue;
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _flush();
  }

  void _flush() {
    final text = _ctrl.text;
    if (text == _savedValue) return;
    _savedValue = text;
    widget.onSave(text);
  }

  @override
  void didUpdateWidget(covariant _DnsServersField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Внешнее изменение (например «Сбросить настройки») подхватываем только
    // когда пользователь не редактирует поле, чтобы не затирать ввод.
    if (widget.initialValue != oldWidget.initialValue &&
        !_focus.hasFocus &&
        widget.initialValue != _ctrl.text) {
      _ctrl.text = widget.initialValue;
      _savedValue = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _flush();
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      maxLines: 4,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: AppTheme.text(context)),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: 'https+local://1.1.1.1/dns-query',
        alignLabelWithHint: true,
        filled: true,
        fillColor: AppTheme.bg(context).withValues(alpha: 0.55),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ExpressiveShape.medium),
          borderSide: BorderSide(color: AppTheme.divider(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ExpressiveShape.medium),
          borderSide: BorderSide(color: AppTheme.divider(context)),
        ),
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
        style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: AppTheme.text(context)),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          isDense: true,
          filled: true,
          fillColor: AppTheme.card(context),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(ExpressiveShape.medium)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ExpressiveShape.medium),
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
  const defaults = AppSettings();
  final current = settings ?? defaults;
  final core = current.xrayCore;
  final tun = current.tun;
  final customPorts = current.localPort != defaults.localPort ||
      current.httpPort != defaults.httpPort;
  if (core == const XrayCoreSettings() && tun.isDefault && !customPorts) {
    return l10n.settingsXrayCoreSubtitle;
  }
  final parts = <String>[core.logLevel];
  if (core.dnsUseCustom) parts.insert(0, 'DNS');
  if (core.xmuxEnabled) parts.add('XMUX');
  if (!tun.isDefault) parts.add('TUN');
  if (customPorts) parts.add('${current.localPort}/${current.httpPort}');
  return parts.join(' · ');
}
