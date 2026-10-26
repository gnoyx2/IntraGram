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

  // 여기 타이머로 소각되거나 사용자가 지울 때 나옴 (상대가 시킨 건 아님). 링크가 burn으로 넘겨서 시계가 어긋나도 양쪽이 같이 버림
  final StreamController<({String conversationId, String messageId})>
  _localBurns =
      StreamController<({String conversationId, String messageId})>.broadcast();

  Stream<({String conversationId, String messageId})> get localBurns =>
      _localBurns.stream;

  // 상대에게 못 간 읽음·소각 (1:1 대화별). 다음 링크가 핸드셰이크를 마치면 takeOwed로 꺼내 보냄.
  // RAM에만 둠 (재시작하면 24시간 상한이 마지막 보루)
  final Map<String, Set<String>> _owedReads = {};
  final Map<String, Set<String>> _owedBurns = {};

  // null이면 디스크를 안 만짐. app_providers가 보관소 저장을 이음
  void Function()? onPersistableChange;
  Timer? _saveDebounce;
  Timer? _saveMaxWait;

  // 설정의 미러: 링크가 크기 게이트에서 읽음 (화면은 vaultSettingsProvider를 봐서 emit 안 함)
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

  // 전송 레코드를 뗀 직후 불림 (소각·와이프 공통): 네트워크 쪽이 남은 자원(토큰, source, .part)을 정리함
  Future<void> Function(FileTransfer transfer)? onTransferRemoved;

  // _removeTransfer가 켠 정리들. 소각은 UI가 멎으면 안 돼서 안 기다리고 패닉만 drainDisposals로 기다림
  final Set<Future<void>> _pendingDisposals = <Future<void>>{};

  // 서명 증적·Merkle 배치 (RAM 전용, Vault 스냅샷에 안 들어감). 수명만 여기 묶어서 secureWipe가 같이 비움
  final EvidenceStore evidence = EvidenceStore();
  final RoomIntegrityBook roomIntegrity = RoomIntegrityBook();
  final OrgCredentialBook orgCredentials = OrgCredentialBook();
}
