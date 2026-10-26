import 'dart:typed_data';

import 'package:cryptography/dart.dart' show DartSha256;

// 소금 친 Merkle 트리. 잎 = SHA-256(0x00 ‖ salt ‖ 내용), 마디 = SHA-256(0x01 ‖ 왼쪽 ‖ 오른쪽) (RFC 6962처럼 앞 바이트로
// 잎을 마디로 위장 못 함). salt가 있어서 증명 하나에 딸린 형제 해시로 다른 사건 내용을 짐작 못 함.
// 층이 홀수면 마지막 마디를 그대로 올림 (복제하면 잎 목록 두 개가 같은 루트를 냄)

Uint8List merkleLeaf(List<int> salt, List<int> payload) =>
    sha256Bytes(<int>[0x00, ...salt, ...payload]);

Uint8List merkleNode(List<int> left, List<int> right) =>
    sha256Bytes(<int>[0x01, ...left, ...right]);

Uint8List sha256Bytes(List<int> bytes) =>
    Uint8List.fromList(const DartSha256().hashSync(bytes).bytes);

List<List<Uint8List>> _levels(List<Uint8List> leaves) {
  final levels = <List<Uint8List>>[leaves];
  var current = leaves;
  while (current.length > 1) {
    final next = <Uint8List>[
      for (var i = 0; i < current.length; i += 2)
        i + 1 < current.length
            ? merkleNode(current[i], current[i + 1])
            : current[i],
    ];
    levels.add(next);
    current = next;
  }
  return levels;
}

// 빈 목록이면 빈 입력의 SHA-256 (배치는 잎이 있을 때만 만들지만 빈 관측 체크포인트도 같은 값으로 맞춤)
Uint8List merkleRoot(List<Uint8List> leaves) =>
    leaves.isEmpty ? sha256Bytes(const <int>[]) : _levels(leaves).last.single;

// index번 잎에서 루트까지 형제 해시들 (형제가 없어 그대로 올라간 층은 건너뜀)
List<Uint8List> merkleProof(List<Uint8List> leaves, int index) {
  RangeError.checkValidIndex(index, leaves);
  final path = <Uint8List>[];
  var i = index;
  for (final level in _levels(leaves)) {
    if (level.length == 1) break;
    final sibling = i.isEven ? i + 1 : i - 1;
    if (sibling < level.length) path.add(level[sibling]);
    i ~/= 2;
  }
  return path;
}

// 잎 개수와 위치로 층마다 형제가 있어야 하는지 다시 계산해서 경로 모양까지 맞아야 통과 (남는 경로·모자란 경로 둘 다 거부)
bool verifyMerkleProof({
  required List<int> leaf,
  required int index,
  required int leafCount,
  required List<List<int>> path,
  required List<int> root,
}) {
  if (leafCount < 1 ||
      index < 0 ||
      index >= leafCount ||
      leaf.length != 32 ||
      root.length != 32 ||
      path.any((hash) => hash.length != 32)) {
    return false;
  }
  var hash = leaf;
  var i = index;
  var width = leafCount;
  var used = 0;
  while (width > 1) {
    final sibling = i.isEven ? i + 1 : i - 1;
    if (sibling < width) {
      if (used >= path.length) return false;
      final other = path[used++];
      hash = i.isEven ? merkleNode(hash, other) : merkleNode(other, hash);
    }
    i ~/= 2;
    width = (width + 1) ~/ 2;
  }
  return used == path.length && bytesEqual(hash, root);
}

bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
