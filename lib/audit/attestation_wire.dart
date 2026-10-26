part of 'attestation.dart';

SignedAttestation? _attestationFromWire(Object? raw) {
  if (raw is! Map || raw['domain'] != kAttestationDomain) return null;
  final kind = AttestationKind.values
      .where((k) => k.name == raw['k'])
      .firstOrNull;
  final eventId = wireId(raw['e']);
  final subjectId = wireId(raw['s']);
  final attemptId = wireId(raw['a']);
  final counterpartId = wireId(raw['cp']);
  final counterpartKey = wireBytes(raw['ck'], length: 32);
  final signerKey = wireBytes(raw['pk'], length: 32);
  final commitment = wireBytes(raw['c'], length: 32);
  final nonce = wireBytes(raw['n'], length: 16);
  final signature = wireBytes(raw['sg'], length: 64);
  final policy = _label(raw['p']);
  final outcome = _label(raw['o']);
  final issuedAt = wireInt(raw['t'], min: 0, max: 9007199254740991);
  if (kind == null ||
      eventId == null ||
      subjectId == null ||
      (raw['a'] != null && attemptId == null) ||
      (raw['cp'] != null && counterpartId == null) ||
      (raw['ck'] != null &&
          (counterpartKey == null ||
              peerIdOfKey(counterpartKey) != counterpartId)) ||
      signerKey == null ||
      commitment == null ||
      nonce == null ||
      signature == null ||
      policy == null ||
      outcome == null ||
      issuedAt == null) {
    return null;
  }
  return SignedAttestation(
    kind: kind,
    eventId: eventId,
    subjectId: subjectId,
    attemptId: attemptId,
    signerKey: signerKey,
    counterpartId: counterpartId,
    counterpartKey: counterpartKey,
    commitment: base64.encode(commitment),
    policy: policy,
    outcome: outcome,
    nonce: base64.encode(nonce),
    issuedAtMs: issuedAt,
    signature: signature,
  );
}

bool _counterpartMatches(String? peerId, Uint8List? key) =>
    key == null || (key.length == 32 && peerIdOfKey(key) == peerId);
