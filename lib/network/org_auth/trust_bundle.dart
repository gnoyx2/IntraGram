part of '../org_auth.dart';

@immutable
final class TrustedIssuer {
  TrustedIssuer({
    required this.id,
    required this.name,
    required List<int> key,
    required Set<String> policies,
    this.demo = false,
  }) : key = Uint8List.fromList(key).asUnmodifiableView(),
       policies = Set.unmodifiable(policies);

  final String id;
  final String name;
  final Uint8List key;

  // 이 발급기관 자격으로 받아 주는 정책 버전들
  final Set<String> policies;

  // 공개 시드로 만든 시연용 발급기관: 누구나 같은 자격을 만들 수 있어서 화면이 늘 '시연용'을 붙임
  final bool demo;
}

// 검증하는 쪽이 믿는 발급기관 공개키 묶음 + 그 시점(스냅샷)의 폐기 목록. 네트워크로 받아 오지 않음
@immutable
final class TrustBundle {
  TrustBundle({
    required this.id,
    required this.snapshot,
    required List<TrustedIssuer> issuers,
    Set<String> revoked = const <String>{},
  }) : issuers = List.unmodifiable(issuers),
       revoked = Set.unmodifiable(revoked);

  final String id;
  final String snapshot;
  final List<TrustedIssuer> issuers;
  final Set<String> revoked;

  TrustedIssuer? issuerFor(OrgCredential credential) => issuers
      .where(
        (i) =>
            i.id == credential.issuerId &&
            _sameBytes(i.key, credential.issuerKey),
      )
      .firstOrNull;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

const String kDemoIssuerId = 'intragram-demo-issuer';
const String kDemoIssuerName = 'Intragram Demo Issuer';
const String kDemoPolicy = 'org-policy/2026-10';
const String kDemoSnapshot = '2026-10-24';

Future<({AppIdentity issuer, TrustBundle bundle})>? _demo;

// 시연용 발급기관: 시드가 앱에 공개돼 있어 실제 신원 보증은 못 함. 같은 앱끼리 인터넷 없이 발급·검증을 보여 주는 용도
Future<({AppIdentity issuer, TrustBundle bundle})> _demoIssuer() =>
    _demo ??= () async {
      final seed = const DartSha256()
          .hashSync(utf8.encode('intragram/demo-org-issuer/v1'))
          .bytes;
      final pair = await Ed25519().newKeyPairFromSeed(seed);
      final key = Uint8List.fromList((await pair.extractPublicKey()).bytes);
      return (
        issuer: AppIdentity.withKey(
          seed: seed,
          publicKey: key,
          alias: kDemoIssuerName,
          platform: 'issuer',
        ),
        bundle: TrustBundle(
          id: 'intragram-demo-bundle',
          snapshot: kDemoSnapshot,
          issuers: [
            TrustedIssuer(
              id: kDemoIssuerId,
              name: kDemoIssuerName,
              key: key,
              policies: const {kDemoPolicy},
              demo: true,
            ),
          ],
        ),
      );
    }();

Future<TrustBundle> demoTrustBundle() async => (await _demoIssuer()).bundle;

// 지금 실행의 신원 키에 시연용 자격을 발급함. 만료 기간은 짧게 둠 (실행 종료 시 키와 함께 소멸하지만 장시간 구동 기기도 고려함)
Future<OrgCredential> issueDemoCredential(
  AppIdentity holder, {
  required String org,
  required String dept,
  required String role,
  Duration validFor = const Duration(hours: 12),
  DateTime? now,
}) async {
  final key = holder.publicKey;
  if (key == null) throw StateError('this identity has no signing key');
  final demo = await _demoIssuer();
  final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final unsigned = OrgCredential(
    id: newId(),
    issuerId: kDemoIssuerId,
    issuerKey: demo.bundle.issuers.single.key,
    subjectKey: Uint8List.fromList(key),
    org: org.trim(),
    dept: dept.trim(),
    role: role.trim(),
    policy: kDemoPolicy,
    issuedAtMs: at,
    expiresAtMs: at + validFor.inMilliseconds,
    snapshot: demo.bundle.snapshot,
    signature: Uint8List(64),
  );
  final signed = OrgCredential.fromWire(<String, dynamic>{
    ...unsigned.toWire(),
    'sg': base64.encode(await demo.issuer.sign(unsigned.signedBytes)),
  });
  if (signed == null) throw ArgumentError('credential fields out of bounds');
  return signed;
}
