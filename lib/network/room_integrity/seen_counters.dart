part of '../room_integrity.dart';

// 연속 번호는 한 구간으로 압축. 재접속 때 무작위 시작 번호나 순서가 뒤집힌 글도 따로 보존함.
// 구간 상한에서 새 구간은 거부하며, 과거 번호를 잊어서 재생을 허용하지 않음.
final class _SeenAuthorCounters {
  final List<({String peer, int first, int last})> _ranges = [];

  bool add(String peer, int counter) {
    var first = counter;
    var last = counter;
    final adjacent = <int>[];
    for (var i = 0; i < _ranges.length; i++) {
      final range = _ranges[i];
      if (range.peer != peer) continue;
      if (range.first <= counter && counter <= range.last) return false;
      if (range.last + 1 == counter || range.first - 1 == counter) {
        adjacent.add(i);
        if (range.first < first) first = range.first;
        if (range.last > last) last = range.last;
      }
    }
    if (adjacent.isEmpty && _ranges.length >= RoomIntegrityBook.window) {
      return false;
    }
    for (final i in adjacent.reversed) {
      _ranges.removeAt(i);
    }
    _ranges.add((peer: peer, first: first, last: last));
    return true;
  }
}
