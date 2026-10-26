import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart' show DartSha256;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'os_privacy.dart';

final Random _idRng = Random.secure();

String _hex(Iterable<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

// 공개키 SHA-256 앞 16바이트 hex. 누구나 다시 계산할 수 있어서 hello의 peerId가 그 키 것인지 확인됨
String peerIdOfKey(List<int> publicKey) =>
    _hex(const DartSha256().hashSync(publicKey).bytes.take(16));

// 96비트라 한 세션 안에선 충돌 걱정 없음
String newId() {
  final bytes = List<int>.generate(12, (_) => _idRng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// 실행마다 새로 만드는 신원 (저장 안 해서 세션끼리 엮을 고정값이 없음). 앱 피어 링크는 키 있는 신원(create/withKey)만 됨.
// 키 없는 생성자·generate는 화면·테스트용
final class AppIdentity {
  AppIdentity({
    required this._peerId,
    required this.alias,
    required this.platform,
  }) : _publicKey = null,
       _seed = null;

  // peerId는 공개키에서 뽑아서 아무 값이나 못 붙임. 시드는 우리 사본으로 쥠
  AppIdentity.withKey({
    required List<int> seed,
    required List<int> publicKey,
    required this.alias,
    required this.platform,
  }) : _peerId = peerIdOfKey(publicKey),
       _publicKey = Uint8List.fromList(publicKey),
       _seed = Uint8List.fromList(seed);

  static Future<AppIdentity> create() async {
    final key = await _newKey();
    final identity = AppIdentity.withKey(
      seed: key.seed,
      publicKey: key.publicKey,
      alias: _randomAlias(Random.secure()),
      platform: await _askPlatform(),
    );
    // withKey가 따로 복사해 가니 이 사본은 0으로 덮음
    key.seed.fillRange(0, key.seed.length, 0);
    return identity;
  }

  // cryptography 키쌍의 destroy는 참조만 버리고 바이트는 안 지움. 지울 수 있는 건 이 사본뿐이라 호출부가 쥐고 지움
  static Future<({Uint8List seed, Uint8List publicKey})> _newKey() async {
    final generated = await Ed25519().newKeyPair();
    final pair = await generated.extract();
    final key = (
      seed: Uint8List.fromList(pair.bytes),
      publicKey: Uint8List.fromList(pair.publicKey.bytes),
    );
    pair.destroy();
    generated.destroy();
    return key;
  }

  String _peerId;
  Uint8List? _publicKey;
  Uint8List? _seed;

  // 패닉 소각(rotateKey) 때 바뀌니 캐시하지 말고 그때그때 읽을 것
  String get peerId => _peerId;

  Uint8List? get publicKey => _publicKey;

  @visibleForTesting
  Uint8List? get debugSeed => _seed;

  Future<Uint8List> sign(List<int> message) async {
    final seed = _seed;
    final publicKey = _publicKey;
    if (seed == null || publicKey == null) {
      throw StateError('this identity has no signing key');
    }
    final pair = SimpleKeyPairData(
      seed,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final signature = await Ed25519().sign(message, keyPair: pair);
    return Uint8List.fromList(signature.bytes);
  }

  // 패닉 소각용: 같은 peerId면 소각 전후 세션이 엮여서 키를 통째로 바꿈. 새 키를 다 뽑은 뒤 한 번에 갈아끼우고
  // 우리가 쥔 옛 시드만 확실히 0으로 덮음 (서명 중 라이브러리가 만든 사본까진 보장 못 함)
  Future<void> rotateKey() async {
    if (_seed == null) return;
    final fresh = await _newKey();
    final old = _seed; // await 중 다른 회전이 끼어도 지금 쥔 걸 지움
    _seed = fresh.seed;
    _publicKey = fresh.publicKey;
    _peerId = peerIdOfKey(fresh.publicKey);
    old?.fillRange(0, old.length, 0);
  }

  // LinkRegistry·DiscoveryController가 이 객체를 계속 쥐고 있어서 이름만 제자리에서 바꿈 (불변 규칙의 일부러 둔 예외)
  String alias;

  final String platform;

  void rename(String next) => alias = next;

  static const List<String> _adjectives = <String>[
    'blue',
    'calm',
    'swift',
    'quiet',
    'bright',
    'bold',
    'warm',
    'keen',
    'lucky',
    'brave',
    'clear',
    'soft',
    'sharp',
    'wise',
    'kind',
    'cool',
  ];

  static const List<String> _animals = <String>[
    'otter',
    'raven',
    'lynx',
    'heron',
    'ibex',
    'koi',
    'moth',
    'wren',
    'fox',
    'elk',
    'owl',
    'seal',
    'hare',
    'crow',
    'newt',
    'bat',
  ];

  factory AppIdentity.generate() {
    final rng = Random.secure();

    final idBytes = List<int>.generate(16, (_) => rng.nextInt(256));
    final peerId = idBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    return AppIdentity(
      peerId: peerId,
      alias: _randomAlias(rng),
      platform: _detectPlatform(),
    );
  }

  static String _randomAlias(Random rng) =>
      '${_adjectives[rng.nextInt(_adjectives.length)]}-'
      '${_animals[rng.nextInt(_animals.length)]}-'
      '${rng.nextInt(90) + 10}';

  static String randomAlias() => _randomAlias(Random.secure());

  // 펼친 iPhone도 큰 창일 수 있으므로 창 크기로 기기 종류를 추측하지 않음
  static Future<String> _askPlatform() async {
    final pad = await OsPrivacy.isPad();
    if (pad != null) return pad ? 'iPadOS' : 'iOS';
    return _detectPlatform();
  }

  static String _detectPlatform() {
    if (Platform.isIOS) return OsPrivacy.cachedIsPad == true ? 'iPadOS' : 'iOS';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }
}
