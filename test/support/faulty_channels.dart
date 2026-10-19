import 'dart:async';

import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';

// 링크 한쪽 채널을 감싸 실패를 결정적으로 만드는 테스트 채널: 송신이 던지게 하거나, 종료(sink.close())를 붙잡거나,
// 쓰인 프레임마다 훅을 검. 아무것도 안 켜면 그대로 통과
class FaultyChannel extends StreamChannelMixin<dynamic> {
  FaultyChannel(this._inner);

  final StreamChannel<dynamic> _inner;

  // true면 sink.add가 던짐: 링크의 송신은 "미전달(false)"로 끝나고 링크는 스스로 닫힘
  bool failAdds = false;

  // 세팅하면 sink.close()가 이 completer가 끝날 때까지
  // 안 끝남: 링크의 종료를 소켓 종료 대기(최대 2초) 구간에 붙잡아
  // 둠
  // (그 사이 링크는 isClosed지만 onClosed 정리는 아직 안 돎)
  Completer<void>? closeGate;

  bool closeStarted = false;

  // sink.add가 성공할 때마다 (지금까지 성공 횟수)로 불림
  void Function(int adds)? onAdd;
  void Function()? beforeAdd;
  int adds = 0;

  @override
  Stream<dynamic> get stream => _inner.stream;

  @override
  late final StreamSink<dynamic> sink = _FaultySink(this);
}

class _FaultySink implements StreamSink<dynamic> {
  _FaultySink(this._channel);

  final FaultyChannel _channel;
  StreamSink<dynamic> get _real => _channel._inner.sink;

  @override
  void add(dynamic event) {
    _channel.beforeAdd?.call();
    if (_channel.failAdds) throw StateError('sink.add failed (test)');
    _real.add(event);
    _channel.onAdd?.call(++_channel.adds);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _real.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<dynamic> stream) => _real.addStream(stream);

  @override
  Future<void> close() {
    _channel.closeStarted = true;
    final gate = _channel.closeGate;
    return gate == null
        ? _real.close()
        : gate.future.then((_) => _real.close());
  }

  @override
  Future<void> get done => _real.done;
}

// TransferRig.create에 꽂는 결함 주입 묶음: 링크마다 감싼
// 채널과 레지스트리가 만든 세션을 만들어진 순서(= 멤버 순서)대로 모아 둠
class RigFaults {
  final List<FaultyChannel> hostChannels = <FaultyChannel>[];
  final List<FaultyChannel> memberChannels = <FaultyChannel>[];
  final SessionLog sessions = SessionLog();

  StreamChannel<dynamic> wrapHost(int index, StreamChannel<dynamic> channel) =>
      _track(hostChannels, channel);

  StreamChannel<dynamic> wrapMember(
    int index,
    StreamChannel<dynamic> channel,
  ) => _track(memberChannels, channel);

  static FaultyChannel _track(
    List<FaultyChannel> into,
    StreamChannel<dynamic> channel,
  ) {
    final wrapped = FaultyChannel(channel);
    into.add(wrapped);
    return wrapped;
  }
}

// 레지스트리가 만드는 세션을 순서대로 모음: 링크의 봉인 워터마크를 올려서
// 그 링크의 다음 송신이 (링크가 열려 있는 채) 봉인에서 던지게 함
class SessionLog {
  final List<CryptoSession> sessions = <CryptoSession>[];

  void attach(LinkRegistry registry) {
    registry.debugCreateSession = () async {
      final session = await CryptoEngine().createSession();
      sessions.add(session);
      return session;
    };
  }

  // index번째로 만들어진 세션의 seal 워터마크를 올림: 그 세션을 쓰는 링크가
  // 아직 안 쓴 seq로 봉인하면 "이미 씀"으로 거부(SecurityException)돼서
  // 열린 링크에서 봉인 예외가 남
  Future<void> poison(int index) =>
      sessions[index].seal(<String, dynamic>{'k': 'typing'}, seq: 1 << 40);
}
