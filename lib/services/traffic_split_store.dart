import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../models/traffic_split.dart';

/// Счёт разбивки на диске: он переживает то, чего не переживает Dart-изолят.
///
/// Нужен из-за Android: ядро там живёт своим процессом, и закрытое приложение
/// туннель не роняет. Пользователь смахнул приложение из недавних, вернулся
/// через час — общий чип показывает объём за весь час (его цифру ведёт
/// нативный сервис), а разбивка начиналась с нуля, потому что считал её
/// умерший вместе с движком трекер.
///
/// Файлом, а не `SharedPreferences`: запись идёт раз в несколько секунд всю
/// сессию, а prefs переписывают на каждое изменение весь свой блоб — вместе со
/// списками серверов и подписок, то есть сотнями килобайт на каждый такт.
class TrafficSplitStore {
  TrafficSplitStore._();

  static const _fileName = 'traffic_split.json';

  /// Метка сессии ядра.
  ///
  /// Порт и токен ядро получает на каждую сессию свои ([MihomoApiSession]), и
  /// пара переживает пересоздание движка — натив достаёт её из конфига, по
  /// которому ядро работает. Токен кладём в файл отпечатком: в открытом виде он
  /// уже лежит в конфиге ядра, второй копии на диске незачем.
  static String sessionKey({required int port, required String secret}) =>
      '$port:${sha256.convert(utf8.encode(secret)).toString().substring(0, 16)}';

  /// Записи выполняются строго по очереди: периодическая и внеочередная (уход
  /// в фон) иначе схлестнулись бы на одном временном файле.
  static Future<void> _chain = Future.value();

  /// Каталог для тестов: path_provider в них не отвечает.
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
      // path_provider не ответил — счёт просто не переживёт закрытия.
      return null;
    }
  }

  /// Счёт прошлого запуска. `null` — записи нет или она нечитаема.
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

  /// Пишем через временный файл с переименованием.
  ///
  /// Процесс убивают ровно в том случае, ради которого файл и заведён, — то
  /// есть в любой момент записи. Прямая запись оставила бы обрезанный JSON, и
  /// счёт всё равно начался бы с нуля.
  static Future<void> _write(TrafficSplitState state) async {
    try {
      final file = await _file();
      if (file == null) return;
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(state.toJson()), flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // Диск полон, каталог недоступен — на подключение это не влияет, а
      // счётчик в худшем случае начнётся заново.
    }
  }
}
