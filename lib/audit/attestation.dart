import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:intragram/audit/signing.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/protocol.dart'
    show wireBytes, wireId, wireInt;

export 'package:intragram/audit/signing.dart';

part 'attestation_wire.dart';

// 서명 증적 종류. 이름이 wire와 서명 바이트에 그대로 들어가서 바꾸면 이미 나간 증적이 안 풀림
enum AttestationKind {
  // 받는 쪽: 크기·무결성 검증과 커밋까지 끝낸 파일의 수신 영수증
  deliveryCommitted,
  // 메시지·전송에 소각 정책이 발동함
  burnTriggered,
  // 앱이 맡은 자원(토큰·조각 파일·RAM 바이트) 정리가 끝남
  cleanupCompleted,
  // 정리가 실패해서 끝났다고 확인 못 함
  cleanupFailed,
}

const String kAttestationDomain = 'intragram/attestation/v1';

// 정책·결과 이름: 화면이 접두로 번역함. 아무 글이나 못 실음
final RegExp _labelPattern = RegExp(r'^[a-z0-9][a-z0-9/:._-]{0,63}$');

String? _label(Object? value) =>
    value is String && _labelPattern.hasMatch(value) ? value : null;

// 서명 전 내용. 서명자 키·사건 id·nonce·시각은 서명할 때 채움
@immutable
final class AttestationDraft {
  AttestationDraft({
    required this.kind,
    required this.subjectId,
    required this.commitment,
    required this.policy,
    required this.outcome,
    this.attemptId,
    this.counterpartId,
    Uint8List? counterpartKey,
  }) : counterpartKey = counterpartKey == null
           ? null
           : immutableBytes(counterpartKey);

  final AttestationKind kind;

  // 사건 대상: 전송 id·메시지 id(양쪽 같음), 대화 정리면 이 기기 대화 id
  final String subjectId;

  // 전송이면 보내는 쪽이 고른 시도 id: 영수증을 그 시도에 못박는 챌린지 (옛 시도 영수증을 새 시도에 재생 못 함)
  final String? attemptId;

  // 상대 peerId(공개키 해시). 수신 영수증이면 보낸 사람
  final String? counterpartId;
  final Uint8List? counterpartKey;

  // 내용 커밋먼트 base64 (파일은 내용 SHA-256, 메시지는 salt 친 SHA-256)
  final String commitment;
  final String policy;
  final String outcome;
}

// Ed25519로 서명한 불변 증적. 본문은 안 담고 커밋먼트만 담아서 소각 뒤에도 남길 수 있음
@immutable
final class SignedAttestation {
  SignedAttestation({
    required this.kind,
    required this.eventId,
    required this.subjectId,
    required Uint8List signerKey,
    required this.commitment,
    required this.policy,
    required this.outcome,
    required this.nonce,
    required this.issuedAtMs,
    required Uint8List signature,
    this.attemptId,
    this.counterpartId,
    Uint8List? counterpartKey,
  }) : counterpartKey = counterpartKey == null
           ? null
           : immutableBytes(counterpartKey),
       signerKey = immutableBytes(signerKey),
       signature = immutableBytes(signature);

  final AttestationKind kind;
  final String eventId;
  final String subjectId;
  final String? attemptId;

  // 서명한 기기의 실행별 신원 공개키 (peerId는 이 키의 해시)
  final Uint8List signerKey;
  final String? counterpartId;
  final Uint8List? counterpartKey;
  final String commitment;
  final String policy;
  final String outcome;

  // 서명자가 고른 16바이트 난수 base64: 같은 내용의 증적도 서로 다른 사건으로 남음
  final String nonce;
  final int issuedAtMs;
  final Uint8List signature;

  String get signerPeerId => peerIdOfKey(signerKey);

  // 고정 순서 JSON 배열 (메시지 AAD와 같은 방식): 양쪽이 같은 바이트를 따로 만듦
  Uint8List get signedBytes => utf8.encode(
    jsonEncode(<Object>[
      kAttestationDomain,
      kind.name,
      eventId,
      subjectId,
      attemptId ?? '',
      base64.encode(signerKey),
      counterpartId ?? '',
      counterpartKey == null ? '' : base64.encode(counterpartKey!),
      commitment,
      policy,
      outcome,
      nonce,
      issuedAtMs,
    ]),
  );

  // Merkle 잎이 묶는 바이트: 서명까지 같이 넣어서 배치가 '이 서명'을 커밋함
  Uint8List get leafPayload =>
      Uint8List.fromList(<int>[...signedBytes, ...signature]);

  Future<bool> verify() => _counterpartMatches(counterpartId, counterpartKey)
      ? verifyEd25519(
          message: signedBytes,
          signature: signature,
          key: signerKey,
        )
      : Future<bool>.value(false);

  static Future<SignedAttestation> sign(
    AppIdentity identity,
    AttestationDraft draft, {
    DateTime? now,
  }) async {
    final key = identity.publicKey;
    if (key == null) throw StateError('this identity has no signing key');
    if (!_counterpartMatches(draft.counterpartId, draft.counterpartKey)) {
      throw ArgumentError('counterpart key must match its peerId');
    }
    final unsigned = SignedAttestation(
      kind: draft.kind,
      eventId: newId(),
      subjectId: draft.subjectId,
      attemptId: draft.attemptId,
      signerKey: Uint8List.fromList(key),
      counterpartId: draft.counterpartId,
      counterpartKey: draft.counterpartKey,
      commitment: draft.commitment,
      policy: draft.policy,
      outcome: draft.outcome,
      nonce: base64.encode(randomBytes(16)),
      issuedAtMs: (now ?? DateTime.now()).millisecondsSinceEpoch,
      signature: Uint8List(64),
    );
    return unsigned._withSignature(await identity.sign(unsigned.signedBytes));
  }

  SignedAttestation _withSignature(Uint8List sig) => SignedAttestation(
    kind: kind,
    eventId: eventId,
    subjectId: subjectId,
    attemptId: attemptId,
    signerKey: signerKey,
    counterpartId: counterpartId,
    counterpartKey: counterpartKey,
    commitment: commitment,
    policy: policy,
    outcome: outcome,
    nonce: nonce,
    issuedAtMs: issuedAtMs,
    signature: sig,
  );

  Map<String, dynamic> toWire() => <String, dynamic>{
    'domain': kAttestationDomain,
    'k': kind.name,
    'e': eventId,
    's': subjectId,
    'a': ?attemptId,
    'pk': base64.encode(signerKey),
    'cp': ?counterpartId,
    'ck': counterpartKey == null ? null : base64.encode(counterpartKey!),
    'c': commitment,
    'p': policy,
    'o': outcome,
    'n': nonce,
    't': issuedAtMs,
    'sg': base64.encode(signature),
  };

  // 엄격 파싱: 필드 하나라도 형식이 틀리면 null을 반환함 (기본값으로 정상 증적을 꾸며 내지 않음). 서명 검사는 verify가 따로 함
  static SignedAttestation? fromWire(Object? raw) => _attestationFromWire(raw);
}

// 중계 전 정규화: 아는 필드만 다시 써서 끼워 넣은 여분 키가 안 넘어감. 형식이 틀리면 null을 반환함 (그 필드만 버림)
Map<String, dynamic>? canonicalAttestationWire(Object? raw) =>
    SignedAttestation.fromWire(raw)?.toWire();
