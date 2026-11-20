import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Ядро без ядра: тест сам решает, когда оно пишет в трубу, на какой сигнал
// выходит и выходит ли по закрытому stdin, как xray с нашим патчем.
class FakeCoreProcess implements Process {
  FakeCoreProcess({
    this.exitOnStdinClose = false,
    Set<ProcessSignal> exitOn = const {
      ProcessSignal.sigterm,
      ProcessSignal.sigkill,
    },
  }) : _exitOn = exitOn {
    stdin = IOSink(_StdinTarget(this));
  }

  final bool exitOnStdinClose;
  final Set<ProcessSignal> _exitOn;

  final signals = <ProcessSignal>[];
  bool stdinClosed = false;

  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _exitCode = Completer<int>();

  @override
  late final IOSink stdin;

  @override
  int get pid => 4242;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  bool get exited => _exitCode.isCompleted;

  void out(String text) => _stdout.add(utf8.encode(text));

  void err(String text) => _stderr.add(utf8.encode(text));

  void outBytes(List<int> bytes) => _stdout.add(bytes);

  void closeOutput() {
    if (!_stdout.isClosed) unawaited(_stdout.close());
    if (!_stderr.isClosed) unawaited(_stderr.close());
  }

  void exit(int code) {
    closeOutput();
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (_exitOn.contains(signal)) {
      exit(signal == ProcessSignal.sigkill ? -9 : -15);
    }
    return true;
  }
}

class _StdinTarget implements StreamConsumer<List<int>> {
  _StdinTarget(this._process);

  final FakeCoreProcess _process;

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() async {
    _process.stdinClosed = true;
    if (_process.exitOnStdinClose) _process.exit(0);
  }
}
