part of '../voice_recorder.dart';

// 녹음 백엔드 seam: 프로덕션은 RecordVoiceCapture(record 패키지), 테스트는 페이크 주입
// PCM 버퍼의 보유/인코딩/해제는 구현이 소유하고 위젯은 완성된 WAV 바이트만 받음
// 임시 파일은 안 만듦
abstract interface class VoiceCapture {
  Future<bool> hasPermission();
  Future<void> start();

  Future<Uint8List?> finish();

  Future<void> cancel();

  Future<void> dispose();

  // 대략 -45(무음) ~ 0(최대) dBFS. 배너 파형 모션용
  Stream<double> get amplitudeStream;
}

// record의 startStream(PCM16 원시 샘플) 위의 얇은 wrapper. 인코더 없이 RAM 버퍼에 모았다가
// finish에서 44바이트 WAV 헤더만 붙임. 임시 파일이 아예 없음
class RecordVoiceCapture implements VoiceCapture {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _pcmSub;
  Completer<void>? _streamDone;

  // 120초 x 16kHz x 2바이트 = 정확한 PCM 상한. 위젯 _ticker가 이미 stop을 부르지만
  // 그 사이 늦게 온 조각까지 막는 방어적 상한
  // 이 크기로 미리 할당한 소유 버퍼에 직접 써서 SecureBytes.wipe가 항상 3-pass 0-fill을 하게 함
  // (BytesBuilder의 원본 chunk 참조가 안 남음)
  static const int _maxPcmBytes = kMaxVoiceNoteSeconds * kVoiceSampleRate * 2;
  final Uint8List _pcm = Uint8List(_maxPcmBytes);
  int _pcmLength = 0;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    _pcmLength = 0;
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
      (chunk) {
        final room = _maxPcmBytes - _pcmLength;
        if (room <= 0) return;
        final take = chunk.length <= room ? chunk.length : room;
        _pcm.setRange(_pcmLength, _pcmLength + take, chunk);
        _pcmLength += take;
      },
      onDone: streamDone.complete,
      onError: (Object _, StackTrace _) {
        if (!streamDone.isCompleted) streamDone.complete();
      },
      cancelOnError: true,
    );
  }

  @override
  Future<Uint8List?> finish() async {
    try {
      await _recorder.stop();
    } on Object {
      // 그래도 지금까지 모은 PCM은 씀
    }
    await _drainStream();
    if (_pcmLength == 0) return null;
    // _encodePcm16Wav가 헤더+데이터를 새 BytesBuilder로 합쳐 돌려주니(wav.dart)
    // 반환값은 _pcm과 무관한 복사본이라 바로 지워도 됨
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
      await _recorder.stop();
    } on Object {
      // 어차피 버릴 거라 무시
    }
    await _drainStream();
    _wipePcm();
  }

  void _wipePcm() {
    SecureBytes.wipe(_pcm);
    _pcmLength = 0;
  }

  // record의 계약: stop 이후에도 스트림 close 이벤트까지 기다려야 마지막 샘플이 포함됨
  // 그래서 실제로 기다리되, 플랫폼이 close를 안 보내는 이상 상황에서 finish/cancel이
  // 멎지 않게 짧은 상한을 둠
  Future<void> _drainStream() async {
    final done = _streamDone;
    if (done != null) {
      await done.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    }
    await _pcmSub?.cancel();
    _pcmSub = null;
  }

  @override
  Future<void> dispose() async {
    await _pcmSub?.cancel();
    _pcmSub = null;
    _wipePcm();
    await _recorder.dispose();
  }

  @override
  Stream<double> get amplitudeStream => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((a) => a.current);
}
