import 'dart:convert';
import 'dart:typed_data';

import 'package:intragram/audit/merkle.dart';
import 'package:intragram/audit/signing.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/protocol.dart'
    show wireBytes, wireId, wireInt;

const roomAuthorKeys = <String>{
  'roomIntegrityId',
  'authorPeerId',
  'authorPubKey',
  'authorCounter',
  'prevAuthorHash',
  'payloadCommitment',
  'payloadSalt',
  'authorSig',
};

// 서명이 바인딩하는 메시지 페이로드임. 표시 이름(from)은 중계 호스트가 지정하는 값이므로 제외하며 작성자는 peerId로만 검증함
String roomPayloadCommitment(
  Map<String, dynamic> wire, {
  required String salt,
}) => base64.encode(
  sha256Bytes(
    utf8.encode(
      jsonEncode([
        'intragram/room-payload/v2',
        salt,
        wire['id'],
        wire['text'],
        wire['ttl'] ?? 0,
        wire['ts'] ?? 0,
        wire['re'] ?? '',
      ]),
    ),
  ),
);

// 그룹 방 작성자 서명 봉투. 방 범위(roomId)는 호스트가 고른 무작위 공유 값이라 로컬 대화 id·링크 seq를 원장 번호로 안 씀.
// 호스트 peerId도 서명에 넣음 (wire엔 안 실음, 각자 인증된 링크로 아는 호스트로 맞춰 봄): 같은 범위 값을 쓰는
// 다른 호스트 방으로 옮겨 재생 못 함
final class RoomAuthorEvent {
  RoomAuthorEvent({
    required this.roomId,
    required this.hostPeerId,
    required this.peerId,
    required List<int> publicKey,
    required this.counter,
    required this.previousHash,
    required this.payloadCommitment,
    required this.payloadSalt,
    required List<int> signature,
  }) : publicKey = Uint8List.fromList(publicKey).asUnmodifiableView(),
       signature = Uint8List.fromList(signature).asUnmodifiableView();

  final String roomId;
  final String hostPeerId;
  final String peerId;
  final Uint8List publicKey;
  final int counter;
  final String previousHash;
  final String payloadCommitment;
  final String payloadSalt;
  final Uint8List signature;

  Uint8List get signedBytes => utf8.encode(
    jsonEncode([
      'intragram/room-author/v2',
      roomId,
      hostPeerId,
      peerId,
      base64.encode(publicKey),
      counter,
      previousHash,
      payloadCommitment,
      payloadSalt,
    ]),
  );

  String get hash => base64.encode(sha256Bytes([...signedBytes, ...signature]));

  Future<bool> verify(Map<String, dynamic> payload) async =>
      peerIdOfKey(publicKey) == peerId &&
      payloadCommitment == roomPayloadCommitment(payload, salt: payloadSalt) &&
      await verifyEd25519(
        message: signedBytes,
        signature: signature,
        key: publicKey,
      );

  Map<String, dynamic> toWire() => {
    'roomIntegrityId': roomId,
    'authorPeerId': peerId,
    'authorPubKey': base64.encode(publicKey),
    'authorCounter': counter,
    'prevAuthorHash': previousHash,
    'payloadCommitment': payloadCommitment,
    'payloadSalt': payloadSalt,
    'authorSig': base64.encode(signature),
  };

  static Future<RoomAuthorEvent> sign(
    AppIdentity identity, {
    required String roomId,
    required String hostPeerId,
    required int counter,
    required String previousHash,
    required Map<String, dynamic> payload,
  }) async {
    final salt = base64.encode(randomBytes(32));
    final event = RoomAuthorEvent(
      roomId: roomId,
      hostPeerId: hostPeerId,
      peerId: identity.peerId,
      publicKey: identity.publicKey!,
      counter: counter,
      previousHash: previousHash,
      payloadCommitment: roomPayloadCommitment(payload, salt: salt),
      payloadSalt: salt,
      signature: const [],
    );
    return RoomAuthorEvent(
      roomId: roomId,
      hostPeerId: hostPeerId,
      peerId: event.peerId,
      publicKey: event.publicKey,
      counter: counter,
      previousHash: previousHash,
      payloadCommitment: event.payloadCommitment,
      payloadSalt: event.payloadSalt,
      signature: await identity.sign(event.signedBytes),
    );
  }

  static RoomAuthorEvent? fromWire(
    Map<String, dynamic> wire, {
    required String hostPeerId,
  }) {
    final room = wireId(wire['roomIntegrityId']);
    final peer = wireId(wire['authorPeerId']);
    final key = wireBytes(wire['authorPubKey'], length: 32);
    final counter = wireInt(
      wire['authorCounter'],
      min: 1,
      max: 9007199254740991,
    );
    final previous = wireBytes(wire['prevAuthorHash'], length: 32);
    final payload = wireBytes(wire['payloadCommitment'], length: 32);
    final salt = wireBytes(wire['payloadSalt'], length: 32);
    final signature = wireBytes(wire['authorSig'], length: 64);
    if (room == null ||
        peer == null ||
        key == null ||
        counter == null ||
        previous == null ||
        payload == null ||
        salt == null ||
        signature == null) {
      return null;
    }
    return RoomAuthorEvent(
      roomId: room,
      hostPeerId: hostPeerId,
      peerId: peer,
      publicKey: key,
      counter: counter,
      previousHash: base64.encode(previous),
      payloadCommitment: base64.encode(payload),
      payloadSalt: base64.encode(salt),
      signature: signature,
    );
  }
}
