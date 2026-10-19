part of '../chat_room_screen.dart';

mixin _ChatRoomSearch on _ChatRoomScreenStateBase {
  String? get _currentHit =>
      _searching && _hits.isNotEmpty ? _hits[_hitIndex] : null;

  void _openSearch() => setState(() => _searching = true);

  void _closeSearch() {
    _searchCtrl.clear();
    setState(() {
      _searching = false;
      _hits = const <String>[];
      _hitIndex = 0;
    });
  }

  void _runSearch(String query) {
    final hits = ref
        .read(inMemoryStoreProvider)
        .searchMessages(query, conversationId: widget.conversationId)
        .map((r) => r.message.id)
        .toList();
    setState(() {
      _hits = hits;
      _hitIndex = hits.isEmpty ? 0 : hits.length - 1; // 최신 히트부터
    });
  }

  // Dart의 %는 양수 제수일 때 항상 0 이상이라 양방향 순환이 공짜
  void _moveHit(int delta) {
    if (_hits.isEmpty) return;
    setState(() => _hitIndex = (_hitIndex + delta) % _hits.length);
  }
}
