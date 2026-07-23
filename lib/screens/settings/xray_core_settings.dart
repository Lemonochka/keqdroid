part of '../settings_tab.dart';

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

// Цвет и рамка на Material, а не на BoxDecoration: Switch/RadioListTile
// рисуют ink-сплэши на ближайшем Material-предке, и цветной DecoratedBox
// между ними прятал рипл (debug-спам «ListTile background color or ink
// splashes may be invisible»).
Widget _xraySettingsCard(BuildContext context, {required List<Widget> children}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppTheme.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppTheme.divider(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
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

  Future<void> _saveTun(AppSettings settings, TunSettings tun) async {
    await ref
        .read(settingsNotifierProvider.notifier)
        .save(settings.copyWith(tun: tun));
  }

  Future<void> _resetDefaults(AppSettings settings) async {
    if (!await _confirmReset(
      context,
      message: AppLocalizations.of(context)!.settingsXrayResetConfirm,
    )) {
      return;
    }
    if (!mounted) return;
    await ref.read(settingsNotifierProvider.notifier).save(
          settings.copyWith(
            xrayCore: const XrayCoreSettings(),
            tun: const TunSettings(),
          ),
        );
    _dnsServersCtrl.text = const XrayCoreSettings().dnsServers;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.settingsXrayResetDone)),
    );
  }

  /// One radio row. Selection is driven by an enclosing [RadioGroup] ancestor,
  /// so the tile itself only declares its [value].
  Widget _choiceTile({
    required BuildContext context,
    required String value,
    required Color accent,
    required String title,
    String? subtitle,
  }) {
    return RadioListTile<String>(
      value: value,
      activeColor: accent,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
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
    final tun = settings.tun;
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
      body: SmoothScroll(
        builder: (context, controller) => ListView(
          controller: controller,
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
          // sing-box TUN есть только на десктопе: Android держит TUN через
          // VpnService + tun2socks, эти опции там ни на что не влияют.
          if (Platform.isWindows || Platform.isLinux) ...[
            _XrayCoreSectionHeader(
              icon: Icons.lan_outlined,
              title: l10n.settingsTunSection,
            ),
            _xraySettingsCard(
              context,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    l10n.settingsTunSectionNote,
                    style: _xrayTileSubtitleStyle(context),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    l10n.settingsTunStackTitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text(context),
                    ),
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
                _xraySettingsDivider(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
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
                          style: _xrayTileSubtitleStyle(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.settingsTunUdpTimeoutHint,
                          style: _xrayTileSubtitleStyle(context),
                        ),
                      ),
                    ],
                  ),
                ),
                _xraySettingsDivider(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    l10n.settingsTunStrictRouteTitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text(context),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Text(
                    l10n.settingsTunStrictRouteHint,
                    style: _xrayTileSubtitleStyle(context),
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
                _xraySettingsDivider(context),
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
                      style: _xrayTileSubtitleStyle(context),
                    ),
                  ),
                ),
                _xraySettingsDivider(context),
                SwitchListTile(
                  value: tun.autoRoute,
                  onChanged: (v) =>
                      _saveTun(settings, tun.copyWith(autoRoute: v)),
                  activeThumbColor: accent,
                  title: Text(l10n.settingsTunAutoRoute),
                  subtitle: Text(
                    l10n.settingsTunAutoRouteHint,
                    style: _xrayTileSubtitleStyle(context),
                  ),
                ),
              ],
            ),
          ],
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
  final tun = settings?.tun ?? const TunSettings();
  if (core == const XrayCoreSettings() && tun.isDefault) {
    return l10n.settingsXrayCoreSubtitle;
  }
  final parts = <String>[core.logLevel];
  if (core.dnsUseCustom) parts.insert(0, 'DNS');
  if (core.xmuxEnabled) parts.add('XMUX');
  if (!tun.isDefault) parts.add('TUN');
  return parts.join(' · ');
}
