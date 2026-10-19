part of '../chat_room_screen.dart';

// 스크린 리더를 켠 사람에게 이 대화의 새 메시지를 한 번 읽어 줌 (메시지 목록은 라이브 영역이 아니라 저절로 안 읽힘)
mixin _ChatRoomAnnounce on _ChatRoomScreenStateBase {
  void _startAnnouncing() {
    _arrivals = ref
        .read(inMemoryStoreProvider)
        .inboundActivity
        .where((e) => e.conversationId == widget.conversationId)
        .listen((e) => _announce(e.message));
  }

  void _stopAnnouncing() => unawaited(_arrivals?.cancel());

  StreamSubscription<Object?>? _arrivals;

  void _announce(EphemeralMessage message) {
    if (!mounted || !MediaQuery.accessibleNavigationOf(context)) return;
    final s = S.of(context);
    final what = message.kind == MessageKind.file
        ? s.t('a11y.newFile')
        : (message.text ?? '');
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        '${s.t('a11y.fromPeer', {'name': message.senderAlias})}: '
        '${what.length > 120 ? '${what.substring(0, 120)}…' : what}',
        Directionality.of(context),
      ),
    );
  }
}
