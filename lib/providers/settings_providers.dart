part of 'providers.dart';

class RoutingRulesNotifier extends AsyncNotifier<List<RoutingRule>> {
  @override
  Future<List<RoutingRule>> build() async {
    return ref.read(storageProvider).getRules();
  }

  Future<void> add(RoutingRule rule) async {
    final rules = [...?state.value, rule];
    await ref.read(storageProvider).saveRules(rules);
    state = AsyncData(rules);
  }

  Future<void> updateRule(RoutingRule rule) async {
    final rules = (state.value ?? [])
        .map((r) => r.id == rule.id ? rule : r)
        .toList();
    await ref.read(storageProvider).saveRules(rules);
    state = AsyncData(rules);
  }

  Future<void> remove(String id) async {
    final rules = (state.value ?? []).where((r) => r.id != id).toList();
    await ref.read(storageProvider).saveRules(rules);
    state = AsyncData(rules);
  }

  Future<void> toggle(String id) async {
    final rules = (state.value ?? [])
        .map((r) => r.id == id ? r.copyWith(enabled: !r.enabled) : r)
        .toList();
    await ref.read(storageProvider).saveRules(rules);
    state = AsyncData(rules);
  }

  Future<void> resetToDefaults() async {
    final rules = RoutingRule.defaults;
    await ref.read(storageProvider).saveRules(rules);
    state = AsyncData(rules);
  }
}

final routingRulesProvider =
AsyncNotifierProvider<RoutingRulesNotifier, List<RoutingRule>>(
  RoutingRulesNotifier.new,
);

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

  /// Снятие отметки без учёта регистра.
  ///
  /// `Telegram.exe` из списка процессов Windows и `telegram.exe`, сохранённый
  /// старой версией, — одно приложение: правило по нему всё равно уходит в
  /// обеих формах ([processNameMatchVariants]). Пока сравнение шло по сырой
  /// строке, повторное нажатие по такой строке не снимало отметку, а клало в
  /// список ВТОРУЮ запись, и на экране появлялся близнец.
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

  /// добавляет пачку пакетов в excludePackages одним обновлением state
  /// (вместо цикла toggleExclude, иначе ловим race condition).
  /// Возвращает, сколько пакетов реально добавилось (без дублей); при пустом
  /// результате не трогает storage вообще (иначе зря стирали includePackages).
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

  /// ручное добавление exe/пути (Windows и произвольные записи)
  Future<void> addCustomProcess(String raw, {required bool asInclude}) async {
    final name = normalizeProcessName(raw);
    if (name.isEmpty) return;
    if (asInclude) {
      await toggleInclude(name);
    } else {
      await toggleExclude(name);
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
    // Список тяжёлый (base64-иконка у каждого приложения — мегабайты строк),
    // поэтому не держим его в памяти вечно: кэш живёт, пока экран открыт,
    // плюс 3 минуты после ухода последнего слушателя — быстрый повторный вход
    // обходится без перезагрузки, а дальше список освобождается.
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

  /// Состояние обновляется ДО записи на диск, а не после неё.
  ///
  /// `saveSettings` уходит в SharedPreferences через платформенный канал, и
  /// пока летел этот круговой рейс, интерфейс стоял: между нажатием на
  /// «Тёмная» и собственно сменой темы была пауза, которая читалась залипанием
  /// переключателя. Настройка — не транзакция, подтверждать её записью незачем.
  ///
  /// Порядок записей от перестановки не страдает: StorageService выстраивает
  /// их в одну очередь в порядке ВЫЗОВА (см. `_serial`), а состояние здесь
  /// меняется в том же порядке.
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