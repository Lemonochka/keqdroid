import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../core/app_logger.dart';
import '../models/traffic_split.dart';

// файлом: prefs переписывают весь блоб со списками серверов на каждый такт
class TrafficSplitStore {
  TrafficSplitStore._();

  static const _fileName = 'traffic_split.json';

  static String sessionKey({required int port, required String secret}) =>
      '$port:${sha256.convert(utf8.encode(secret)).toString().substring(0, 16)}';

  // по очереди: периодическая запись и запись при уходе в фон делят один временный файл
  static Future<void> _chain = Future.value();

  @visibleForTesting
  static String? directoryOverride;

  static Future<File?> _file() async {
    try {
      final override = directoryOverride;
      final dir = override != null
          ? Directory(override)
          : await getApplicationSupportDirectory();
      return File('${dir.path}${Platform.pathSeparator}$_fileName');
    } catch (_) {
      return null;
    }
  }

  static Future<TrafficSplitState?> load() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return null;
      return TrafficSplitState.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(TrafficSplitState state) {
    final run = _chain.then((_) => _write(state));
    _chain = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  // через временный файл: процесс убивают в любой момент записи
  static Future<void> _write(TrafficSplitState state) async {
    try {
      final file = await _file();
      if (file == null) return;
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(state.toJson()), flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      AppLogger.instance.warn('Traffic split state not saved', error: e);
    }
  }
}
