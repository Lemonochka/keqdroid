import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keqdroid/app/app.dart';
import 'package:keqdroid/core/app_logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:keqdroid/platform/platform_bootstrap.dart';
import 'package:keqdroid/services/background_service.dart';
import 'package:keqdroid/services/desktop_background_service.dart';
import 'package:keqdroid/services/notification_service.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers_tab.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/screens/subscriptions_tab.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/update_service.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/bottom_nav.dart';
import 'package:keqdroid/shared/ui/update_dialog.dart';
import 'package:keqdroid/ui/desktop/desktop_home_screen.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    var crashlyticsReady = false;
    if (Platform.isAndroid) {
      try {
        await Firebase.initializeApp();
        crashlyticsReady = true;
      } catch (e, st) {
        AppLogger.instance.warn(
          'Firebase is not configured. Crash reporting is disabled.',
          error: e,
          stackTrace: st,
        );
      }
      await BackgroundService.init();
      await BackgroundService.registerPeriodicTask();
      await NotificationService.init();
    } else if (Platform.isWindows) {
      await PlatformBootstrap.initialize();
    } else if (Platform.isLinux || Platform.isMacOS) {
      await DesktopBackgroundService.init();
    }

    AppLogger.instance.setCrashlyticsEnabled(crashlyticsReady && !kDebugMode);
    if (crashlyticsReady) {
      FlutterError.onError = (details) {
        unawaited(AppLogger.instance.recordError(
          details.exception,
          details.stack ?? StackTrace.current,
          reason: 'Flutter framework error',
        ));
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(AppLogger.instance.recordError(
          error,
          stack,
          reason: 'Platform dispatcher error',
        ));
        return true;
      };
    }

    final storage = await StorageService.init();

    final home = Platform.isWindows
        ? const DesktopHomeScreen()
        : const VpnHomeScreen();

    runApp(
      ProviderScope(
        overrides: [storageProvider.overrideWithValue(storage)],
        child: KeqdisApp(home: home),
      ),
    );
  }, (error, stack) async {
    await AppLogger.instance.recordError(
      error,
      stack,
      reason: 'runZonedGuarded unhandled error',
      fatal: true,
    );
  });
}

class VpnHomeScreen extends ConsumerStatefulWidget {
  const VpnHomeScreen({super.key});
  @override
  ConsumerState<VpnHomeScreen> createState() => _VpnHomeScreenState();
}

class _VpnHomeScreenState extends ConsumerState<VpnHomeScreen> {
  static const _tabCount = 3;

  int _navIndex = 0;
  late final PageController _pageCtrl;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _pageCtrl.addListener(_onPageScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(updateInfoProvider);
      }
    });
  }

  @override
  void dispose() {
    _pageCtrl.removeListener(_onPageScroll);
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onPageScroll() {
    final page = _pageCtrl.page;
    if (page == null) return;

    ref.read(homeTabPageProvider.notifier).state = page;

    final rounded = page.round().clamp(0, _tabCount - 1);
    if (rounded != _navIndex) {
      setState(() => _navIndex = rounded);
    }
  }

  void _onPageSettled(int index) {
    ref.read(homeTabIndexProvider.notifier).state = index;
    ref.read(homeTabPageProvider.notifier).state = index.toDouble();
    if (_navIndex != index) {
      setState(() => _navIndex = index);
    }
  }

  void _selectTab(int index) {
    if (_navIndex == index) return;
    ref.read(homeTabIndexProvider.notifier).state = index;

    if ((index - _navIndex).abs() > 1) {
      _pageCtrl.jumpToPage(index);
      ref.read(homeTabPageProvider.notifier).state = index.toDouble();
      setState(() => _navIndex = index);
      return;
    }

    _pageCtrl.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<UpdateInfo?>>(updateInfoProvider, (prev, next) {
      if (!shouldAutoPromptForUpdate(prev, next)) return;
      final info = next.valueOrNull;
      if (info == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showUpdateDialog(context, info);
      });
    });

    final isConnected = ref.watch(
      vpnStateProvider.select(
        (a) => a.valueOrNull?.status == VpnStatus.connected,
      ),
    );
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      body: PageView(
        controller: _pageCtrl,
        physics: const ClampingScrollPhysics(),
        dragStartBehavior: DragStartBehavior.down,
        onPageChanged: _onPageSettled,
        children: [
          _HomeTabPage(child: ServersTab()),
          _HomeTabPage(child: const SubscriptionsTab()),
          _HomeTabPage(child: SettingsTab()),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        index: _navIndex,
        showConnectedBadge: isConnected,
        onTap: _selectTab,
      ),
    );
  }
}

class _HomeTabPage extends StatefulWidget {
  final Widget child;
  const _HomeTabPage({required this.child});

  @override
  State<_HomeTabPage> createState() => _HomeTabPageState();
}

class _HomeTabPageState extends State<_HomeTabPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
