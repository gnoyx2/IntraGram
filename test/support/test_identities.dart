import 'package:intragram/core/app_identity.dart';

// 테스트용 고정 신원: 시드와 공개키를 상수로 둬서 실행마다 Ed25519 키를 새로 뽑지 않고 동기적으로
// 만듦(값이 서로 맞는지는 test_identities_test.dart가 검사함). peerId는 공개키의 해시라서 첫 글자
// ([tag])만 정해져 있음(a, b, c, ...): 테스트가 발신자를 첫 글자로 구분함
const Map<String, (String seed, String publicKey)> _keys = {
  'a': (
    '0100610000000000000000000000000000000000000000000000000000000000',
    '436c75bfaf13cd36d6cda606e7593138f605678709019fedf08e834b81eafea9',
  ),
  'b': (
    '1600620000000000000000000000000000000000000000000000000000000000',
    '93fdde2a222d0d714ed935c80469ca49cc7741fe47faaa5815afac7c0b576e28',
  ),
  'c': (
    '1400630000000000000000000000000000000000000000000000000000000000',
    'ba71719ecfcba42fcdc6d888b6d82dbc34d4f2b8e5a4da7e7be236da2dc53cc8',
  ),
  'd': (
    '1600640000000000000000000000000000000000000000000000000000000000',
    '78e454e903f6b02174d0ca322fbd486eefd9c8d286436b71f2b6512f944dca08',
  ),
  'e': (
    '0200650000000000000000000000000000000000000000000000000000000000',
    '532e3f90c0ea5ac7f1a180a17e3da925c40fd473baa53b07424c5497874afbd9',
  ),
  '0': (
    '0300300000000000000000000000000000000000000000000000000000000000',
    'c0449087d6108b9b7f233fab9338f0ee27a3aea17f658710c52272ded9c3a41a',
  ),
};

Iterable<String> get testIdentityTags => _keys.keys;

List<int> _unhex(String hex) => <int>[
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

// 같은 tag는 언제나 같은 키/peerId
AppIdentity testIdentity(
  String tag, {
  String alias = 'test',
  String platform = 'test',
}) {
  final (seed, publicKey) = _keys[tag]!;
  return AppIdentity.withKey(
    seed: _unhex(seed),
    publicKey: _unhex(publicKey),
    alias: alias,
    platform: platform,
  );
}

String testPeerId(String tag) => testIdentity(tag).peerId;
