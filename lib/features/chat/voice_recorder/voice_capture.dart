part of '../voice_recorder.dart';

// 녹음 백엔드 seam (프로덕션은 record 패키지, 테스트는 페이크). PCM 버퍼는 구현이 쥐고 지우며 위젯은 완성된 WAV만 받음. 임시 파일 없음
abstract interface class VoiceCapture {
  Future<bool> hasPermission();
  Future<void> start();

  Future<Uint8List?> finish();

  Future<void> cancel();

  Future<void> dispose();

  // 대략 -45(무음) ~ 0(최대) dBFS. 배너 파형 모션용. 녹음이 도중에 끊기면 오류 이벤트가 옴
  Stream<double> get amplitudeStream;
}

// record startStream(PCM16) 위의 얇은 래퍼: 인코더 없이 RAM에 모았다가 finish에서 WAV 헤더만 붙임.
// Linux는 record가 띄우는 parecord와 같은 인자의 도구를 직접 띄워서 일찍 끝나는지 보고 PipeWire로 바꿈
class RecordVoiceCapture implements VoiceCapture {
  RecordVoiceCapture({this.linuxStart});

  // 첫 PCM을 기다리는 상한: 그 전에 끝나면 시작 실패, 지나도 살아 있으면 녹음 중으로 봄
  static const Duration _firstPcmWait = Duration(seconds: 1);

  final ProcessStarter? linuxStart;
  Process? _linuxProcess;
  // 시작한 뒤 멈추기 전에 끝난 Linux 녹음. 다시 띄우면 빈틈이 생겨 잘린 녹음을 보내지 않고 오류로 알림
  Object? _linuxFailure;
  bool _stopping = false;
  final _linuxAmplitude = StreamController<double>.broadcast();
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<List<int>>? _pcmSub;
  Completer<void>? _streamDone;

  // 120초 × 16kHz × 2바이트 = 딱 PCM 상한 (위젯 _ticker가 먼저 멈추지만 늦게 온 조각까지 막음).
  // 미리 잡은 소유 버퍼에 바로 써서 wipe가 늘 전부 덮음
  static const int _maxPcmBytes = kMaxVoiceNoteSeconds * kVoiceSampleRate * 2;
  final Uint8List _pcm = Uint8List(_maxPcmBytes);
  int _pcmLength = 0;

  // 테스트(FLUTTER_TEST)는 호스트 OS와 상관없이 android로 보여서 Linux CI에서도 실제 도구를 안 띄움
  bool get _linux =>
      linuxStart != null || defaultTargetPlatform == TargetPlatform.linux;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    _pcmLength = 0;
    _stopping = false;
    _linuxFailure = null;
    if (_linux) return _startLinux(pulse: true);
    final streamDone = Completer<void>();
    _streamDone = streamDone;
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: kVoiceSampleRate,
        numChannels: 1,
      ),
    );
    _pcmSub = stream.listen(
      _take,
      onDone: streamDone.complete,
      onError: (Object _, StackTrace _) {
        if (!streamDone.isCompleted) streamDone.complete();
      },
      cancelOnError: true,
    );
  }

  Future<void> _startLinux({required bool pulse}) async {
    final audio = await startLinuxAudio(
      recording: true,
      sampleRate: kVoiceSampleRate,
      channels: 1,
      start: linuxStart,
      pulse: pulse,
    );
    final process = audio.process;
    _linuxProcess = process;
    drainAudioDiagnostics(process);
    final streamDone = Completer<void>();
    final firstPcm = Completer<bool>();
    _streamDone = streamDone;
    var capturing = false;
    void ended() {
      if (!streamDone.isCompleted) streamDone.complete();
      if (!capturing) {
        if (!firstPcm.isCompleted) firstPcm.complete(false);
        return;
      }
      if (_stopping || !identical(_linuxProcess, process)) return;
      final failure = ProcessException(
        audio.executable,
        const [],
        'recording ended before it was stopped',
      );
      _linuxFailure = failure;
      if (!_linuxAmplitude.isClosed) _linuxAmplitude.addError(failure);
    }

    _pcmSub = process.stdout.listen(
      (bytes) {
        if (!firstPcm.isCompleted) firstPcm.complete(true);
        _take(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
      },
      onDone: ended,
      onError: (Object _, StackTrace _) => ended(),
      cancelOnError: true,
    );
    capturing = await firstPcm.future.timeout(
      _firstPcmWait,
      onTimeout: () => true,
    );
    if (capturing) return;
    // 첫 PCM 전에 끝남(서버 없음 등): 끝난 스트림은 버리고, PulseAudio였을 때만 PipeWire로 한 번 다시 띄움
    process.kill();
    await _pcmSub?.cancel();
    _pcmSub = null;
    _linuxProcess = null;
    if (audio.pulse) return _startLinux(pulse: false);
    throw ProcessException(audio.executable, const [], 'no audio captured');
  }

  void _take(Uint8List chunk) {
    final room = _maxPcmBytes - _pcmLength;
    final take = chunk.length <= room ? chunk.length : room;
    if (take > 0) {
      _pcm.setRange(_pcmLength, _pcmLength + take, chunk);
      _pcmLength += take;
    }
    if (_linux && !_linuxAmplitude.isClosed) {
      var peak = 0;
      final samples = ByteData.sublistView(chunk);
      for (var at = 0; at + 1 < chunk.length; at += 2) {
        peak = math.max(peak, samples.getInt16(at, Endian.little).abs());
      }
      _linuxAmplitude.add(
        peak == 0 ? -160 : 20 * math.log(peak / 32768) / math.ln10,
      );
    }
    // 플러그인·도구가 넘긴 조각도 옮긴 뒤 덮음 (소유 버퍼 밖에 음성 사본을 안 남김)
    SecureBytes.wipe(chunk);
  }

  @override
  Future<Uint8List?> finish() async {
    try {
      await _stopRecorder();
    } on Object {
      // 그래도 지금까지 모은 PCM은 씀
    }
    await _drainStream();
    final failure = _linuxFailure;
    if (failure != null) {
      // 도중에 끊긴 녹음은 잘린 채로 보내지 않음 (호출부가 '저장하지 못함'을 알림)
      _wipePcm();
      throw failure;
    }
    if (_pcmLength == 0) return null;
    // _encodePcm16Wav는 새 버퍼에 합쳐 돌려줘서 _pcm은 바로 지워도 됨
    final wav = _encodePcm16Wav(
      Uint8List.sublistView(_pcm, 0, _pcmLength),
      sampleRate: kVoiceSampleRate,
    );
    _wipePcm();
    return wav;
  }

  @override
  Future<void> cancel() async {
    try {
      await _stopRecorder();
    } on Object {
      // 어차피 버릴 거라 무시
    }
    await _drainStream();
    _wipePcm();
  }

  // 사용자가 멈추는 것이므로 뒤따르는 스트림 종료는 실패도 폴백 대상도 아님
  Future<void> _stopRecorder() async {
    _stopping = true;
    final process = _linuxProcess;
    if (!_linux) {
      await _recorder.stop();
    } else if (process != null) {
      process.kill();
      await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
  }

  void _wipePcm() {
    SecureBytes.wipe(_pcm);
    _pcmLength = 0;
  }

  // record 계약: stop 뒤에도 스트림 close까지 기다려야 마지막 샘플이 들어옴. close가 안 오는 이상 상황에 대비해 2초 상한
  Future<void> _drainStream() async {
    final done = _streamDone;
    if (done != null) {
      await done.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    }
    await _pcmSub?.cancel();
    _pcmSub = null;
    _linuxProcess = null;
  }

  @override
  Future<void> dispose() async {
    if (_linuxProcess != null) await _stopRecorder();
    await _pcmSub?.cancel();
    _pcmSub = null;
    _linuxProcess = null;
    _wipePcm();
    await _linuxAmplitude.close();
    await _recorder.dispose();
  }

  @override
  Stream<double> get amplitudeStream => _linux
      ? _linuxAmplitude.stream
      : _recorder
            .onAmplitudeChanged(const Duration(milliseconds: 100))
            .map((a) => a.current);
}
