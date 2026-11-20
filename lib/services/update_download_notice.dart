import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../platform/vpn_native_bridge.dart';

// Установщик из фона Android молча не открывает (запрет с Android 10, VPN не исключение), а плагин отвечает done:
// окно закрывалось, и пользователь качал ту же версию снова. Поэтому установщик ждёт, пока приложение вернётся
class UpdateDownloadNotice {
  UpdateDownloadNotice(
    this._l10n,
    this._version, {
    @visibleForTesting DateTime Function() now = DateTime.now,
  }) : _now = now;

  final AppLocalizations _l10n;
  final String _version;
  final DateTime Function() _now;

  // у NotificationManagerService предел частоты на пакет, DEFAULT_MAX_NOTIFICATION_ENQUEUE_RATE = 5
  static const _progressGap = Duration(milliseconds: 500);

  @visibleForTesting
  static bool? debugSupported;

  static bool get supported => debugSupported ?? Platform.isAndroid;

  int _percent = -1;
  DateTime? _sentAt;
  bool _over = false;

  Future<void> started() => _call('startUpdateDownload', {
    'channel': _l10n.updateNoticeProgressChannel,
    'title': _l10n.updateNoticeDownloading(_version),
  });

  void progress(double fraction) {
    if (_over) return;
    final percent = (fraction.clamp(0, 1) * 100).toInt();
    if (percent == _percent) return;
    final now = _now();
    final sentAt = _sentAt;
    if (sentAt != null && now.difference(sentAt) < _progressGap) return;
    _percent = percent;
    _sentAt = now;
    unawaited(_call('updateDownloadProgress', {'percent': percent}));
  }

  Future<void> downloaded() async {
    _over = true;
    await _call('stopUpdateDownload');
    if (_inForeground) return;
    await _show(_l10n.updateNoticeReady(_version), _l10n.updateNoticeReadyHint);
    await _untilForeground();
    await _call('cancelUpdateNotice');
  }

  Future<void> failed() async {
    if (_over) return;
    _over = true;
    await _call('stopUpdateDownload');
    if (_inForeground) return;
    await _show(_l10n.updateNoticeFailed, _l10n.updateNoticeFailedHint);
    unawaited(_untilForeground().then((_) => _call('cancelUpdateNotice')));
  }

  bool get _inForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  Future<void> _untilForeground() {
    if (_inForeground) return Future.value();
    final back = Completer<void>();
    late final AppLifecycleListener listener;
    listener = AppLifecycleListener(
      onResume: () {
        listener.dispose();
        back.complete();
      },
    );
    return back.future;
  }

  Future<void> _show(String title, String text) => _call('showUpdateNotice', {
    'channel': _l10n.updateNoticeResultChannel,
    'title': title,
    'text': text,
  });

  // без уведомления загрузка всё равно идёт, ронять её из-за шторки нельзя
  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    try {
      await VpnNativeBridge.channel.invokeMethod<void>(method, args);
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}
