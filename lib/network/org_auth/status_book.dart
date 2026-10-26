part of '../org_auth.dart';

// RAM 전용 조직 자격 장부: 내가 제시할 자격 하나와 링크 상대별 검증 결과(orgCredentialStatus). SAS 확인 상태
// (Conversation·RoomMember.verified)와 따로 둬서 서로 덮어쓰지 않음. 상대 결과는 그걸 받은 링크 수명만큼만 남고
// secureWipe가 내 자격까지 다 비움 (패닉으로 신원 키를 갈면 옛 자격은 어차피 키가 안 맞음)
final class OrgCredentialBook extends ChangeNotifier {
  OrgCredential? _holder;
  bool _closed = false;
  Timer? _expiryTimer;
  int _generation = 0;
  int get generation => _generation;
  final Map<String, ({OrgCredentialStatus status, Object owner})> _peers =
      <String, ({OrgCredentialStatus status, Object owner})>{};

  // 검증할 때 믿는 번들. 기본은 시연용 번들 하나 (테스트가 바꿔 끼움)
  Future<TrustBundle> Function() trustBundle = demoTrustBundle;

  OrgCredential? get holder => _holder;

  // 지금 신원 키에 묶인 자격만 제시함
  OrgCredential? holderFor(AppIdentity identity) {
    final credential = _holder;
    final key = identity.publicKey;
    if (credential == null ||
        key == null ||
        !_sameBytes(credential.subjectKey, key) ||
        DateTime.now().millisecondsSinceEpoch >= credential.expiresAtMs) {
      return null;
    }
    return credential;
  }

  void activate(OrgCredential credential) {
    if (_closed) return;
    _holder = credential;
    _scheduleExpiry();
    notifyListeners();
  }

  void deactivate() {
    if (_holder == null) return;
    _holder = null;
    _scheduleExpiry();
    _notify();
  }

  OrgCredentialStatus? statusOf(String? peerId) {
    final status = peerId == null ? null : _peers[peerId]?.status;
    return status != null &&
            status.verified &&
            DateTime.now().millisecondsSinceEpoch >=
                status.credential.expiresAtMs
        ? _expired(status)
        : status;
  }

  // 같은 링크가 같은 자격을 다시 내면 검증을 또 돌리지 않음 (프레임을 되풀이해 서명 검사를 시키지 못하게)
  bool alreadyChecked(String peerId, String digest, Object owner) {
    final known = _peers[peerId];
    return known != null &&
        identical(known.owner, owner) &&
        known.status.credential.digest == digest;
  }

  void record(
    String peerId,
    OrgCredentialStatus status, {
    required Object owner,
  }) {
    if (_closed) return;
    _peers[peerId] = (status: status, owner: owner);
    _scheduleExpiry();
    notifyListeners();
  }

  // 그 결과를 남긴 링크가 닫힐 때만 지움 (재접속한 새 링크가 남긴 결과는 늦게 닫힌 옛 링크가 못 지움)
  void forget(String peerId, {required Object owner}) {
    final known = _peers[peerId];
    if (known == null || !identical(known.owner, owner)) return;
    _peers.remove(peerId);
    _scheduleExpiry();
    _notify();
  }

  void clear() {
    _generation++;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _holder = null;
    _peers.clear();
    _notify();
  }

  void close() {
    if (_closed) return;
    clear();
    _closed = true;
    super.dispose();
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  OrgCredentialStatus _expired(OrgCredentialStatus status) =>
      OrgCredentialStatus(
        check: OrgCheck.expired,
        credential: status.credential,
        issuerName: status.issuerName,
        demo: status.demo,
      );

  // 한 개의 타이머로 만료 배지·대화상자·멤버 목록을 함께 갱신하고 만료된 내 자격의 제시도 중지함.
  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final deadlines = [
      if (_holder != null) _holder!.expiresAtMs,
      for (final peer in _peers.values)
        if (peer.status.verified) peer.status.credential.expiresAtMs,
    ];
    if (_closed || deadlines.isEmpty) return;
    final deadline = deadlines.reduce((a, b) => a < b ? a : b);
    _expiryTimer = Timer(
      Duration(milliseconds: deadline - DateTime.now().millisecondsSinceEpoch),
      () {
        _expiryTimer = null;
        if (_holder != null && _holder!.expiresAtMs <= deadline) _holder = null;
        _peers.updateAll(
          (_, peer) =>
              peer.status.verified &&
                  peer.status.credential.expiresAtMs <= deadline
              ? (status: _expired(peer.status), owner: peer.owner)
              : peer,
        );
        _scheduleExpiry();
        _notify();
      },
    );
  }
}
