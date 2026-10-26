import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Ed25519;
import 'package:cryptography/dart.dart' show DartSha256;
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:meta/meta.dart';

import 'package:intragram/audit/signing.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/protocol.dart'
    show wireBytes, wireId, wireInt, wireText;

part 'org_auth/trust_bundle.dart';
part 'org_auth/presentation.dart';
part 'org_auth/status_book.dart';

// 오프라인 조직 자격: 발급기관이 '이 실행의 신원 공개키는 이 기관·부서·역할'이라고 서명한 짧은 위임 증명.
// 신원 키가 실행마다 바뀌어서 자격도 그 실행 키에만 묶이고(저장 안 함), hello 평문엔 절대 안 실림.
// 암호 링크가 선 뒤 org_cred 프레임으로만 오가고 SAS 확인(Conversation.verified)과는 따로 저장됨
const String kOrgCredentialDomain = 'intragram/org-credential/v1';

final RegExp _labelPattern = RegExp(r'^[a-z0-9][a-z0-9/:._-]{0,63}$');
final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
const int _kMaxWireInt = 9007199254740991;

@immutable
final class OrgCredential {
  OrgCredential({
    required this.id,
    required this.issuerId,
    required List<int> issuerKey,
    required List<int> subjectKey,
    required this.org,
    required this.dept,
    required this.role,
    required this.policy,
    required this.issuedAtMs,
    required this.expiresAtMs,
    required this.snapshot,
    required List<int> signature,
  }) : issuerKey = Uint8List.fromList(issuerKey).asUnmodifiableView(),
       subjectKey = Uint8List.fromList(subjectKey).asUnmodifiableView(),
       signature = Uint8List.fromList(signature).asUnmodifiableView();

  final String id;
  final String issuerId;
  final Uint8List issuerKey;

  // 자격을 쥔 기기의 실행별 신원 공개키 (peerId는 이 키의 해시)
  final Uint8List subjectKey;
  final String org;
  final String dept;
  final String role;

  // 발급 정책 버전 (예: org-policy/2026-10)
  final String policy;
  final int issuedAtMs;
  final int expiresAtMs;

  // 발급 때 기준이 된 신뢰 번들 스냅샷 날짜 (폐기 목록 시점)
  final String snapshot;
  final Uint8List signature;

  Uint8List get signedBytes => utf8.encode(
    jsonEncode(<Object>[
      kOrgCredentialDomain,
      id,
      issuerId,
      base64.encode(issuerKey),
      base64.encode(subjectKey),
      org,
      dept,
      role,
      policy,
      issuedAtMs,
      expiresAtMs,
      snapshot,
    ]),
  );

  // PoP가 묶는 자격 지문: 서명까지 넣어서 같은 내용의 다른 발급본과도 구분됨
  String get digest => base64.encode(
    const DartSha256().hashSync(<int>[...signedBytes, ...signature]).bytes,
  );

  Future<bool> issuerSigned() =>
      verifyEd25519(message: signedBytes, signature: signature, key: issuerKey);

  Map<String, dynamic> toWire() => <String, dynamic>{
    'id': id,
    'iss': issuerId,
    'ik': base64.encode(issuerKey),
    'sk': base64.encode(subjectKey),
    'org': org,
    'dept': dept,
    'role': role,
    'pol': policy,
    'iat': issuedAtMs,
    'exp': expiresAtMs,
    'snap': snapshot,
    'sg': base64.encode(signature),
  };

  // 엄격 파싱: 하나라도 틀리면 null. 표시 문자열은 바이트 상한을 둠 (상대가 보낸 값이 배지에 그대로 뜸)
  static OrgCredential? fromWire(Object? raw) {
    if (raw is! Map) return null;
    String? text(String key, int max) {
      final value = wireText(raw[key], maxUtf8Bytes: max);
      return value == null || value.trim().isEmpty ? null : value;
    }

    final id = wireId(raw['id']);
    final issuerId = wireId(raw['iss']);
    final issuerKey = wireBytes(raw['ik'], length: 32);
    final subjectKey = wireBytes(raw['sk'], length: 32);
    final org = text('org', 96);
    final dept = text('dept', 96);
    final role = text('role', 64);
    final policy = raw['pol'];
    final issuedAt = wireInt(raw['iat'], min: 0, max: _kMaxWireInt);
    final expiresAt = wireInt(raw['exp'], min: 0, max: _kMaxWireInt);
    final snapshot = raw['snap'];
    final signature = wireBytes(raw['sg'], length: 64);
    if (id == null ||
        issuerId == null ||
        issuerKey == null ||
        subjectKey == null ||
        org == null ||
        dept == null ||
        role == null ||
        policy is! String ||
        !_labelPattern.hasMatch(policy) ||
        issuedAt == null ||
        expiresAt == null ||
        expiresAt <= issuedAt ||
        snapshot is! String ||
        !_datePattern.hasMatch(snapshot) ||
        signature == null) {
      return null;
    }
    return OrgCredential(
      id: id,
      issuerId: issuerId,
      issuerKey: issuerKey,
      subjectKey: subjectKey,
      org: org,
      dept: dept,
      role: role,
      policy: policy,
      issuedAtMs: issuedAt,
      expiresAtMs: expiresAt,
      snapshot: snapshot,
      signature: signature,
    );
  }
}

// 중계 전 정규화 (org_cred는 링크 밖으로 안 나가지만 받는 쪽 dispatch도 아는 필드만 봄)
Map<String, dynamic>? canonicalCredentialWire(Object? raw) =>
    OrgCredential.fromWire(raw)?.toWire();
