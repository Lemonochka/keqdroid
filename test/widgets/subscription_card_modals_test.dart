import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/models/subscription_card_layout.dart';
import 'package:keqdroid/models/subscription_card_theme.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/subscriptions_tab.dart';
import 'package:keqdroid/services/rule_list_service.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../helpers/fake_tunnel_backend.dart';
import '../helpers/test_storage.dart';

final _en = lookupAppLocalizations(const Locale('en'));

const _sub = Subscription(id: 'a', name: 'Gaming VPN', url: 'https://a.example/sub');

class _Edit {
  _Edit(this.id, this.name, this.url, this.resetName, this.identity);

  final String id;
  final String? name;
  final String? url;
  final bool resetName;
  final SubscriptionFetchIdentity? identity;
}

final _edits = <_Edit>[];
final _removed = <String>[];
Object? _editFailure;

class _FakeSubs extends SubscriptionsNotifier {
  @override
  Future<List<Subscription>> build() async => const [_sub];

  @override
  Future<void> editMeta(
    String id, {
    String? name,
    String? url,
    bool resetName = false,
    SubscriptionFetchIdentity? fetchIdentity,
    String? cardThemeId,
    bool? cardThemeInServers,
    Set<SubscriptionCardElement>? hiddenCardElements,
    CardVeil? cardVeil,
    bool? autoSelectVisible,
    bool? autoSelect,
  }) async {
    if (_editFailure != null) throw _editFailure!;
    _edits.add(_Edit(id, name, url, resetName, fetchIdentity));
  }

  @override
  Future<void> remove(String id) async => _removed.add(id);
}

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class _FakeVpn extends VpnStateNotifier {
  @override
  Future<VpnState> build() async =>
      const VpnState(status: VpnStatus.disconnected);
}

class _FakeRuleLists extends RuleListsNotifier {
  @override
  Map<String, RuleListStatus> build() => const {};
}

Future<void> _openMenu(WidgetTester tester) async {
  // шрифт тестов шире настоящего: на ширине телефона заголовок окна удаления не влезает
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final storage = await buildStorageService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        subscriptionsProvider.overrideWith(_FakeSubs.new),
        settingsNotifierProvider.overrideWith(_FakeSettings.new),
        vpnStateProvider.overrideWith(_FakeVpn.new),
        ruleListsProvider.overrideWith(_FakeRuleLists.new),
        vpnEngineProvider.overrideWithValue(
          VpnEngine.withBackend(FakeTunnelBackend()),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const SubscriptionsTab(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.more_vert_rounded));
  await tester.pumpAndSettle();
}

Future<void> _openFromMenu(WidgetTester tester, String title) async {
  await _openMenu(tester);
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _edits.clear();
    _removed.clear();
    _editFailure = null;
  });

  testWidgets('card menu lists its actions under the subscription name',
      (tester) async {
    await _openMenu(tester);
    final sheet = find.byType(BottomSheet);
    for (final title in [
      _en.subscriptionsEditSubscription,
      _en.subscriptionCardLookTitle,
      _en.subscriptionsShareButton,
      _en.subscriptionsDelete,
      _sub.name,
    ]) {
      expect(find.descendant(of: sheet, matching: find.text(title)),
          findsOneWidget, reason: title);
    }
  });

  testWidgets('edit sheet starts from the subscription and saves new values',
      (tester) async {
    await _openFromMenu(tester, _en.subscriptionsEditSubscription);
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller!.text, _sub.name);
    expect(fields[1].controller!.text, _sub.url);

    await tester.enterText(find.byType(TextField).at(0), ' New name ');
    await tester.enterText(find.byType(TextField).at(1), ' https://b.example ');
    await tester.tap(find.text(_en.subscriptionsSave));
    await tester.pumpAndSettle();

    expect(_edits, hasLength(1));
    expect(_edits.single.id, 'a');
    expect(_edits.single.name, 'New name');
    expect(_edits.single.url, 'https://b.example');
    expect(_edits.single.resetName, isFalse);
    expect(_edits.single.identity, _sub.fetchIdentity);
    expect(find.text(_en.subscriptionsEditSubscription), findsNothing);
  });

  testWidgets('emptied name asks for the name to be reset', (tester) async {
    await _openFromMenu(tester, _en.subscriptionsEditSubscription);
    await tester.enterText(find.byType(TextField).at(0), '   ');
    await tester.tap(find.text(_en.subscriptionsSave));
    await tester.pumpAndSettle();

    expect(_edits.single.name, isNull);
    expect(_edits.single.resetName, isTrue);
  });

  testWidgets('empty address saves nothing and keeps the sheet open',
      (tester) async {
    await _openFromMenu(tester, _en.subscriptionsEditSubscription);
    await tester.enterText(find.byType(TextField).at(1), '   ');
    await tester.tap(find.text(_en.subscriptionsSave));
    await tester.pumpAndSettle();

    expect(_edits, isEmpty);
    expect(find.text(_en.subscriptionsEditSubscription), findsOneWidget);
  });

  testWidgets('failed save shows the error and keeps the sheet open',
      (tester) async {
    _editFailure = Exception('boom');
    await _openFromMenu(tester, _en.subscriptionsEditSubscription);
    await tester.tap(find.text(_en.subscriptionsSave));
    await tester.pumpAndSettle();

    expect(find.text(_en.subscriptionsEditSubscription), findsOneWidget);
    final sheet = find.byType(BottomSheet);
    final texts = tester
        .widgetList<Text>(find.descendant(of: sheet, matching: find.byType(Text)))
        .map((t) => t.data ?? '');
    expect(texts.where((t) => t.contains('boom')), isNotEmpty);
  });

  testWidgets('leaving the edit sheet without saving changes nothing',
      (tester) async {
    await _openFromMenu(tester, _en.subscriptionsEditSubscription);
    await tester.enterText(find.byType(TextField).at(0), 'Other');
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(_edits, isEmpty);
    expect(find.text(_en.subscriptionsEditSubscription), findsNothing);
  });

  testWidgets('share sheet shows the QR of the address and the action',
      (tester) async {
    await _openFromMenu(tester, _en.subscriptionsShareButton);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.widgetWithText(SelectableText, _sub.url), findsOneWidget);
    expect(
      find.text(Platform.isLinux
          ? _en.subscriptionsSave
          : _en.subscriptionsShareAction),
      findsOneWidget,
    );
  });

  testWidgets('delete asks first, cancel keeps the subscription',
      (tester) async {
    await _openFromMenu(tester, _en.subscriptionsDelete);
    expect(find.text(_en.subscriptionsDeleteConfirm(_sub.name)), findsOneWidget);

    await tester.tap(find.text(_en.subscriptionsCancel));
    await tester.pumpAndSettle();
    expect(_removed, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('confirmed delete removes the subscription', (tester) async {
    await _openFromMenu(tester, _en.subscriptionsDelete);
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(_en.subscriptionsDelete),
    ));
    await tester.pumpAndSettle();
    expect(_removed, ['a']);
  });
}
