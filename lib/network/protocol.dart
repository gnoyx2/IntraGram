import 'dart:convert';
import 'dart:typed_data';

import 'package:intragram/core/constants.dart';
import 'package:intragram/core/network_guard.dart' show NetworkGuard;

// WebSocket 위 두 프레임 레이어. Outer frame은 평문 JSON: 핸드셰이크(hello/auth/web_hello),
// 암호화 봉투(enc), 브라우저 게스트용 평문 래퍼(plain)
// Inner frame은 채팅 의미를 담음: 앱 피어끼리는 ChaCha20-Poly1305로 봉인돼 enc 안에,
// 브라우저 게스트는 plain 안에. 파일 벌크 바이트는 HTTP로 스트리밍 (inner file_*은 협상용)

part 'protocol/inbound_outer.dart';
part 'protocol/inbound_inner.dart';
part 'protocol/inbound_file.dart';
part 'protocol/parse_inner.dart';
part 'protocol/validation.dart';
part 'protocol/inner_frames.dart';

// 방 인원수만으로 표시 이름을 계산하는 순수 함수라 host/멤버가 로컬에서 같은
// 값을 뽑음 (room_join/room_state로 count만 보내면 됨)
String roomTitle(int memberCount) =>
    memberCount <= 2 ? 'Room' : 'Room · $memberCount people';

class OuterFrame {
  const OuterFrame._();

  // identityKeyB64는 신원 공개키(peerId는 그 해시). 다이얼러는 임시키 대신 커밋(commitmentB64)만,
  // 리스너는 임시키(publicKeyB64)와 신원 증명(signatureB64)을 실음 (서명 대상은 peer_auth.dart 참고)
  static String hello({
    required String peerId,
    required String alias,
    required String platform,
    required String identityKeyB64,
    String? publicKeyB64,
    String? commitmentB64,
    String? signatureB64,
    int? port,
  }) => jsonEncode(<String, dynamic>{
    't': 'hello',
    'v': kProtocolVersion,
    'peerId': peerId,
    'alias': alias,
    'platform': platform,
    'pub': ?publicKeyB64,
    'cmt': ?commitmentB64,
    'idk': identityKeyB64,
    'sig': ?signatureB64,
    'port': ?port,
  });

  // 다이얼러가 리스너의 hello를 받은 뒤 보내는 임시키 공개 + 신원 증명
  // 리스너는 임시키가 커밋과 맞고 서명이 통하기 전엔 키 합의도, 상대 peerId도 안 믿음
  static String auth({
    required String publicKeyB64,
    required String signatureB64,
  }) => jsonEncode(<String, dynamic>{
    't': 'auth',
    'pub': publicKeyB64,
    'sig': signatureB64,
  });

  static String webHello({required String alias}) => jsonEncode(
    <String, dynamic>{'t': 'web_hello', 'v': kProtocolVersion, 'alias': alias},
  );

  static String enc({
    required String nonceB64,
    required String cipherB64,
    required String macB64,
    required int seq,
  }) => jsonEncode(<String, dynamic>{
    't': 'enc',
    'n': nonceB64,
    'c': cipherB64,
    'm': macB64,
    'seq': seq,
  });

  static String plain(Map<String, dynamic> inner) =>
      jsonEncode(<String, dynamic>{'t': 'plain', 'd': inner});
}
