import 'dart:async';
import 'dart:io';

class AudioProcess implements Process {
  AudioProcess();

  factory AudioProcess.help({bool rawSupported = true}) {
    final process = AudioProcess();
    process.output.add((rawSupported ? '--raw' : '--format').codeUnits);
    unawaited(process.output.close());
    process._exit.complete(0);
    return process;
  }

  final output = StreamController<List<int>>();
  final _exit = Completer<int>();
  final inputBytes = <int>[];
  late final IOSink _input = IOSink(_AudioSink(inputBytes));
  bool killed = false;

  @override
  IOSink get stdin => _input;
  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 1;
  // 서버에 못 붙어 첫 소리 전에, 또는 도중에 스스로 끝난 도구 (PulseAudio·PipeWire 도구는 실패하면 1)
  void exitWith(int code) {
    if (_exit.isCompleted) return;
    _exit.complete(code);
    unawaited(output.close());
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exit.isCompleted) {
      _exit.complete(0);
      unawaited(output.close());
    }
    return true;
  }
}

class _AudioSink implements StreamConsumer<List<int>> {
  _AudioSink(this.bytes);
  final List<int> bytes;

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(bytes.addAll);
  @override
  Future<void> close() async {}
}
