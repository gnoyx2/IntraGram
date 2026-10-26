import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart' show DartSha256;

import 'package:intragram/core/constants.dart';

// 다이얼러가 첫 hello에 임시키 대신 싣는 커밋 (임시키는 auth에서 공개). 리스너가 이것만 보고 자기 키를 정해서
// 중간자가 상대 키를 보고 SAS 맞추는 키를 못 고름. 신원 키도 묶어서 커밋을 다른 신원으로 못 돌려씀
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

// 신원 증명 서명 바이트: peerId가 신원 공개키 해시라 그 개인키로 서명하면 peerId 주인임이 증명됨. 양쪽 신원 키(unknown-key-share 방지)와
// 역할 바이트(다이얼러 서명을 리스너 서명으로 못 씀)를 같이 묶음. 리스너는 다이얼러 임시키를 보기 전에 서명해서 그 자리에 커밋을 넣음
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

// 다이얼러는 리스너 임시키를 받은 뒤 자기 임시키를 공개하며 서명함
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

// 다 32바이트 고정이라 이어붙여도 모호하지 않음
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

// 위수 8 이하 점들의 y 좌표 (x 부호 무관): 0(위수 4), 1(위수 1), p-1(위수 2), 위수 8 두 개.
// test/peer_auth_weak_key_test.dart가 곡선 산술로 따로 검증함
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

// 작은 위수 점 키는 누구나 아무 메시지에 통하는 서명을 만들 수 있어서(항등원이면 R=[s]B, S=s) 그 peerId를 아무나 '증명'함.
// 그래서 신원 키로 안 받음. y가 p 이상인 비정규 인코딩도 있어 p로 줄여 비교
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
