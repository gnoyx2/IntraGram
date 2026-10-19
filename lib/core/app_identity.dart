import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart' show DartSha256;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'os_privacy.dart';

final Random _idRng = Random.secure();

String _hex(Iterable<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

// SHA-256 앞 16바이트(hex 32자). 누구나 다시 계산할 수 있어서 hello의 peerId가
// 실제 그 키의 것인지 검증됨 (mDNS로 광고하는 값도 동일)
String peerIdOfKey(List<int> publicKey) =>
    _hex(const DartSha256().hashSync(publicKey).bytes.take(16));

// 96비트면 한 세션 트래픽 안에서 충돌 확률은 무시 가능 (저장 안 함)
String newId() {
  final bytes = List<int>.generate(12, (_) => _idRng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// 세션마다 새로 만드는 신원. 아무것도 저장 안 해서 세션끼리 엮을 고정 식별자가 없음
// 앱 피어 링크는 create/withKey로 만든 키 있는 신원만 가능 (peerId = 공개키 해시)
// 키 없는 new/generate는 화면·테스트용. 패닉 소각은 rotateKey로 키와 peerId를 교체함
final class AppIdentity {
  AppIdentity({
    required this._peerId,
    required this.alias,
    required this.platform,
  }) : _publicKey = null,
       _seed = null;

  // peerId는 publicKey의 해시라 임의 값을 키에 붙일 수 없음. 시드는 자체 사본을 보관
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
    // withKey가 사본을 따로 쥐니 뽑은 사본은 0으로 덮음 (개인키 사본 잔존 방지)
    key.seed.fillRange(0, key.seed.length, 0);
    return identity;
  }

  // 라이브러리 키쌍의 destroy는 참조만 버리고 바이트를 안 지움(cryptography 2.9)
  // 지울 수 있는 건 이 사본뿐이라 호출부가 소유하고 지움
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

  // 키 있는 신원은 공개키 해시. mDNS 자기 탐지 필터와 대화 키에 쓰고,
  // 패닉 소각(rotateKey)에서만 바뀜
  String get peerId => _peerId;

  // hello에 실려 상대가 peerId를 검증하는 데 씀
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

  // 패닉 소각용. 같은 peerId면 소각 전후 세션을 엮을 수 있어서 키와 peerId를 새로 바꿈
  // 새 키를 뽑는 동안엔 옛 키가 유효하고, 뽑은 뒤 한 번에 교체함 (중간 상태 없음)
  // Dart 힙은 서명 중 라이브러리가 만든 임시 사본까지 지운다고 보장 못 해서
  // 여기서 쥔 사본만 확실히 0으로 덮음
  Future<void> rotateKey() async {
    if (_seed == null) return;
    final fresh = await _newKey();
    final old = _seed; // await 중 다른 회전이 끼어도 지금 쥔 걸 지움
    _seed = fresh.seed;
    _publicKey = fresh.publicKey;
    _peerId = peerIdOfKey(fresh.publicKey);
    old?.fillRange(0, old.length, 0);
  }

  // 소비자(LinkRegistry, DiscoveryController 등)가 참조로 쥐고 있어서 rename 때 제자리 변경함
  // 재구성 없이 다음 호출부터 새 이름을 씀 (불변 규칙의 의도된 예외)
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

  // iPad는 UIDevice에 물음. 못 물으면 창 크기 짐작
  static Future<String> _askPlatform() async {
    final pad = await OsPrivacy.isPad();
    if (pad != null) return pad ? 'iPadOS' : 'iOS';
    return _detectPlatform();
  }

  static String _detectPlatform() {
    if (Platform.isIOS) return _isTabletSized() ? 'iPadOS' : 'iOS';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  // dart:io엔 iPhone/iPad 구분이 없음. 기기 모델 조회 플러그인 대신
  // 짧은 변이 600dp 이상이면 태블릿으로 보는 Material 표준 휴리스틱 사용
  static bool _isTabletSized() {
    final view = ui.PlatformDispatcher.instance.views.firstOrNull;
    if (view == null) return false;
    final shortestSide = view.physicalSize.shortestSide / view.devicePixelRatio;
    return shortestSide >= 600;
  }
}
