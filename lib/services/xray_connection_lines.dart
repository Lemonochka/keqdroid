import 'dart:collection';

import 'connections_service.dart';

// мимо фильтра уровня: при Warning в видимом журнале нет Info-строк, а правило, домен и закрытие xray пишет только ими
class XrayConnectionLines {
  static const _maxChars = 64 * 1024;

  final _lines = ListQueue<String>();
  var _chars = 0;

  void add(String line) {
    if (!XrayAccessLogParser.isConnectionLine(line)) return;
    _lines.addLast(line);
    _chars += line.length + 1;
    while (_chars > _maxChars) {
      _chars -= _lines.removeFirst().length + 1;
    }
  }

  String get text => _lines.join('\n');

  void clear() {
    _lines.clear();
    _chars = 0;
  }
}
