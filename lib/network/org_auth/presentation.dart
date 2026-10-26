part of '../org_auth.dart';

const String kOrgPopDomain = 'intragram/org-pop/v1';

// 발급 시각이 기기 시계보다 조금 앞서도 받아 줌 (LAN 기기끼리 시계가 몇 분씩 어긋남)
const Duration _kClockSkew = Duration(minutes: 5);

// 자격을 쥔 쪽이 '이 세션에서 이 자격을 내가 제시함'이라고 신원 키로 서명하는 바이트(PoP).
// 세션 지문(양쪽 임시키)·역할(D/L)·양쪽 peerId를 묶어서 다른 세션·반대 방향·다른 상대에게 옮겨 쓰지 못함
Uint8List orgPopBytes({
  required String credentialDigest,
  required String policy,
  required List<int> sessionBinding,
  required bool holderDialled,
  required String holderPeerId,
  required String verifierPeerId,
}) => utf8.encode(
  jsonEncode(<Object>[
    kOrgPopDomain,
    credentialDigest,
    policy,
    base64.encode(sessionBinding),
    holderDialled ? 'D' : 'L',
    holderPeerId,
    verifierPeerId,
  ]),
);

enum OrgCheck {
  verified,
  untrustedIssuer,
  invalidSignature,
  policyMismatch,
  revoked,
  snapshotMismatch,
  expired,
  notYetValid,
  subjectMismatch,
  invalidPop,
}

// 검증 결과. 확인 실패면 credential의 기관·역할은 상대 주장일 뿐이라 화면이 그대로 믿고 보여 주지 않음
@immutable
final class OrgCredentialStatus {
  const OrgCredentialStatus({
    required this.check,
    required this.credential,
    this.issuerName,
    this.demo = false,
  });

  final OrgCheck check;
  final OrgCredential credential;
  final String? issuerName;
  final bool demo;

  bool get verified => check == OrgCheck.verified;
}

// 순서대로 봄: 믿는 발급기관 → 발급 서명 → 정책 → 폐기 → 스냅샷 → 유효 기간 → 자격 주인이 이 링크 상대인가 → 이 세션 PoP
Future<OrgCredentialStatus> verifyOrgPresentation({
  required OrgCredential credential,
  required List<int> pop,
  required TrustBundle bundle,
  required String holderPeerId,
  required String verifierPeerId,
  required List<int> sessionBinding,
  required bool holderDialled,
  DateTime? now,
}) async {
  OrgCredentialStatus result(OrgCheck check, [TrustedIssuer? issuer]) =>
      OrgCredentialStatus(
        check: check,
        credential: credential,
        issuerName: issuer?.name,
        demo: issuer?.demo ?? false,
      );
  final issuer = bundle.issuerFor(credential);
  if (issuer == null) return result(OrgCheck.untrustedIssuer);
  if (!await credential.issuerSigned()) {
    return result(OrgCheck.invalidSignature, issuer);
  }
  if (!issuer.policies.contains(credential.policy)) {
    return result(OrgCheck.policyMismatch, issuer);
  }
  if (bundle.revoked.contains(credential.id)) {
    return result(OrgCheck.revoked, issuer);
  }
  if (credential.snapshot != bundle.snapshot) {
    return result(OrgCheck.snapshotMismatch, issuer);
  }
  final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
  if (at >= credential.expiresAtMs) return result(OrgCheck.expired, issuer);
  if (at + _kClockSkew.inMilliseconds < credential.issuedAtMs) {
    return result(OrgCheck.notYetValid, issuer);
  }
  if (peerIdOfKey(credential.subjectKey) != holderPeerId) {
    return result(OrgCheck.subjectMismatch, issuer);
  }
  final popOk = await verifyEd25519(
    message: orgPopBytes(
      credentialDigest: credential.digest,
      policy: credential.policy,
      sessionBinding: sessionBinding,
      holderDialled: holderDialled,
      holderPeerId: holderPeerId,
      verifierPeerId: verifierPeerId,
    ),
    signature: pop,
    key: credential.subjectKey,
  );
  return result(popOk ? OrgCheck.verified : OrgCheck.invalidPop, issuer);
}
