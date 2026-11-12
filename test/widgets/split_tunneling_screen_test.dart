import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_info.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/split_tunneling_screen.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';
import 'package:keqdroid/utils/process_name_utils.dart';

import '../helpers/fake_tunnel_backend.dart';

/// Списки берём из состояния, а не из хранилища: настоящий нотифаер лезет в
/// SharedPreferences, которых в тесте нет.
class _FakeSplit extends SplitTunnelingNotifier {
  _FakeSplit(this._state);

  final SplitTunnelingState _state;

  @override
  SplitTunnelingState build() => _state;

  /// Настоящий toggle пишет в SharedPreferences; здесь нужен только сдвиг
  /// состояния — экран слушает именно его. Сам расчёт — настоящий.
  @override
  Future<void> toggleApp(AppInfo app, {required bool include}) async {
    state = include
        ? state.copyWith(
            includePackages: SplitTunnelingNotifier.toggledEntries(
              state.includePackages,
              app,
            ),
          )
        : state.copyWith(
            excludePackages: SplitTunnelingNotifier.toggledEntries(
              state.excludePackages,
              app,
            ),
          );
  }
}

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class _FakeVpn extends VpnStateNotifier {
  _FakeVpn(this._status);

  final VpnStatus _status;
  static int reconnects = 0;

  @override
  Future<VpnState> build() async => VpnState(status: _status);

  @override
  Future<void> reconnectToActiveServer() async => reconnects++;
}

AppInfo _app(String pkg, String name, {bool running = false}) => AppInfo(
      packageName: pkg,
      appName: name,
      isRunning: running,
      installPath: r'C:\Program Files\' '$name.exe',
    );

/// Список в том виде, в каком его отдаёт Windows: имя процесса с настоящим
/// регистром и полный путь.
final _windowsApps = <AppInfo>[
  const AppInfo(
    packageName: 'Discord.exe',
    appName: 'Discord.exe',
    installPath: r'C:\Users\u\AppData\Local\Discord\Discord.exe',
    isRunning: true,
  ),
  const AppInfo(
    packageName: 'Telegram.exe',
    appName: 'Telegram.exe',
    installPath: r'C:\Program Files\Telegram Desktop\Telegram.exe',
  ),
];

final _apps = <AppInfo>[
  _app('com.telegram', 'Telegram', running: true),
  _app('com.discord', 'Discord'),
  _app('ru.sberbank.online', 'СберБанк Онлайн'),
  _app('com.spotify.music', 'Spotify'),
  _app('org.mozilla.firefox', 'Firefox'),
  _app('com.valve.steam', 'Steam'),
];

/// Отмечена ли строка: выбор на экране несёт сегмент списка, а не отдельный
/// значок, — по нему и спрашиваем.
bool _isRowSelected(WidgetTester tester, String title) {
  final segment = tester.widget<ExpressiveListSegment>(
    find
        .ancestor(
          of: find.text(title),
          matching: find.byType(ExpressiveListSegment),
        )
        .first,
  );
  return segment.selected;
}

Future<void> _pump(
  WidgetTester tester, {
  Set<String> excludes = const {},
  VpnStatus status = VpnStatus.disconnected,
  Size size = const Size(1080, 2160),
  double pixelRatio = 3,
  List<AppInfo>? apps,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        installedAppsProvider(false).overrideWith((ref) async => apps ?? _apps),
        splitTunnelingProvider.overrideWith(
          () => _FakeSplit(SplitTunnelingState(excludePackages: excludes)),
        ),
        settingsNotifierProvider.overrideWith(_FakeSettings.new),
        vpnStateProvider.overrideWith(() => _FakeVpn(status)),
        // Без этого экран поднимает НАСТОЯЩИЙ бэкенд туннеля (через него идут
        // иконки приложений), а на Linux его dispose зовёт gsettings — тест
        // падал на CI и правил прокси рабочего стола. См. FakeTunnelBackend.
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme(
          ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4),
            brightness: Brightness.dark,
          ),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: const SplitTunnelingScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Программы и пути здесь виндовые, а CI гоняет тесты на Linux: без подмены
  // экран применял бы к ним правила той машины, на которой запущен.
  setUp(() => debugWindowsProcessRules = true);
  tearDown(() => debugWindowsProcessRules = null);

  testWidgets('экран раскладывается без переполнений', (tester) async {
    await _pump(tester, excludes: {'com.telegram', 'ru.sberbank.online'});

    expect(tester.takeException(), isNull);
    expect(find.text('Telegram'), findsOneWidget);
    // Подписи режимов должны помещаться целиком — ради этого селектор и стоит
    // на сегментах списка, а не на связанной группе кнопок с одной строкой.
    expect(find.text('Все кроме выбранных'), findsOneWidget);
    expect(find.text('Только выбранные'), findsOneWidget);
    // Счётчик выбранных переехал из шапки в заголовок секции над списком.
    expect(find.text('Выбрано приложений: 2'), findsOneWidget);
  });

  testWidgets('поиск остаётся на экране при прокрутке списка', (tester) async {
    await _pump(tester);

    final search = find.byType(SearchBar);
    expect(search, findsOneWidget);
    final before = tester.getTopLeft(search);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    // Прилипшая шапка: полоса поиска не уезжает вместе с содержимым.
    expect(tester.getTopLeft(search).dy, lessThanOrEqualTo(before.dy));
    expect(search, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('при активном туннеле показывается напоминание', (tester) async {
    await _pump(tester, status: VpnStatus.connected, excludes: {'com.discord'});

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('переподключ'),
      findsWidgets,
    );
  });

  // 12.11.2026, просьба из чата: «а можно сюда тоже кнопку переподключиться как в правилах?»
  testWidgets('переподключиться можно прямо из напоминания', (tester) async {
    _FakeVpn.reconnects = 0;
    await _pump(tester, status: VpnStatus.connected);

    await tester.tap(find.text('Переподключить'));
    await tester.pumpAndSettle();
    expect(_FakeVpn.reconnects, 1);
  });

  testWidgets('пока туннель поднимается, кнопка не нажимается', (tester) async {
    _FakeVpn.reconnects = 0;
    await _pump(tester, status: VpnStatus.connecting);

    final button = find.ancestor(
      of: find.text('Переподключить'),
      matching: find.byType(TextButton),
    );
    expect(tester.widget<TextButton>(button).onPressed, isNull);
  });

  group('дубли строк', () {
    testWidgets('выбранное приложение не удваивается', (tester) async {
      // Windows отдаёт `Discord.exe`, и в списке исключений лежит ровно оно.
      // Пока сравнение шло по сырой строке против набора в нижнем регистре,
      // запись считалась «добавленной руками» и приписывалась второй строкой.
      await _pump(
        tester,
        apps: _windowsApps,
        excludes: {'Discord.exe'},
      );

      expect(find.text('Discord.exe'), findsOneWidget);
      expect(find.text('Выбрано приложений: 1'), findsOneWidget);
    });

    testWidgets('сохранённое имя в другом регистре — та же строка', (
      tester,
    ) async {
      // Старая версия писала имена в нижнем регистре. Такая запись не должна
      // рождать второй строки и обязана показывать отметку на своей.
      await _pump(
        tester,
        apps: _windowsApps,
        excludes: {'telegram.exe'},
      );

      expect(find.text('Telegram.exe'), findsOneWidget);
      expect(_isRowSelected(tester, 'Telegram.exe'), isTrue);
      expect(_isRowSelected(tester, 'Discord.exe'), isFalse);
    });

    testWidgets('повторные переключения не плодят строк', (tester) async {
      // Дубли накапливались именно так: слияние повторялось поверх уже
      // слитого списка на каждое изменение выбора.
      await _pump(tester, apps: _windowsApps);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Discord.exe'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Telegram.exe'));
        await tester.pumpAndSettle();
      }

      // Считаем сегменты, а не подписи: три из них — селектор режимов,
      // остальные и есть строки списка.
      expect(
        find.byType(ExpressiveListSegment),
        findsNWidgets(3 + _windowsApps.length),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // Отмеченное в списке сохраняется именем — программа, обновившаяся в новую
  // папку, остаётся в сплите; путь, указанный вручную, — «только этот файл».
  group('путь и имя', () {
    // Две строки в тестовом окне ложатся под плавающую кнопку «Добавить», и
    // нажатие по координатам ловит она. Зовём обработчик самой строки.
    Future<void> tapRow(WidgetTester tester, String title) async {
      tester
          .widget<ExpressiveListSegment>(
            find
                .ancestor(
                  of: find.text(title),
                  matching: find.byType(ExpressiveListSegment),
                )
                .first,
          )
          .onTap!();
      await tester.pumpAndSettle();
    }

    SplitTunnelingState state(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(SplitTunnelingScreen)),
        ).read(splitTunnelingProvider);

    testWidgets('отметка строки сохраняет её имя, а не путь', (tester) async {
      await _pump(tester, apps: _windowsApps, excludes: {'Telegram.exe'});

      await tapRow(tester, 'Discord.exe');

      expect(state(tester).excludePackages, {'Telegram.exe', 'Discord.exe'});
      expect(_isRowSelected(tester, 'Discord.exe'), isTrue);
    });

    testWidgets('строка, отмеченная старым именем, снимается', (tester) async {
      await _pump(
        tester,
        apps: _windowsApps,
        excludes: {'telegram.exe', 'Discord.exe'},
      );

      await tapRow(tester, 'Telegram.exe');

      expect(state(tester).excludePackages, {'Discord.exe'});
      expect(_isRowSelected(tester, 'Telegram.exe'), isFalse);
    });

    testWidgets('путь к программе не из списка — своя строка с этим путём', (
      tester,
    ) async {
      await _pump(
        tester,
        apps: _windowsApps,
        excludes: {r'C:\Games\Launcher\Update.exe'},
      );

      expect(find.text('Update.exe'), findsOneWidget);
      expect(find.text(r'C:\Games\Launcher\Update.exe'), findsOneWidget);
      expect(_isRowSelected(tester, 'Update.exe'), isTrue);
      expect(_isRowSelected(tester, 'Discord.exe'), isFalse);
    });

    testWidgets('одно имя, разные пути — отмечена только своя строка', (
      tester,
    ) async {
      await _pump(
        tester,
        apps: const [
          AppInfo(
            packageName: 'Update.exe',
            appName: 'Launcher A',
            installPath: r'C:\A\Update.exe',
          ),
          AppInfo(
            packageName: 'Update.exe',
            appName: 'Launcher B',
            installPath: r'C:\B\Update.exe',
          ),
        ],
        excludes: {r'C:\B\Update.exe'},
      );

      expect(_isRowSelected(tester, 'Launcher B'), isTrue);
      expect(_isRowSelected(tester, 'Launcher A'), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('в невысоком окне заголовок обычный, а не крупный', (
    tester,
  ) async {
    // Окно из трея: 152dp крупной шапки съели бы половину экрана.
    await _pump(
      tester,
      size: const Size(288, 480),
      pixelRatio: 1,
      excludes: {'com.telegram'},
    );

    expect(tester.takeException(), isNull);
    final bar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    expect(bar.expandedHeight, isNull);
    expect(bar.pinned, isTrue);
  });
}
