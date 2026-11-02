part of 'providers.dart';

class SplitTunnelingState {
  final Set<String> excludePackages;
  final Set<String> includePackages;

  const SplitTunnelingState({
    this.excludePackages = const {},
    this.includePackages = const {},
  });

  SplitTunnelingState copyWith({
    Set<String>? excludePackages,
    Set<String>? includePackages,
  }) =>
      SplitTunnelingState(
        excludePackages: excludePackages ?? this.excludePackages,
        includePackages: includePackages ?? this.includePackages,
      );
}

class SplitTunnelingNotifier extends Notifier<SplitTunnelingState> {
  @override
  SplitTunnelingState build() {
    final storage = ref.read(storageProvider);
    return SplitTunnelingState(
      excludePackages: storage.getExcludePackages().toSet(),
      includePackages: storage.getIncludePackages().toSet(),
    );
  }

  // без учёта регистра: старые версии сохраняли telegram.exe, а список даёт Telegram.exe
  static Set<String> _togglePackage(Set<String> current, String pkg) {
    final key = pkg.toLowerCase();
    final next = {...current}..removeWhere((e) => e.toLowerCase() == key);
    if (next.length == current.length) next.add(pkg);
    return next;
  }

  Future<void> toggleExclude(String pkg) async {
    final set = _togglePackage(state.excludePackages, pkg);
    await ref.read(storageProvider).setExcludePackages(set.toList());
    await ref.read(storageProvider).setIncludePackages([]);
    state = state.copyWith(excludePackages: set, includePackages: const {});
  }

  Future<void> toggleInclude(String pkg) async {
    final set = _togglePackage(state.includePackages, pkg);
    await ref.read(storageProvider).setIncludePackages(set.toList());
    await ref.read(storageProvider).setExcludePackages([]);
    state = state.copyWith(includePackages: set, excludePackages: const {});
  }

  static Set<String> toggledEntries(Set<String> current, AppInfo app) {
    final next = {...current}..removeWhere((e) => splitEntryMatches(e, app));
    if (next.length == current.length) next.add(app.packageName);
    return next;
  }

  Future<void> toggleApp(AppInfo app, {required bool include}) async {
    final next = toggledEntries(
      include ? state.includePackages : state.excludePackages,
      app,
    );
    final storage = ref.read(storageProvider);
    if (include) {
      await storage.setIncludePackages(next.toList());
      await storage.setExcludePackages([]);
      state = state.copyWith(includePackages: next, excludePackages: const {});
    } else {
      await storage.setExcludePackages(next.toList());
      await storage.setIncludePackages([]);
      state = state.copyWith(excludePackages: next, includePackages: const {});
    }
  }

  // одним обновлением state: циклом toggleExclude записи гонялись между собой
  Future<int> addAllExcludes(List<String> packages) async {
    if (packages.isEmpty) return 0;
    final set = {...state.excludePackages, ...packages};
    final added = set.length - state.excludePackages.length;
    if (added == 0) return 0;
    await ref.read(storageProvider).setExcludePackages(set.toList());
    await ref.read(storageProvider).setIncludePackages([]);
    state = state.copyWith(excludePackages: set, includePackages: const {});
    return added;
  }

  Future<void> clearExcludes() async {
    await ref.read(storageProvider).setExcludePackages([]);
    state = state.copyWith(excludePackages: const {});
  }

  Future<void> clearIncludes() async {
    await ref.read(storageProvider).setIncludePackages([]);
    state = state.copyWith(includePackages: const {});
  }

  Future<void> clearAll() async {
    await ref.read(storageProvider).setExcludePackages([]);
    await ref.read(storageProvider).setIncludePackages([]);
    state = const SplitTunnelingState();
  }

  Future<void> addCustomProcess(String raw, {required bool asInclude}) async {
    final entry = isProcessPathEntry(raw)
        ? normalizeProcessPath(raw)
        : normalizeProcessName(raw);
    if (entry.isEmpty || normalizeProcessName(entry).isEmpty) return;
    if (asInclude) {
      await toggleInclude(entry);
    } else {
      await toggleExclude(entry);
    }
  }
}

final splitTunnelingProvider =
NotifierProvider<SplitTunnelingNotifier, SplitTunnelingState>(
  SplitTunnelingNotifier.new,
);

final installedAppsProvider =
    FutureProvider.autoDispose.family<List<AppInfo>, bool>(
      (ref, includeSystem) async {
    final link = ref.keepAlive();
    Timer? release;
    ref.onCancel(() {
      release?.cancel();
      release = Timer(const Duration(minutes: 3), link.close);
    });
    ref.onResume(() => release?.cancel());
    ref.onDispose(() => release?.cancel());
    final engine = ref.read(vpnEngineProvider);
    final rawList = await engine.getInstalledApps(includeSystem: includeSystem);
    return rawList.map(AppInfo.fromJson).toList()
      ..sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
  },
);

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    return ref.read(storageProvider).getSettings();
  }

  Future<void> save(AppSettings settings) async {
    state = AsyncData(settings);
    await ref.read(storageProvider).saveSettings(settings);
  }

  Future<void> reset() async {
    await save(const AppSettings());
  }
}

final settingsNotifierProvider =
AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// владельца соединения Android называет с 10-й версии (getConnectionOwnerUid), ниже защите адреса сервера не на чем работать
final androidSdkIntProvider = FutureProvider<int?>((ref) async {
  if (!Platform.isAndroid) return null;
  return (await VpnNativeBridge.getNativeInternals())['sdkInt'] as int?;
});

final activeVpnBackendProvider = Provider<VpnBackend>((ref) {
  final preference = ref.watch(
    settingsNotifierProvider.select(
      (a) => a.value?.vpnCore ?? AppSettings.vpnCoreXray,
    ),
  );
  final server = ref.watch(serversProvider).activeServer;
  if (server == null) {
    return preference == AppSettings.vpnCoreMihomo && mihomoShipsHere
        ? VpnBackend.mihomo
        : VpnBackend.xray;
  }
  final sub = server.subscriptionId;
  final template =
      sub == null ? null : ref.watch(subscriptionTemplateProvider(sub));
  return serverBackendChoice(
    server,
    preference: preference,
    viaTemplate: template?.nodeFor(server) != null,
  ).backend;
});
