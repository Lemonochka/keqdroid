import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../core/app_logger.dart';
import '../core/connections_poll_stats.dart';
import '../tunnel/linux_tunnel_backend.dart';
import '../tunnel/windows_tunnel_backend.dart';

class MemoryWatch {
  MemoryWatch._();

  static final instance = MemoryWatch._();

  static const _channel = MethodChannel('keqdroid_vpn_channel');

  final _schedule = MemoryWatchSchedule();
  Timer? _timer;

  void start() {
    if (_timer != null || !(Platform.isWindows || Platform.isLinux)) return;
    _timer = Timer.periodic(MemoryWatchSchedule.beat, (_) => _onBeat());
    unawaited(_snapshot('start'));
  }

  void _onBeat() {
    final beat = _schedule.onBeat(DateTime.now());
    final slept = beat.slept;
    if (slept != null) {
      AppLogger.instance.info(
        'the system was asleep or the app was frozen for ~${slept.inMinutes} min',
      );
    }
    final reason = beat.reason;
    if (reason != null) unawaited(_snapshot(reason));
  }

  Future<void> _snapshot(String reason) async {
    try {
      final sample = await _collect();
      final alarm = _schedule.onSize(sample.size);
      final line = 'memory [$reason]: ${sample.describe()}';
      if (alarm == null) {
        AppLogger.instance.info(line);
      } else {
        AppLogger.instance.warn('$line; $alarm');
      }
    } catch (e) {
      AppLogger.instance.debug('memory snapshot failed', error: e);
    }
  }

  Future<MemorySample> _collect() async {
    final images = PaintingBinding.instance.imageCache;
    final common = (
      rss: ProcessInfo.currentRss,
      peakRss: ProcessInfo.maxRss,
      liveImages: images.liveImageCount,
      imageBytes: images.currentSizeBytes,
      polls: ConnectionsPollStats.instance.takeSummary(),
    );
    if (Platform.isWindows) {
      final pids = WindowsTunnelBackend.activeInstance?.activeCorePids ?? const {};
      final native = await _channel.invokeMapMethod<String, Object?>(
        'getProcessResources',
        {'cores': pids},
      );
      final self = (native?['self'] as Map?)?.cast<String, Object?>() ?? const {};
      final cores = (native?['cores'] as Map?)?.cast<String, Object?>() ?? const {};
      return MemorySample(
        rss: common.rss,
        peakRss: common.peakRss,
        privateBytes: self['ok'] == true ? self['privateBytes'] as int? : null,
        threads: self['threads'] as int?,
        handles: self['handles'] as int?,
        gdiObjects: self['gdiObjects'] as int?,
        userObjects: self['userObjects'] as int?,
        liveImages: common.liveImages,
        imageBytes: common.imageBytes,
        polls: common.polls,
        cores: {
          for (final entry in cores.entries)
            if (entry.value case final Map core when core['ok'] == true)
              entry.key: core['privateBytes'] as int,
        },
      );
    }
    final status = _procStatus('self');
    final pids = LinuxTunnelBackend.activeInstance?.activeCorePids ?? const {};
    return MemorySample(
      rss: common.rss,
      peakRss: common.peakRss,
      threads: status['Threads'],
      handles: _openFiles(),
      liveImages: common.liveImages,
      imageBytes: common.imageBytes,
      polls: common.polls,
      cores: {
        for (final entry in pids.entries)
          entry.key: ?_procStatus('${entry.value}')['VmRSS'],
      },
    );
  }

  static Map<String, int> _procStatus(String pid) {
    try {
      final out = <String, int>{};
      for (final line in File('/proc/$pid/status').readAsLinesSync()) {
        final match = RegExp(r'^(\w+):\s+(\d+)(\s+kB)?').firstMatch(line);
        if (match == null) continue;
        final value = int.parse(match.group(2)!);
        out[match.group(1)!] = match.group(3) == null ? value : value * 1024;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  static int? _openFiles() {
    try {
      return Directory('/proc/self/fd').listSync().length;
    } catch (_) {
      return null;
    }
  }
}

class MemoryWatchSchedule {
  static const beat = Duration(minutes: 1);
  static const periodBeats = 10;

  static const sleepGap = Duration(minutes: 3);

  static const growthAlarm = 256 * 1024 * 1024;

  static const growthContinues = 32 * 1024 * 1024;

  static const maxFastBeats = 30;

  static const firstThreshold = 1024 * 1024 * 1024;

  DateTime? _lastBeat;
  int _beatsSinceSnapshot = 0;
  int? _beatsSinceWake;
  int _fastLeft = 0;
  int? _lastSize;
  int _nextThreshold = firstThreshold;

  ({String? reason, Duration? slept}) onBeat(DateTime now) {
    final last = _lastBeat;
    _lastBeat = now;
    _beatsSinceSnapshot++;

    final gap = last == null ? Duration.zero : now.difference(last);
    if (gap >= sleepGap) {
      _beatsSinceWake = 0;
      return (reason: _taken('after sleep'), slept: gap);
    }

    final sinceWake = _beatsSinceWake;
    if (sinceWake != null) {
      final minutes = sinceWake + 1;
      _beatsSinceWake = minutes >= 5 ? null : minutes;
      if (minutes == 1 || minutes == 5) {
        return (reason: _taken('$minutes min after sleep'), slept: null);
      }
    }
    if (_fastLeft > 0) {
      _fastLeft--;
      return (reason: _taken('growing'), slept: null);
    }
    if (_beatsSinceSnapshot >= periodBeats) {
      return (reason: _taken('periodic'), slept: null);
    }
    return (reason: null, slept: null);
  }

  String _taken(String reason) {
    _beatsSinceSnapshot = 0;
    return reason;
  }

  String? onSize(int bytes) {
    final previous = _lastSize;
    _lastSize = bytes;
    final warnings = <String>[];
    if (bytes >= _nextThreshold) {
      while (bytes >= _nextThreshold) {
        _nextThreshold *= 2;
      }
      warnings.add('now above ${mb(_nextThreshold ~/ 2)}');
    }
    if (previous != null) {
      final delta = bytes - previous;
      if (delta >= growthAlarm) {
        _fastLeft = maxFastBeats;
        warnings.add('grew by ${mb(delta)} since last time');
      } else if (_fastLeft > 0 && delta < growthContinues) {
        _fastLeft = 0;
      }
    }
    return warnings.isEmpty ? null : warnings.join(', ');
  }
}

class MemorySample {
  const MemorySample({
    required this.rss,
    required this.peakRss,
    this.privateBytes,
    this.threads,
    this.handles,
    this.gdiObjects,
    this.userObjects,
    this.liveImages = 0,
    this.imageBytes = 0,
    this.polls = '',
    this.cores = const {},
  });

  final int rss;
  final int peakRss;

  final int? privateBytes;
  final int? threads;

  final int? handles;
  final int? gdiObjects;
  final int? userObjects;
  final int liveImages;
  final int imageBytes;
  final String polls;

  final Map<String, int> cores;

  int get size => privateBytes ?? rss;

  String describe() {
    final parts = <String>[
      [
        if (privateBytes != null) 'private ${mb(privateBytes!)}',
        'resident ${mb(rss)} (peak ${mb(peakRss)})',
        if (threads != null) 'threads $threads',
        if (handles != null) 'handles $handles',
        if (gdiObjects != null) 'gdi $gdiObjects',
        if (userObjects != null) 'user $userObjects',
      ].join(', '),
      'images $liveImages live, ${mb(imageBytes)} cached',
      if (polls.isNotEmpty) '/connections: $polls',
      cores.isEmpty
          ? 'no core running'
          : 'cores ${cores.entries.map((e) => '${e.key} ${mb(e.value)}').join(', ')}',
    ];
    return parts.join('; ');
  }
}

String mb(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';
