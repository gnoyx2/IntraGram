import 'dart:convert';
import 'dart:typed_data';

import 'package:intragram/core/constants.dart';
import 'package:intragram/core/network_guard.dart' show NetworkGuard;
import 'package:intragram/network/peer_auth.dart' show isSmallOrderKey;

// WebSocket 위 두 겹 프레임. 바깥(outer)은 평문 JSON: 핸드셰이크(hello/auth/web_hello), 암호 봉투(enc), 브라우저 게스트용 평문(plain).
// 안쪽(inner)이 채팅 내용: 앱끼리는 ChaCha20-Poly1305로 봉인해 enc 안에, 게스트는 plain 안에 담음. 파일 바이트는 HTTP로 감 (file_*는 협상용)

part 'protocol/inbound_outer.dart';
part 'protocol/inbound_inner.dart';
part 'protocol/inbound_file.dart';
part 'protocol/parse_inner.dart';
part 'protocol/validation.dart';
part 'protocol/inner_frames.dart';

// 인원수만으로 제목을 만드는 순수 함수라 호스트·멤버가 각자 같은 값을 뽑음 (count만 보내면 됨)
String roomTitle(int memberCount) =>
    memberCount <= 2 ? 'Room' : 'Room · $memberCount people';

class OuterFrame {
  const OuterFrame._();

  // identityKeyB64는 신원 공개키(peerId는 그 해시). 다이얼러는 임시키 대신 커밋만, 리스너는 임시키와 서명을 실음 (서명 대상은 peer_auth.dart)
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

  // 다이얼러가 리스너 hello를 받은 뒤 보내는 임시키 공개 + 신원 증명. 리스너는 임시키가 커밋과 맞고 서명이 통해야 키 합의도 peerId도 믿음
  static String auth({
    required String publicKeyB64,
    required String signatureB64,
  }) => jsonEncode(<String, dynamic>{
    't': 'auth',
    'pub': publicKeyB64,
    'sig': signatureB64,
  });

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
