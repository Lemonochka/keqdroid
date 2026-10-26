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
import 'package:keqdroid/platform/windows_cert_trust.dart';
import 'package:keqdroid/services/background_service.dart';
import 'package:keqdroid/services/card_image_service.dart';
import 'package:keqdroid/services/desktop_background_service.dart';
import 'package:keqdroid/services/notification_service.dart';
import 'package:keqdroid/services/prefs_recovery.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/screens/servers_tab.dart';
import 'package:keqdroid/services/vpn_engine.dart';
import 'package:keqdroid/screens/subscriptions_tab.dart';
import 'package:keqdroid/screens/settings_tab.dart';
import 'package:keqdroid/services/linux_background_service.dart';
import 'package:keqdroid/services/memory_watch.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/update_service.dart';
import 'package:keqdroid/tunnel/linux_tunnel_backend.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/bottom_nav.dart';
import 'package:keqdroid/shared/ui/halloween/halloween_icons.dart';
import 'package:keqdroid/shared/ui/liquid_bud.dart';
import 'package:keqdroid/shared/ui/liquid_wave.dart';
import 'package:keqdroid/shared/ui/nav_rail.dart';
import 'package:keqdroid/shared/ui/smooth_fade.dart';
import 'package:keqdroid/shared/ui/update_dialog.dart';
import 'package:keqdroid/ui/desktop/desktop_home_screen.dart';
import 'package:keqdroid/ui/responsive/window_breakpoints.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // до всего остального: ошибка до runApp иначе не оставит следа
    await AppLogger.instance.enableFileLog();
    if (Platform.isWindows) HttpOverrides.global = WindowsSystemTrust();
    await PrefsRecovery.prepare();

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
      await PlatformBootstrap.initialize();
      // пульт шлёт клавиши как виртуальная клавиатура, без этого фокус не видно
      if (PlatformBootstrap.isTelevision) {
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
      }
    } else if (Platform.isWindows) {
      await PlatformBootstrap.initialize();
    } else if (Platform.isLinux || Platform.isMacOS) {
      await DesktopBackgroundService.init();
      if (Platform.isLinux) {
        final primary =
            await LinuxBackgroundService.instance.ensureSingleInstance();
        if (!primary) {
          exit(0);
        }
        await LinuxTunnelBackend.cleanupStaleState();
        await LinuxBackgroundService.instance.initWindowAndTray();
      }
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
    // до первого кадра, иначе выбранная картинка карточки не покажется
    await CardImageService.warmUp();
    await SmoothFade.load();
    await LiquidWave.loadShaders();
    await LiquidBud.load();

    final home = Platform.isWindows || Platform.isLinux
        ? const DesktopHomeScreen()
        : const VpnHomeScreen();

    runApp(
      ProviderScope(
        overrides: [storageProvider.overrideWithValue(storage)],
        child: KeqdisApp(home: home),
      ),
    );

    MemoryWatch.instance.start();
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
  bool _lastServersVisible = true;

  // вкладки живут в PageView с keepAlive: без этого гифки подписок крутились и на
  // настройках, около 50% ядра на одном потоке io (Pixel 6a, 26.10.2026)
  int _onScreen = 1;
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

    final serversVisible = page < 0.05;
    if (serversVisible != _lastServersVisible) {
      _lastServersVisible = serversVisible;
      ref.read(homeTabPageProvider.notifier).set(serversVisible ? 0.0 : 1.0);
    }

    final rounded = page.round().clamp(0, _tabCount - 1);
    var onScreen = 0;
    for (var i = 0; i < _tabCount; i++) {
      if ((page - i).abs() < 0.999) onScreen |= 1 << i;
    }
    if (rounded != _navIndex || onScreen != _onScreen) {
      setState(() {
        _navIndex = rounded;
        _onScreen = onScreen;
      });
    }
  }

  void _onPageSettled(int index) {
    ref.read(homeTabIndexProvider.notifier).set(index);
    _lastServersVisible = index == 0;
    ref.read(homeTabPageProvider.notifier).set(_lastServersVisible ? 0.0 : 1.0);
    if (_navIndex != index) {
      setState(() => _navIndex = index);
    }
  }

  void _selectTab(int index) {
    if (_navIndex == index) return;
    ref.read(homeTabIndexProvider.notifier).set(index);

    if ((index - _navIndex).abs() > 1) {
      _pageCtrl.jumpToPage(index);
      _lastServersVisible = index == 0;
      ref.read(homeTabPageProvider.notifier).set(_lastServersVisible ? 0.0 : 1.0);
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
      final info = next.value;
      if (info == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showUpdateDialog(context, info);
      });
    });

    final isConnected = ref.watch(
      vpnStateProvider.select(
        (a) => a.value?.status == VpnStatus.connected,
      ),
    );
    final expanded = WindowBreakpoints.isExpandedMobile(context);
    final railAtLeft = Directionality.of(context) == TextDirection.ltr;
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      // шторки и маршруты отступают от клавиатуры сами, а ужатая оболочка
      // иногда так и оставалась ужатой после возврата
      resizeToAvoidBottomInset: false,
      body: Row(
        children: [
          if (expanded)
            HalloweenIconScope(
              child: AppNavRail(
                index: _navIndex,
                showConnectedBadge: isConnected,
                onTap: _selectTab,
              ),
            ),
          Expanded(
            // без ключа PageView пересоздаётся при повороте вместе с состоянием вкладок
            key: const ValueKey('home-pages'),
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: expanded && railAtLeft,
              removeRight: expanded && !railAtLeft,
              child: PageView(
                controller: _pageCtrl,
                physics: const ClampingScrollPhysics(),
                dragStartBehavior: DragStartBehavior.down,
                allowImplicitScrolling: true,
                onPageChanged: _onPageSettled,
                children: [
                  for (final (i, tab) in const [
                    ServersTab(),
                    SubscriptionsTab(),
                    SettingsTab(),
                  ].indexed)
                    _HomeTabPage(
                      index: i,
                      onScreen: _onScreen & (1 << i) != 0,
                      child: tab,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: expanded
          ? null
          : HalloweenIconScope(
              child: AppBottomNav(
                index: _navIndex,
                showConnectedBadge: isConnected,
                onTap: _selectTab,
              ),
            ),
    );
  }
}

class _HomeTabPage extends ConsumerStatefulWidget {
  final int index;
  final bool onScreen;
  final Widget child;
  const _HomeTabPage({
    required this.index,
    required this.onScreen,
    required this.child,
  });

  @override
  ConsumerState<_HomeTabPage> createState() => _HomeTabPageState();
}

class _HomeTabPageState extends ConsumerState<_HomeTabPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // иначе стрелка пульта уводит фокус на соседнюю вкладку за краем экрана
    final current = ref.watch(homeTabIndexProvider) == widget.index;
    return TickerMode(
      enabled: widget.onScreen,
      child: ExcludeFocus(
        excluding: !current,
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}
