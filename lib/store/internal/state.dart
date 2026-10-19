part of '../in_memory_store.dart';

abstract class _InMemoryStoreState {
  final Map<String, Conversation> _conversations = <String, Conversation>{};
  final Map<String, Map<String, EphemeralMessage>> _messages = {};
  final Map<String, String> _messageRooms = {};
  final Map<String, FileTransfer> _transfers = <String, FileTransfer>{};
  final Map<String, Timer> _burnTimers = <String, Timer>{};

  final Map<String, Timer> _typingTimers = <String, Timer>{};

  final Map<String, Timer> _ceilingTimers = <String, Timer>{};

  final StreamController<List<Conversation>> _conversationEvents =
      StreamController<List<Conversation>>.broadcast();
  final Map<String, StreamController<List<EphemeralMessage>>> _roomEvents =
      <String, StreamController<List<EphemeralMessage>>>{};
  final StreamController<List<FileTransfer>> _transferEvents =
      StreamController<List<FileTransfer>>.broadcast();

  // 메시지가 여기서 자기 타이머 만료로 소각될 때 발생 (피어가 시킨 게 아님)
  // 링크 레이어가 burn 프레임을 전달해서 시계나 wake 상태가 어긋나도 반대쪽이 lockstep으로 버림
  final StreamController<({String conversationId, String messageId})>
  _localBurns =
      StreamController<({String conversationId, String messageId})>.broadcast();

  Stream<({String conversationId, String messageId})> get localBurns =>
      _localBurns.stream;

  // 링크가 없거나 끊겨 상대에게 못 간 읽음·소각 신호 (1:1 대화 id별 메시지 id). 다음 링크가
  // 핸드셰이크를 마치면 PeerLink가 takeOwed로 꺼내 보냄. RAM에만 둠 (재시작하면 24시간 상한이 마지막 보루)
  final Map<String, Set<String>> _owedReads = {};
  final Map<String, Set<String>> _owedBurns = {};

  // null이면(기본) 순수 인메모리로 동작해서 디스크를 안 만짐. app_providers가 vault 저장 콜백을 연결함
  void Function()? onPersistableChange;
  Timer? _saveDebounce;
  Timer? _saveMaxWait;

  // 순수 런타임 값이라 스트림 emit 안 함 (설정 화면은
  // vaultSettingsProvider를 봄). 링크 레이어가 크기 게이트에서 읽음
  LargeMessageMode largeMessageMode = LargeMessageMode.inline;

  // '내가 연 대화만 받기' 설정의 미러: 링크 레이어가 모르는 기기의 인바운드를 거절할 때 읽음
  bool onlyChatsIStart = false;

  // 알림 브리지가 false일 때만 인바운드 메시지에 로컬 알림을 띄움
  bool appInForeground = true;

  // 시스템 메시지 제외. 알림 브리지가 구독해서 앱이 포그라운드가 아니면 로컬 알림을 띄움
  final StreamController<({String conversationId, EphemeralMessage message})>
  _inboundActivity =
      StreamController<
        ({String conversationId, EphemeralMessage message})
      >.broadcast();

  Stream<({String conversationId, EphemeralMessage message})>
  get inboundActivity => _inboundActivity.stream;

  bool _disposed = false;

  // 스토어에서 전송 레코드를 뗀 직후 호출 (burn/wipe 공통 경로):
  // 네트워크 레이어가 남은 자원(취소 토큰, 스테이징된 source/.part)을
  // 정리할 기회. app_providers가 연결하고 null이면(테스트 등) no-op
  Future<void> Function(FileTransfer transfer)? onTransferRemoved;

  // _removeTransfer가 켠 정리 작업들. burn은 UI가 네트워크 정리를 기다리며 멎으면 안 돼서
  // fire-and-forget이고,
  // 패닉만 drainDisposals로 전부 끝나길 기다림
  final Set<Future<void>> _pendingDisposals = <Future<void>>{};
}
