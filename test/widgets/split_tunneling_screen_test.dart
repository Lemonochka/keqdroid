import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_info.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/split_tunneling_screen.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';
import 'package:keqdroid/tunnel/tunnel_state.dart';

/// Списки берём из состояния, а не из хранилища: настоящий нотифаер лезет в
/// SharedPreferences, которых в тесте нет.
class _FakeSplit extends SplitTunnelingNotifier {
  _FakeSplit(this._state);

  final SplitTunnelingState _state;

  @override
  SplitTunnelingState build() => _state;

  /// Настоящий toggle пишет в SharedPreferences; здесь нужен только сдвиг
  /// состояния — экран слушает именно его.
  @override
  Future<void> toggleExclude(String pkg) async {
    final key = pkg.toLowerCase();
    final next = {...state.excludePackages}
      ..removeWhere((e) => e.toLowerCase() == key);
    if (next.length == state.excludePackages.length) next.add(pkg);
    state = state.copyWith(excludePackages: next);
  }
}

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class _FakeVpn extends VpnStateNotifier {
  _FakeVpn(this._status);

  final VpnStatus _status;

  @override
  Future<VpnState> build() async => VpnState(status: _status);
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
