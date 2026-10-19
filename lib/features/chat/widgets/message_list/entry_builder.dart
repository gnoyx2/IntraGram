part of '../message_list.dart';

extension _MessageListEntryBuilder on _MessageListState {
  // 첫 안 읽은 메시지 id. unreadOnOpen개만큼 뒤에서 세되 시스템/발신 메시지는 건너뜀 (bumpUnread와 같은 기준)
  // 소각 고스트는 이미 읽고 지나간 메시지라 widget.messages 기준으로만 셈
  String? _firstUnreadId() {
    if (widget.unreadOnOpen <= 0) return null;
    var remaining = widget.unreadOnOpen;
    for (var i = widget.messages.length - 1; i >= 0; i--) {
      final m = widget.messages[i];
      if (m.direction == MessageDirection.incoming &&
          m.kind != MessageKind.system) {
        remaining--;
        if (remaining == 0) return i > 0 ? m.id : null;
      }
    }
    return null;
  }

  DateTime _entryTime(_Entry e) => switch (e) {
    _MessageEntry(:final message) => message.createdAt,
    _GhostEntry(:final ghost) => ghost.createdAt,
    _SeparatorEntry() => DateTime.fromMillisecondsSinceEpoch(0),
  };

  // widget.messages와 소각 고스트를 시간순으로 섞어서, 사라지는 동안 원래 자리 근처에 계속 보이게 함
  List<_Entry> _messagesAndGhosts() {
    final combined = <_Entry>[
      for (final m in widget.messages) _Entry.message(m),
      for (final g in _burning.values) _Entry.ghost(g),
    ];
    if (_burning.isNotEmpty) {
      combined.sort((a, b) => _entryTime(a).compareTo(_entryTime(b)));
    }
    return combined;
  }

  List<_Entry> _buildEntries() {
    final s = S.of(context);
    final entries = <_Entry>[];
    final firstUnreadId = _firstUnreadId();
    DateTime? lastDay;
    for (final entry in _messagesAndGhosts()) {
      final day = DateUtils.dateOnly(_entryTime(entry).toLocal());
      if (lastDay == null || day != lastDay) {
        entries.add(_Entry.separator(s.dayLabel(day)));
        lastDay = day;
      }
      if (entry is _MessageEntry && entry.message.id == firstUnreadId) {
        entries.add(_Entry.separator(s.t('msglist.newMessages')));
      }
      entries.add(entry);
    }
    return entries;
  }
}
