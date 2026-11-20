// список процессов Windows отдаёт Discord.exe, а старая версия сохраняла discord.exe
library;

import '../models/app_info.dart';
import 'process_name_utils.dart';

String splitNameKey(String raw, {bool? windows}) =>
    normalizeProcessName(raw, windows: windows).toLowerCase();

// регистр пути снимаем только на Windows: на Linux /opt/App и /opt/app разные файлы
String splitPathKey(String raw, {bool? windows}) {
  final onWindows = windowsProcessRules(windows);
  final path = normalizeProcessPath(raw, windows: onWindows);
  return onWindows ? path.toLowerCase() : path;
}

bool _hasPath(AppInfo app) =>
    app.installPath != null && app.installPath!.isNotEmpty;

bool splitEntryMatches(String entry, AppInfo app, {bool? windows}) {
  if (entry.trim().isEmpty) return false;
  if (isProcessPathEntry(entry)) {
    return _hasPath(app) &&
        splitPathKey(entry, windows: windows) ==
            splitPathKey(app.installPath!, windows: windows);
  }
  return splitNameKey(entry, windows: windows) ==
      splitNameKey(app.packageName, windows: windows);
}

class SplitSelection {
  SplitSelection(Iterable<String> entries, {bool? windows})
    : _windows = windows {
    for (final entry in entries) {
      if (entry.trim().isEmpty) continue;
      if (isProcessPathEntry(entry)) {
        _paths.add(splitPathKey(entry, windows: windows));
      } else {
        _names.add(splitNameKey(entry, windows: windows));
      }
    }
  }

  final bool? _windows;
  final _paths = <String>{};
  final _names = <String>{};

  bool covers(AppInfo app) =>
      (_hasPath(app) &&
          _paths.contains(splitPathKey(app.installPath!, windows: _windows))) ||
      _names.contains(splitNameKey(app.packageName, windows: _windows));
}

AppInfo splitStubForEntry(String entry, {bool? windows}) {
  if (isProcessPathEntry(entry)) {
    final path = normalizeProcessPath(entry, windows: windows);
    final name = normalizeProcessName(path, windows: windows);
    return AppInfo(packageName: name, appName: name, installPath: path);
  }
  return AppInfo(
    packageName: normalizeProcessName(entry, windows: windows),
    appName: entry.trim(),
  );
}

List<AppInfo> dedupeSplitEntries(List<AppInfo> apps, {bool? windows}) {
  final withPath = <String>{};
  final namesWithPath = <String>{};
  for (final app in apps) {
    if (_hasPath(app)) {
      namesWithPath.add(splitNameKey(app.packageName, windows: windows));
    }
  }
  final pathless = <String>{};
  final out = <AppInfo>[];
  for (final app in apps) {
    final name = splitNameKey(app.packageName, windows: windows);
    if (name.isEmpty) continue;
    if (_hasPath(app)) {
      if (withPath.add(splitPathKey(app.installPath!, windows: windows))) {
        out.add(app);
      }
    } else if (!namesWithPath.contains(name) && pathless.add(name)) {
      out.add(app);
    }
  }
  return out;
}
