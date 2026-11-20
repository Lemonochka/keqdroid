import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// Тот же файл и формат, что у SharedPreferencesWindows 2.4.1, но тот писал весь файл синхронно в потоке
// интерфейса: 575 КБ стоили 5,7 мс в медиане и до 22 мс (замер 18.11.2026). Запись начинается сразу,
// не по таймеру: закрытие окна без трея гасит процесс мимо Dart
class WindowsPrefsStore extends SharedPreferencesStorePlatform {
  WindowsPrefsStore({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  static const fileName = 'shared_preferences.json';
  static const _prefix = 'flutter.';

  final Future<Directory> Function() _directory;
  Map<String, Object>? _cache;
  File? _file;
  Future<Map<String, Object>>? _loading;
  Future<void>? _writing;
  var _dirty = false;
  var _lastOk = true;

  static void register() =>
      SharedPreferencesStorePlatform.instance = WindowsPrefsStore();

  static Future<void> flushInstance() async {
    final store = SharedPreferencesStorePlatform.instance;
    if (store is WindowsPrefsStore) await store.flush();
  }

  Future<void> flush() async {
    await _loading;
    await _writing;
  }

  Future<Map<String, Object>> _read() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _loading ??= _load();
  }

  Future<Map<String, Object>> _load() async {
    final dir = await _directory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    _file = file;
    var prefs = <String, Object>{};
    if (file.existsSync()) {
      final text = file.readAsStringSync();
      if (text.isNotEmpty) {
        final data = json.decode(text);
        if (data is Map) prefs = data.cast<String, Object>();
      }
    }
    return _cache ??= prefs;
  }

  // при загруженном кэше изменение и запись ставятся синхронно: flush перед выходом их уже видит
  Future<bool> _mutate(void Function(Map<String, Object> prefs) change) {
    final cached = _cache;
    if (cached != null) {
      change(cached);
      return _save();
    }
    return _read().then((prefs) {
      change(prefs);
      return _save();
    });
  }

  Future<bool> _save() {
    _dirty = true;
    return (_writing ??= _drain()).then((_) => _lastOk);
  }

  Future<void> _drain() async {
    try {
      while (_dirty) {
        _dirty = false;
        final file = _file;
        final prefs = _cache;
        if (file == null || prefs == null) break;
        final text = json.encode(prefs);
        try {
          await file.parent.create(recursive: true);
          // прерванная запись оставляла файл из нулей, и старт падал до runApp (PrefsRecovery)
          final tmp = File('${file.path}.tmp');
          await tmp.writeAsString(text);
          try {
            await tmp.rename(file.path);
          } on FileSystemException {
            await file.writeAsString(text);
            await tmp.delete().catchError((_) => tmp);
          }
          _lastOk = true;
        } catch (_) {
          _lastOk = false;
        }
      }
    } finally {
      _writing = null;
    }
  }

  bool _matches(String key, PreferencesFilter filter) =>
      key.startsWith(filter.prefix) &&
      (filter.allowList?.contains(key) ?? true);

  @override
  Future<bool> clear() => clearWithParameters(
        ClearParameters(filter: PreferencesFilter(prefix: _prefix)),
      );

  @override
  Future<bool> clearWithPrefix(String prefix) => clearWithParameters(
        ClearParameters(filter: PreferencesFilter(prefix: prefix)),
      );

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      _mutate((prefs) =>
          prefs.removeWhere((key, _) => _matches(key, parameters.filter)));

  @override
  Future<Map<String, Object>> getAll() => getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: _prefix)),
      );

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) =>
      getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: prefix)),
      );

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final all = Map<String, Object>.from(await _read());
    all.removeWhere((key, _) => !_matches(key, parameters.filter));
    return all;
  }

  @override
  Future<bool> remove(String key) => _mutate((prefs) => prefs.remove(key));

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _mutate((prefs) => prefs[key] = value);
}
