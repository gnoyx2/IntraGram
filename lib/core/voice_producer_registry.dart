import 'dart:async';

// 활성 음성 녹음/재생 producer의 정지 콜백 모음. 패닉이 store를 소각하기 전에 전부 멈추게 함
// 위젯이 일반 StatefulWidget이라 ref가 없고, 바꾸면 리빌드 범위 등 부작용이 생겨서
// provider 대신 전역 싱글턴으로 둠
class VoiceProducerRegistry {
  VoiceProducerRegistry._();
  static final VoiceProducerRegistry instance = VoiceProducerRegistry._();

  final Set<Future<void> Function()> _stoppers = <Future<void> Function()>{};

  // 패닉 중 true. 이 사이 새로 시작한 producer는 등록 대신 즉시 정지함
  // stopAll 스냅샷 뒤라 소각이 못 보는데, 두면 소각된 세션 위에서 녹음/재생이 되살아나 새 세션에 씀
  bool _admissionClosed = false;

  // 패닉 시퀀스가 첫 await 전에 동기적으로 호출. reopenAdmission까지 새 producer를 안 받음
  void closeAdmission() => _admissionClosed = true;

  void reopenAdmission() => _admissionClosed = false;

  void register(Future<void> Function() stop) {
    if (_admissionClosed) {
      unawaited(stop().catchError((Object _) {}));
      return;
    }
    _stoppers.add(stop);
  }

  void unregister(Future<void> Function() stop) => _stoppers.remove(stop);

  // 병렬로 멈춤. 하나가 실패해도(unmounted 위젯의 context 접근 등) 나머지는 끝까지 진행하고,
  // 전원이 끝난 뒤 하나의 예외로 알려서 패닉 시퀀스가 부분 실패로 기록하게 함
  Future<void> stopAll() async {
    final stoppers = _stoppers.toList();
    final failures = <Object>[];
    await Future.wait(
      stoppers.map((stop) async {
        try {
          await stop();
        } on Object catch (e) {
          failures.add(e);
        }
      }),
    );
    if (failures.isNotEmpty) {
      throw Exception(
        '${failures.length} voice producer(s) failed to stop: '
        '${failures.first}',
      );
    }
  }
}
