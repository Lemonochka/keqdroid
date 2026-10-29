part of '../settings_tab.dart';

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

Future<void> _saveXrayCore(
  WidgetRef ref,
  AppSettings settings,
  XrayCoreSettings core,
) async {
  await ref
      .read(settingsNotifierProvider.notifier)
      .save(settings.copyWith(xrayCore: core));
}

Future<void> _saveXrayTun(
  WidgetRef ref,
  AppSettings settings,
  TunSettings tun,
) async {
  await ref
      .read(settingsNotifierProvider.notifier)
      .save(settings.copyWith(tun: tun));
}

Future<void> _saveFakeIp(
  WidgetRef ref,
  AppSettings settings,
  bool value,
) async {
  await ref
      .read(settingsNotifierProvider.notifier)
      .save(settings.copyWith(fakeIp: value));
}

Widget _xrayChoiceTile({
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


class _XrayCoreSettingsScreen extends ConsumerStatefulWidget {
  const _XrayCoreSettingsScreen();

  @override
  ConsumerState<_XrayCoreSettingsScreen> createState() =>
      _XrayCoreSettingsScreenState();
}

class _XrayCoreSettingsScreenState extends ConsumerState<_XrayCoreSettingsScreen> {
  Future<void> _resetDefaults(AppSettings settings) async {
    if (!await _confirmReset(
      context,
      message: AppLocalizations.of(context)!.settingsXrayResetConfirm,
    )) {
      return;
    }
    if (!mounted) return;
    final vpn = ref.read(vpnStateProvider).value?.status;
    final portsLocked =
        vpn == VpnStatus.connected || vpn == VpnStatus.connecting;
    const defaults = AppSettings();
    await ref.read(settingsNotifierProvider.notifier).save(
          settings.copyWith(
            xrayCore: const XrayCoreSettings(),
            tun: const TunSettings(),
            // сброс обязан покрывать всё, что есть на экране, включая Fake IP
            fakeIp: defaults.fakeIp,
            localPort: portsLocked ? null : defaults.localPort,
            httpPort: portsLocked ? null : defaults.httpPort,
          ),
        );
    if (!mounted) return;
    AppSnack.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.settingsXrayResetDone)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final accent = AppTheme.accent(context);
    final xray = ref.watch(activeVpnBackendProvider) == VpnBackend.xray;

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
        const _LocalPortsSection(),
        const _XrayDnsSection(),
        if (xray) ...[
          const _XrayMuxSection(),
          const _XrayXmuxSection(),
          const _XrayFragmentSection(),
          const _XrayNoiseSection(),
        ],
        const _XrayGeneralSection(),
        if (Platform.isWindows || Platform.isLinux) const _XrayTunSection(),
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

class _XrayDnsSection extends ConsumerWidget {
  const _XrayDnsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final core = settings.xrayCore;
    final accent = AppTheme.accent(context);
    final xray = ref.watch(activeVpnBackendProvider) == VpnBackend.xray;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _XrayCoreSectionHeader(icon: Icons.dns_rounded, title: l10n.settingsXrayDnsSection),
        _xraySettingsCard(
          context,
          children: [
            SwitchListTile(
              value: core.dnsUseCustom,
              onChanged: (v) => _saveXrayCore(ref, settings, core.copyWith(dnsUseCustom: v)),
              activeThumbColor: accent,
              title: Text(l10n.settingsXrayDnsCustom),
              subtitle: Text(
                !core.dnsUseCustom
                    ? l10n.settingsXrayDnsDefaultNote
                    : xray
                        ? l10n.settingsXrayDnsCustomHintXray
                        : l10n.settingsXrayDnsCustomHint,
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
                          _saveXrayCore(ref, settings, core.copyWith(dnsServers: v)),
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
            if (xray && core.dnsSplitApplies)
              SwitchListTile(
                value: core.dnsSplitDirectDomains,
                onChanged: (v) => _saveXrayCore(
                  ref,
                  settings,
                  core.copyWith(dnsSplitDirectDomains: v),
                ),
                activeThumbColor: accent,
                title: Text(l10n.settingsXrayDnsSplitDirect),
                subtitle: Text(
                  core.dnsUseCustom
                      ? l10n.settingsXrayDnsSplitDirectHint
                      : l10n.settingsXrayDnsSplitDirectSystemHint,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _DnsServersField(
                initialValue: core.dnsHosts,
                label: l10n.settingsXrayDnsHosts,
                hintText: 'example.com 10.0.0.5',
                onSave: (v) =>
                    _saveXrayCore(ref, settings, core.copyWith(dnsHosts: v)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _DnsServersField(
                initialValue: core.dnsPolicy,
                label: l10n.settingsXrayDnsPolicy,
                hintText: 'home.lan 192.168.1.1',
                onSave: (v) =>
                    _saveXrayCore(ref, settings, core.copyWith(dnsPolicy: v)),
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
              groupValue: xray || core.dnsQueryStrategy == 'UseIPv4'
                  ? core.dnsQueryStrategy
                  : 'UseIP',
              onChanged: (v) {
                if (v != null) _saveXrayCore(ref, settings, core.copyWith(dnsQueryStrategy: v));
              },
              child: Column(
                children: [
                  // у mihomo только dns.ipv6 да или нет, остальные три вели бы себя как UseIP
                  for (final strategy in xray
                      ? XrayCoreSettings.dnsQueryStrategies
                      : const ['UseIPv4', 'UseIP'])
                    _xrayChoiceTile(
                      context: context,
                      value: strategy,
                      accent: accent,
                      title: strategy,
                    ),
                ],
              ),
            ),
            if (xray)
              SwitchListTile(
                value: core.dnsDisableCache,
                onChanged: (v) => _saveXrayCore(
                  ref,
                  settings,
                  core.copyWith(dnsDisableCache: v),
                ),
                activeThumbColor: accent,
                title: Text(l10n.settingsXrayDnsDisableCache),
              ),
            SwitchListTile(
              value: settings.fakeIp,
              onChanged: (v) => _saveFakeIp(ref, settings, v),
              activeThumbColor: accent,
              title: Text(l10n.settingsFakeIp),
              subtitle: Text(l10n.settingsFakeIpHint),
            ),
          ],
        ),
      ],
    );
  }
}

class _XrayMuxSection extends ConsumerWidget {
  const _XrayMuxSection();

  static String _udp443Label(AppLocalizations l10n, String mode) =>
      switch (mode) {
        XrayCoreSettings.muxUdp443Allow => l10n.settingsXrayMuxUdp443Allow,
        XrayCoreSettings.muxUdp443Skip => l10n.settingsXrayMuxUdp443Skip,
        _ => l10n.settingsXrayMuxUdp443Reject,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final core = settings.xrayCore;
    final accent = AppTheme.accent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _XrayCoreSectionHeader(
          icon: Icons.account_tree_rounded,
          title: l10n.settingsXrayMuxSection,
        ),
        _xraySettingsCard(
          context,
          children: [
            SwitchListTile(
              value: core.muxEnabled,
              onChanged: (v) =>
                  _saveXrayCore(ref, settings, core.copyWith(muxEnabled: v)),
              activeThumbColor: accent,
              title: Text(l10n.settingsXrayMuxEnable),
              subtitle: Text(l10n.settingsXrayMuxEnableHint),
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
                          l10n.settingsXrayMuxParamsTitle,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: AppTheme.text(context)),
                        ),
                        const SizedBox(height: 4),
                        Text(l10n.settingsXrayMuxParamsHint),
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
                                key: ValueKey('mux_c_${core.muxConcurrency}'),
                                label: l10n.settingsXrayMuxConcurrency,
                                hint: '${XrayCoreSettings.defaultMuxConcurrency}',
                                initialValue: '${core.muxConcurrency}',
                                keyboardType: TextInputType.number,
                                onSave: (v) => _saveXrayCore(
                                  ref,
                                  settings,
                                  core.copyWith(
                                    muxConcurrency: int.tryParse(v.trim()) ??
                                        XrayCoreSettings.defaultMuxConcurrency,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _XrayCoreTextField(
                                key: ValueKey(
                                  'mux_x_${core.muxXudpConcurrency}',
                                ),
                                label: l10n.settingsXrayMuxXudpConcurrency,
                                hint:
                                    '${XrayCoreSettings.defaultMuxXudpConcurrency}',
                                initialValue: '${core.muxXudpConcurrency}',
                                keyboardType: TextInputType.number,
                                onSave: (v) => _saveXrayCore(
                                  ref,
                                  settings,
                                  core.copyWith(
                                    muxXudpConcurrency: int.tryParse(v.trim()) ??
                                        XrayCoreSettings
                                            .defaultMuxXudpConcurrency,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      l10n.settingsXrayMuxUdp443Title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: AppTheme.text(context)),
                    ),
                  ),
                  RadioGroup<String>(
                    groupValue: core.muxXudpProxyUDP443,
                    onChanged: (v) {
                      if (v != null) {
                        _saveXrayCore(
                          ref,
                          settings,
                          core.copyWith(muxXudpProxyUDP443: v),
                        );
                      }
                    },
                    child: Column(
                      children: [
                        for (final mode in XrayCoreSettings.muxUdp443Modes)
                          _xrayChoiceTile(
                            context: context,
                            value: mode,
                            accent: accent,
                            title: _udp443Label(l10n, mode),
                            subtitle: mode,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              crossFadeState: core.muxEnabled
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 220),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ],
    );
  }
}

class _XrayXmuxSection extends ConsumerWidget {
  const _XrayXmuxSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final core = settings.xrayCore;
    final accent = AppTheme.accent(context);
    final concurrencySet = core.xmuxMaxConcurrency.trim().isNotEmpty;
    final connectionsSet = core.xmuxMaxConnections.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _XrayCoreSectionHeader(icon: Icons.merge_type_rounded, title: l10n.settingsXrayXmuxSection),
        _xraySettingsCard(
          context,
          children: [
            SwitchListTile(
              value: core.xmuxEnabled,
              onChanged: (v) => _saveXrayCore(ref, settings, core.copyWith(xmuxEnabled: v)),
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
                                    enabled: concurrencySet || !connectionsSet,
                                    helperText: !concurrencySet && connectionsSet
                                        ? l10n.settingsXrayXmuxOneOfTwo
                                        : null,
                                    onSave: (v) => _saveXrayCore(ref, 
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
                                    hint: '3',
                                    initialValue: core.xmuxMaxConnections,
                                    enabled: connectionsSet || !concurrencySet,
                                    helperText: concurrencySet && !connectionsSet
                                        ? l10n.settingsXrayXmuxOneOfTwo
                                        : null,
                                    errorText: concurrencySet && connectionsSet
                                        ? l10n.settingsXrayXmuxConnectionsIgnored
                                        : null,
                                    onSave: (v) => _saveXrayCore(ref, 
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
                                    onSave: (v) => _saveXrayCore(ref, 
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
                                    onSave: (v) => _saveXrayCore(ref, 
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
                                    onSave: (v) => _saveXrayCore(ref, 
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
                                      _saveXrayCore(ref, 
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
      ],
    );
  }
}

class _XrayFragmentSection extends ConsumerWidget {
  const _XrayFragmentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final core = settings.xrayCore;
    final accent = AppTheme.accent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                  _saveXrayCore(ref, settings, core.copyWith(fragmentEnabled: v)),
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
                        _saveXrayCore(ref, settings, core.copyWith(fragmentPackets: v));
                      }
                    },
                    child: Column(
                      children: [
                        for (final mode in XrayCoreSettings.fragmentPacketModes)
                          _xrayChoiceTile(
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
                                onSave: (v) => _saveXrayCore(ref, 
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
                                onSave: (v) => _saveXrayCore(ref, 
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
      ],
    );
  }
}

class _XrayNoiseSection extends ConsumerWidget {
  const _XrayNoiseSection();

  static String _kindLabel(AppLocalizations l10n, String kind) => switch (kind) {
        XrayCoreSettings.noiseStr => l10n.settingsXrayNoiseKindStr,
        XrayCoreSettings.noiseHex => l10n.settingsXrayNoiseKindHex,
        XrayCoreSettings.noiseBase64 => l10n.settingsXrayNoiseKindBase64,
        _ => l10n.settingsXrayNoiseKindRand,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final core = settings.xrayCore;
    final accent = AppTheme.accent(context);
    final random = core.noiseKind == XrayCoreSettings.noiseRandom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _XrayCoreSectionHeader(
          icon: Icons.graphic_eq_rounded,
          title: l10n.settingsXrayNoiseSection,
        ),
        _xraySettingsCard(
          context,
          children: [
            SwitchListTile(
              value: core.noiseEnabled,
              onChanged: (v) =>
                  _saveXrayCore(ref, settings, core.copyWith(noiseEnabled: v)),
              activeThumbColor: accent,
              title: Text(l10n.settingsXrayNoiseEnable),
              subtitle: Text(l10n.settingsXrayNoiseEnableHint),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      l10n.settingsXrayNoiseKindTitle,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: AppTheme.text(context)),
                    ),
                  ),
                  RadioGroup<String>(
                    groupValue: core.noiseKind,
                    onChanged: (v) {
                      if (v != null) {
                        _saveXrayCore(
                          ref,
                          settings,
                          core.copyWith(noiseKind: v),
                        );
                      }
                    },
                    child: Column(
                      children: [
                        for (final kind in XrayCoreSettings.noiseKinds)
                          _xrayChoiceTile(
                            context: context,
                            value: kind,
                            accent: accent,
                            title: _kindLabel(l10n, kind),
                            subtitle: kind,
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(l10n.settingsXrayNoiseParamsHint),
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
                        child: Column(
                          children: [
                            if (random)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _XrayCoreTextField(
                                      key: ValueKey(
                                        'noise_len_${core.noiseRandLength}',
                                      ),
                                      label: l10n.settingsXrayNoiseRandLength,
                                      hint: XrayCoreSettings
                                          .defaultNoiseRandLength,
                                      initialValue: core.noiseRandLength,
                                      onSave: (v) => _saveXrayCore(
                                        ref,
                                        settings,
                                        core.copyWith(noiseRandLength: v),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _XrayCoreTextField(
                                      key: ValueKey(
                                        'noise_bytes_${core.noiseRandBytes}',
                                      ),
                                      label: l10n.settingsXrayNoiseRandBytes,
                                      hint: '0-255',
                                      initialValue: core.noiseRandBytes,
                                      onSave: (v) => _saveXrayCore(
                                        ref,
                                        settings,
                                        core.copyWith(noiseRandBytes: v),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else
                              _XrayCoreTextField(
                                key: ValueKey('noise_packet_${core.noisePacket}'),
                                label: l10n.settingsXrayNoisePacket,
                                hint: '',
                                initialValue: core.noisePacket,
                                onSave: (v) => _saveXrayCore(
                                  ref,
                                  settings,
                                  core.copyWith(noisePacket: v),
                                ),
                              ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _XrayCoreTextField(
                                    key: ValueKey(
                                      'noise_delay_${core.noiseDelay}',
                                    ),
                                    label: l10n.settingsXrayNoiseDelay,
                                    hint: '0',
                                    initialValue: core.noiseDelay,
                                    onSave: (v) => _saveXrayCore(
                                      ref,
                                      settings,
                                      core.copyWith(noiseDelay: v),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _XrayCoreTextField(
                                    key: ValueKey(
                                      'noise_reset_${core.noiseReset}',
                                    ),
                                    label: l10n.settingsXrayNoiseReset,
                                    hint: '0',
                                    initialValue: core.noiseReset,
                                    onSave: (v) => _saveXrayCore(
                                      ref,
                                      settings,
                                      core.copyWith(noiseReset: v),
                                    ),
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
              crossFadeState: core.noiseEnabled
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 220),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ],
    );
  }
}

class _XrayGeneralSection extends ConsumerWidget {
  const _XrayGeneralSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final core = settings.xrayCore;
    final accent = AppTheme.accent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                if (v != null) _saveXrayCore(ref, settings, core.copyWith(logLevel: v));
              },
              child: Column(
                children: [
                  for (final level in XrayCoreSettings.logLevels)
                    _xrayChoiceTile(
                      context: context,
                      value: level,
                      accent: accent,
                      title: level,
                    ),
                ],
              ),
            ),
            // mihomo её тоже читает: _ipRuleStrategy решает, резолвить ли домен под GEOIP и IP-CIDR
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
                  _saveXrayCore(
                    ref,
                    settings,
                    core.copyWith(routingDomainStrategy: v),
                  );
                }
              },
              child: Column(
                children: [
                  for (final strategy
                      in XrayCoreSettings.routingDomainStrategies)
                    _xrayChoiceTile(
                      context: context,
                      value: strategy,
                      accent: accent,
                      title: strategy,
                    ),
                ],
              ),
            ),
            SwitchListTile(
              value: core.concurrentDial,
              onChanged: (v) =>
                  _saveXrayCore(ref, settings, core.copyWith(concurrentDial: v)),
              activeThumbColor: accent,
              title: Text(l10n.settingsXrayConcurrentDial),
              subtitle: Text(l10n.settingsXrayConcurrentDialHint),
            ),
            SwitchListTile(
              value: core.sniffingEnabled,
              onChanged: (v) {
                _saveXrayCore(ref, 
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
                    ? (v) => _saveXrayCore(ref, settings, core.copyWith(sniffingRouteOnly: v))
                    : null,
                activeThumbColor: accent,
                title: Text(l10n.settingsXraySniffingRouteOnly),
                subtitle: Text(
                  l10n.settingsXraySniffingRouteOnlyHint,
                ),
              ),
            ),
            SwitchListTile(
              value: core.udpPerAddress,
              onChanged: (v) =>
                  _saveXrayCore(ref, settings, core.copyWith(udpPerAddress: v)),
              activeThumbColor: accent,
              title: Text(l10n.settingsXrayUdpPerAddress),
              subtitle: Text(l10n.settingsXrayUdpPerAddressHint),
            ),
          ],
        ),
      ],
    );
  }
}

class _XrayTunSection extends ConsumerWidget {
  const _XrayTunSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings =
        ref.watch(settingsNotifierProvider).value ?? const AppSettings();
    final tun = settings.tun;
    final accent = AppTheme.accent(context);
    final xray = ref.watch(activeVpnBackendProvider) == VpnBackend.xray;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            // TUN xray держит сам и только на gVisor, выбирать там нечего
            if (!xray) ...[
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
                  if (v != null) _saveXrayTun(ref, settings, tun.copyWith(stack: v));
                },
                child: Column(
                  children: [
                    _xrayChoiceTile(
                      context: context,
                      value: TunSettings.stackSystem,
                      accent: accent,
                      title: 'system',
                      subtitle: l10n.settingsTunStackSystemHint,
                    ),
                    _xrayChoiceTile(
                      context: context,
                      value: TunSettings.stackGvisor,
                      accent: accent,
                      title: 'gVisor',
                      subtitle: l10n.settingsTunStackGvisorHint,
                    ),
                    _xrayChoiceTile(
                      context: context,
                      value: TunSettings.stackMixed,
                      accent: accent,
                      title: 'mixed',
                      subtitle: l10n.settingsTunStackMixedHint,
                    ),
                    _xrayChoiceTile(
                      context: context,
                      value: TunSettings.stackMips,
                      accent: accent,
                      title: 'Mips',
                      subtitle: l10n.settingsTunStackMipsHint,
                    ),
                  ],
                ),
              ),
            ],
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
                        _saveXrayTun(ref, 
                          settings,
                          tun.copyWith(mtu: TunSettings.clampMtu(n)),
                        );
                      },
                    ),
                  ),
                  if (xray) const SizedBox(width: 10),
                  if (xray)
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
                          _saveXrayTun(
                            ref,
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
                  if (xray) const SizedBox(width: 10),
                  if (xray)
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
                  _saveXrayTun(ref, settings, tun.copyWith(strictRoute: v));
                }
              },
              child: Column(
                children: [
                  _xrayChoiceTile(
                    context: context,
                    value: TunSettings.strictRouteAuto,
                    accent: accent,
                    title: l10n.settingsTunStrictRouteAuto,
                    subtitle: l10n.settingsTunStrictRouteAutoHint,
                  ),
                  _xrayChoiceTile(
                    context: context,
                    value: TunSettings.strictRouteOn,
                    accent: accent,
                    title: l10n.settingsTunStrictRouteOn,
                  ),
                  _xrayChoiceTile(
                    context: context,
                    value: TunSettings.strictRouteOff,
                    accent: accent,
                    title: l10n.settingsTunStrictRouteOff,
                  ),
                ],
              ),
            ),
            SwitchListTile(
              value: tun.autoRoute,
              onChanged: (v) =>
                  _saveXrayTun(ref, settings, tun.copyWith(autoRoute: v)),
              activeThumbColor: accent,
              title: Text(l10n.settingsTunAutoRoute),
              subtitle: Text(
                l10n.settingsTunAutoRouteHint,
              ),
            ),
            if (xray)
              SwitchListTile(
                value: tun.blockIpv6Leak,
                onChanged: (v) =>
                    _saveXrayTun(ref, settings, tun.copyWith(blockIpv6Leak: v)),
                activeThumbColor: accent,
                title: Text(l10n.settingsTunIpv6),
                subtitle: Text(l10n.settingsTunIpv6Hint),
              ),
          ],
        ),
      ],
    );
  }
}


// многострочное поле не шлёт onSubmitted, поэтому сохраняем по потере фокуса и при уходе
class _DnsServersField extends StatefulWidget {
  const _DnsServersField({
    required this.initialValue,
    required this.label,
    required this.onSave,
    this.hintText = 'https+local://1.1.1.1/dns-query',
  });

  final String initialValue;
  final String label;
  final ValueChanged<String> onSave;

  final String hintText;

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
      textDirection: technicalInputDirection,
      maxLines: 4,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: AppTheme.text(context)),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
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
    this.enabled = true,
    this.helperText,
    this.errorText,
  });

  final String label;
  final String hint;
  final String initialValue;
  final ValueChanged<String> onSave;
  final TextInputType keyboardType;
  final bool enabled;
  final String? helperText;
  final String? errorText;

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
      child: CommitOnBlur(
        controller: _ctrl,
        onCommit: widget.onSave,
        builder: (focus, commit) => TextField(
          controller: _ctrl,
          focusNode: focus,
          enabled: widget.enabled,
          keyboardType: widget.keyboardType,
          textDirection: technicalInputDirection,
          style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppTheme.text(context)),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            helperText: widget.helperText,
            helperMaxLines: 3,
            errorText: widget.errorText,
            errorMaxLines: 3,
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
          onSubmitted: (_) => commit(),
          onEditingComplete: commit,
        ),
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
  if (core.muxEnabled) parts.add('Mux');
  if (core.xmuxEnabled) parts.add('XMUX');
  if (!tun.isDefault) parts.add('TUN');
  if (customPorts) parts.add('${current.localPort}/${current.httpPort}');
  return parts.join(' · ');
}
