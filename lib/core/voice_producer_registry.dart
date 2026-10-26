import 'dart:async';

// 녹음·재생 중인 producer의 정지 콜백 모음: 패닉이 store를 태우기 전에 다 멈춤. 위젯이 ref 없는 StatefulWidget이라 provider 대신 전역 싱글턴
class VoiceProducerRegistry {
  VoiceProducerRegistry._();
  static final VoiceProducerRegistry instance = VoiceProducerRegistry._();

  final Set<Future<void> Function()> _stoppers = <Future<void> Function()>{};

  // 패닉 중엔 새 producer를 받지 않고 바로 멈춤 (stopAll 스냅샷 뒤라 소각이 못 보고, 두면 새 세션에서 녹음·재생이 되살아남)
  bool _admissionClosed = false;

  // 패닉이 첫 await 전에 동기로 부름
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

  // 병렬로 멈춤. 하나가 실패해도 나머지는 끝까지 하고, 다 끝난 뒤 예외 하나로 알려서 패닉이 부분 실패로 기록하게 함
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
