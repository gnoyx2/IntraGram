import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart' show DartSha256;

import 'package:intragram/core/constants.dart';

// 다이얼러가 첫 hello에 임시키 대신 싣는 커밋. 리스너는 이 값만 보고 자기 임시키를 정해야 해서
// 중간자가 상대 키를 본 뒤 6자리 SAS를 맞추는 키를 고를 수 없음 (임시키는 auth에서 공개)
// 신원 키도 묶어서 다른 신원으로 같은 커밋을 재사용하지 못하게 함
Uint8List ephemeralCommitment({
  required List<int> ephemeral,
  required List<int> identityKey,
}) {
  _require32(<List<int>>[ephemeral, identityKey]);
  return Uint8List.fromList(
    const DartSha256().hashSync(<int>[
      ...utf8.encode('intragram/commit/v$kProtocolVersion'),
      ...ephemeral,
      ...identityKey,
    ]).bytes,
  );
}

// 신원 증명에서 서명하는 바이트: peerId가 신원 공개키의 해시라서 그 개인키로 서명하면
// peerId를 실제로 가진 쪽임이 증명됨. 양쪽 신원 공개키(unknown-key-share 방지)와 역할 바이트
// (다이얼러 서명이 리스너 서명으로 통하지 않게)를 함께 서명함
// 리스너는 다이얼러 임시키를 보기 전에 서명하므로 그 자리에 다이얼러 커밋을 넣음
Uint8List listenerTranscript({
  required List<int> dialerCommitment,
  required List<int> listenerEphemeral,
  required List<int> dialerKey,
  required List<int> listenerKey,
}) => _transcript(0x4c, <List<int>>[
  dialerCommitment,
  listenerEphemeral,
  dialerKey,
  listenerKey,
]);

// 다이얼러는 리스너 임시키를 받은 뒤 공개하는 자기 임시키로 서명함
Uint8List dialerTranscript({
  required List<int> dialerEphemeral,
  required List<int> listenerEphemeral,
  required List<int> dialerKey,
  required List<int> listenerKey,
}) => _transcript(0x44, <List<int>>[
  dialerEphemeral,
  listenerEphemeral,
  dialerKey,
  listenerKey,
]);

// 모든 필드가 32바이트 고정 길이라 이어붙여도 모호하지 않음 (길이가 다르면 ArgumentError)
Uint8List _transcript(int role, List<List<int>> fields) {
  _require32(fields);
  return Uint8List.fromList(<int>[
    ...utf8.encode('intragram/auth/v$kProtocolVersion'),
    role, // 'D' / 'L'
    for (final field in fields) ...field,
  ]);
}

void _require32(List<List<int>> fields) {
  if (fields.any((field) => field.length != 32)) {
    throw ArgumentError('handshake fields must be 32 bytes each');
  }
}

// Ed25519 체 크기 p = 2^255 - 19
final BigInt _fieldPrime = (BigInt.one << 255) - BigInt.from(19);

// 위수 8 이하인 8개 점(작은 위수 점)의 y 좌표 (x 부호와 무관):
// 0(위수 4), 1(위수 1), p-1(위수 2), 위수 8인 두 값
// 값은 test/peer_auth_weak_key_test.dart가 곡선 산술로 독립 검증함
final Set<BigInt> _smallOrderYs = <BigInt>{
  BigInt.zero,
  BigInt.one,
  _fieldPrime - BigInt.one,
  BigInt.parse(
    '2707385501144840649318225287225658788936804267575313519463743609750303402022',
  ),
  BigInt.parse(
    '55188659117513257062467267217118295137698188065244968500265048394206261417927',
  ),
};

// 작은 위수 점 키는 아무나 임의 메시지에 유효한 서명을 만들 수 있어서(항등원이면
// R=[s]B, S=s) 그 해시인 peerId를 누구나 "증명"함
// 그래서 신원 키로 안 받음. y가 p 이상인 비정규 인코딩도 있어 p로 줄여서 비교
bool isSmallOrderKey(List<int> key) {
  var y = BigInt.zero;
  for (var i = 31; i >= 0; i--) {
    y = (y << 8) | BigInt.from(i == 31 ? key[i] & 0x7f : key[i]);
  }
  return _smallOrderYs.contains(y % _fieldPrime);
}

Future<bool> verifyAuth({
  required List<int> transcript,
  required List<int> signature,
  required List<int> signerKey,
}) => Ed25519().verify(
  transcript,
  signature: Signature(
    signature,
    publicKey: SimplePublicKey(signerKey, type: KeyPairType.ed25519),
  ),
);
