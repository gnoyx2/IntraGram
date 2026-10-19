import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/constants.dart';

import 'test_identities.dart';

AppIdentity identity() =>
    testIdentity('0', alias: 'portal-host-7', platform: 'Linux');

// 이 테스트 스위트 전체가 공유하는 고정 포털 토큰. 실제로는 매 세션 RAM 난수(ServerController.start 참고)지만
// 테스트는 registry.acceptInbound에 준 값과 Guest.hello가 실어 보내는 값만 서로 일치하면 됨
const String kTestPortalToken = 'test-portal-token';

// 브라우저 게스트 대역: 실제 WebSocket이 나르는 그대로 duplex 채널로 raw JSON 프레임을 주고받음
class Guest {
  Guest() {
    _controller.local.stream.listen(
      (m) => received.add(m as String),
      onDone: () => closed = true,
    );
  }

  final StreamChannelController<dynamic> _controller =
      StreamChannelController<dynamic>();
  final List<String> received = <String>[];
  // 호스트가 이 소켓을 닫았는지
  bool closed = false;

  StreamChannel<dynamic> get wire => _controller.foreign;

  void _send(Map<String, dynamic> frame) =>
      _controller.local.sink.add(jsonEncode(frame));

  void hello(String alias, {String? token = kTestPortalToken}) =>
      _send(<String, dynamic>{
        't': 'web_hello',
        'v': kProtocolVersion,
        'alias': alias,
        'tok': ?token,
      });

  void say(String id, String text) => _send(<String, dynamic>{
    't': 'plain',
    'd': <String, dynamic>{
      'k': 'msg',
      'id': id,
      'text': text,
      'ttl': 0,
      'ts': 1,
    },
  });

  void react(String id, String emoji) => _send(<String, dynamic>{
    't': 'plain',
    'd': <String, dynamic>{'k': 'react', 'id': id, 'emoji': emoji, 'on': true},
  });

  void burn(String id) => _send(<String, dynamic>{
    't': 'plain',
    'd': <String, dynamic>{'k': 'burn', 'id': id},
  });

  void screenshot() => _send(<String, dynamic>{
    't': 'plain',
    'd': <String, dynamic>{'k': 'screenshot'},
  });

  // v3 offer: at/md가 필수이고 주소(sh/sp)를 주면 pull이라 토큰도 함께 실음 (파서가 조합을 강제함)
  void offerFile(String id, {String? srcHost, int? srcPort}) =>
      _send(<String, dynamic>{
        't': 'plain',
        'd': <String, dynamic>{
          'k': 'file_offer',
          'id': id,
          'at': 'attempt-$id',
          'md': srcHost == null ? 'push' : 'pull',
          'name': 'x.bin',
          'size': 4,
          'sh': ?srcHost,
          'sp': ?srcPort,
          if (srcHost != null) 'tok': 'tok-$id',
        },
      });

  Future<void> disconnect() => _controller.local.sink.close();

  // 이 게스트가 받은 plain 봉투에서 꺼낸 inner 프레임
  List<Map<String, dynamic>> get inbound => received
      .map((s) => jsonDecode(s) as Map<String, dynamic>)
      .where((m) => m['t'] == 'plain')
      .map((m) => (m['d'] as Map).cast<String, dynamic>())
      .toList();

  List<Map<String, dynamic>> inboundOfKind(String kind) =>
      inbound.where((f) => f['k'] == kind).toList();
}
