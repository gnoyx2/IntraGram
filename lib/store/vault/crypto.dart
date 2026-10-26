part of '../vault.dart';

// PIN 봉인(PBKDF2 키 + ChaCha20-Poly1305)과 duress PIN을 확인함
extension _VaultCrypto on Vault {
  void _clearKey() {
    _keyGeneration++;
    _sessionKey?.destroy();
    _sessionKey = null;
    _keyReady = null;
    _keyError = null;
  }

  Future<SecretKeyData> _deriveKey(
    String pin,
    List<int> salt, {
    int iterations = kVaultPbkdf2Iterations,
  }) {
    debugKdfCount++;
    return _deriveVaultKey(pin, salt, iterations: iterations);
  }

  Future<String> _encrypt(String plaintext, SecretKey key) async {
    final salt = base64.encode(_salt!);
    final dchk = _dchk ??= base64.encode(_randomBytes(32));
    final ds = base64.encode(_dchkSalt ??= _randomBytes(16));
    final box = await _aead.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: _aead.newNonce(),
    );
    return jsonEncode(<String, dynamic>{
      'v': 1,
      'enc': true,
      'kdf': <String, dynamic>{'salt': salt, 'iter': kVaultPbkdf2Iterations},
      'n': base64.encode(box.nonce),
      'c': base64.encode(box.cipherText),
      'm': base64.encode(box.mac.bytes),
      'dchk': dchk,
      'ds': ds,
      if (_dchkIterations != kVaultPbkdf2Iterations) 'di': _dchkIterations,
      'dv': _kDchkVersion,
    });
  }

  Future<String> _newDecoyCheck(
    String pin,
    List<int> salt, {
    int iterations = kVaultPbkdf2Iterations,
  }) async {
    final key = await _deriveKey(pin, salt, iterations: iterations);
    try {
      return base64.encode(await _dchkFromKey(key.bytes));
    } finally {
      key.destroy();
    }
  }

  // dchk와 PIN에서 뽑은 값을 상수 시간 비교. duress가 없으면 dchk는 난수라 절대 안 맞음
  // dv가 없는 옛 파일은 PBKDF2 출력을 그대로 담았으니 그대로 비교함
  Future<bool> _matchesDecoy(Map<String, dynamic> map, String pin) async {
    try {
      final expected = map['dchk'];
      if (expected is! String) return false;
      final kdf = (map['kdf'] as Map).cast<String, dynamic>();
      _requireSupportedIterations(kdf['iter']);
      final iterations = _requireSupportedIterations(map['di'] ?? kdf['iter']);
      final salt = base64.decode((map['ds'] ?? kdf['salt']).toString());
      final key = await _deriveKey(pin, salt, iterations: iterations);
      try {
        final actual = map['dv'] == _kDchkVersion
            ? await _dchkFromKey(key.bytes)
            : key.bytes;
        return _constantTimeEquals(actual, base64.decode(expected));
      } finally {
        key.destroy();
      }
    } on Object {
      return false;
    }
  }

  // 진짜 unlock 때 세션에 넣을 (salt, dchk, 재저장 필요). 옛 dchk(PBKDF2 원본)는 HKDF로
  // 한 번 더 감아서 v2로 올림. 옛 dchk가 진짜 키와 같으면(진짜 PIN = duress PIN으로 저장된 파일)
  // 키가 평문으로 샌 상태라 salt를 새로 뽑고 duress는 버림. 디스크엔 다음 save부터 반영됨
  Future<({List<int> salt, String? dchk, bool rewrite})> _migratedDchk(
    Map<String, dynamic> map,
    SecretKeyData key,
    List<int> salt,
  ) async {
    final stored = map['dchk'] is String ? map['dchk'] as String : null;
    if (map['dv'] == _kDchkVersion || stored == null) {
      return (salt: salt, dchk: stored, rewrite: false);
    }
    final raw = base64.decode(stored);
    if (_constantTimeEquals(key.bytes, raw)) {
      return (salt: _randomBytes(16), dchk: null, rewrite: true);
    }
    final upgraded = base64.encode(await _dchkFromKey(raw));
    return (salt: salt, dchk: upgraded, rewrite: true);
  }

  // 새 진짜 PIN이 duress PIN과 같은지. 재시작 뒤엔 duress PIN 원문이 없어서 dchk로 대조함
  Future<bool> _isDecoyPin(String pin) async {
    if (_decoyPin != null) return pin == _decoyPin;
    final dchk = _dchk;
    final salt = _dchkSalt;
    if (dchk == null || salt == null) return false;
    return _constantTimeEquals(
      base64.decode(
        await _newDecoyCheck(pin, salt, iterations: _dchkIterations),
      ),
      base64.decode(dchk),
    );
  }

  // 틀린 PIN이면 MAC 검증이 실패해서 null
  Future<({String plain, SecretKeyData key})?> _decrypt(
    Map<String, dynamic> map,
    String pin,
  ) async {
    SecretKeyData? key;
    try {
      final kdf = (map['kdf'] as Map).cast<String, dynamic>();
      final iterations = _requireSupportedIterations(kdf['iter']);
      key = await _deriveKey(
        pin,
        base64.decode(kdf['salt'].toString()),
        iterations: iterations,
      );
      final box = SecretBox(
        base64.decode(map['c'].toString()),
        nonce: base64.decode(map['n'].toString()),
        mac: Mac(base64.decode(map['m'].toString())),
      );
      final bytes = await _aead.decrypt(box, secretKey: key);
      return (plain: utf8.decode(bytes), key: key);
    } on Object {
      key?.destroy();
      return null;
    }
  }
}

const int _kDchkVersion = 2;
const String _kDchkInfo = 'intragram/vault/dchk/v2';

// 봉인 키와 같은 PBKDF2 출력을 dchk에 그대로 쓰면 안 됨. 진짜 PIN이 duress PIN과 같아지는 순간
// 파일에 복호화 키가 평문으로 박힘. HKDF로 용도를 갈라서 dchk만 보고는 키를 못 얻게 함
Future<List<int>> _dchkFromKey(List<int> pbkdf2Out) async {
  final key = await Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  ).deriveKey(secretKey: SecretKey(pbkdf2Out), info: utf8.encode(_kDchkInfo));
  return key.extractBytes();
}

// iter는 현행 200k나 옛 100k만 받음: 조작한 횟수로 KDF 비용을 낮추거나 읽기를 하염없이 묶지 못하게 함
int _requireSupportedIterations(Object? rawIter) {
  if (rawIter is! int ||
      (rawIter != kVaultPbkdf2Iterations &&
          rawIter != kVaultLegacyPbkdf2Iterations)) {
    throw const FormatException('unsupported vault kdf.iter');
  }
  return rawIter;
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

List<int> _randomBytes(int n) {
  final rng = Random.secure();
  return List<int>.generate(n, (_) => rng.nextInt(256));
}

// KDF는 별도 isolate에서 돌림. 받은 Uint8List는 앱 소유 키로 쥐어서 lock·패닉의 destroy가 0으로 덮음
// (isolate 안 라이브러리 사본은 못 덮고 isolate 종료로 힙만 반납됨)
Future<SecretKeyData> _deriveVaultKey(
  String pin,
  List<int> salt, {
  int iterations = kVaultPbkdf2Iterations,
}) async {
  final bytes = await Isolate.run(() async {
    final key = await CryptoEngine.deriveKeyFromPin(
      pin,
      salt,
      iterations: iterations,
    );
    try {
      return Uint8List.fromList(await key.extractBytes());
    } finally {
      key.destroy();
    }
  });
  return ownedSecretKeyFrom(bytes);
}
