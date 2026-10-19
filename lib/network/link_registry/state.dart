part of '../link_registry.dart';

// 동작은 link_registry/의 믹스인(_LinkRegistryRoom
// 위에 Session/Connect/Chat/Facade)으로 나뉨
// 생성자 본문이 부르는 linkFor와 _broadcastToRoom은 room_broadcast.dart에 있음
abstract class _LinkRegistryState {
  _LinkRegistryState({
    required this.store,
    required this.crypto,
    required this.identity,
    Future<String?> Function(String suggestedName)? chooseDirectory,
    Duration ackTimeout = kFileReceivedAckTimeout,
  }) {
    _transfers = TransferCoordinator(
      store: store,
      identity: identity,
      linkFor: linkFor,
      linkForTransfer: linkForIncomingTransfer,
      linksForTransfer: linksForTransfer,
      localEndpoint: () => localEndpoint,
      chooseDirectory: chooseDirectory,
      ackTimeout: ackTimeout,
    );
    // 메시지의 자기 타이머가 여기서 소각하면 피어에게 알려서 시계나 wake 상태가 어긋났어도 양쪽이 같이 버림
    _localBurnSub = store.localBurns.listen((event) {
      if (_isRoomHub(event.conversationId)) {
        unawaited(
          _broadcastToRoom(
            event.conversationId,
            InnerFrame.burn(event.messageId),
          ),
        );
      } else {
        // 링크가 없거나 못 나가면 다음 링크가 갚게 적어 둠 (markRoomRead의 영수증과 같은 이유)
        final link = _links[event.conversationId];
        void owe() => store.oweBurn(event.conversationId, event.messageId);
        if (link == null) {
          owe();
        } else {
          unawaited(
            link.sendRawInnerOrClose(InnerFrame.burn(event.messageId)).then((
              ok,
            ) {
              if (!ok) owe();
            }),
          );
        }
      }
    });
  }

  final InMemoryStore store;
  final CryptoEngine crypto;
  final AppIdentity identity;

  // disposeAll이 시작하면 즉시(첫 await 전에) true: 이후 새 링크 등록을 전부 거부.
  // 한 번 disposed되면 이 인스턴스는 안 쓰이고 다음 세션은 새 LinkRegistry로 시작
  bool _disposed = false;

  // disposeAll 호출마다 증가. _register가 crypto.createSession()
  // await에서 돌아왔을 때 시작 때 캡처한 값과 다르면(그사이 disposeAll이 돎)
  // 늦게 얻은 channel/session을 등록하지 않고 버림
  int _generation = 0;

  // 이 기기 임베디드 서버의 사설 host:port. ServerController가 바인딩하면 채우고 멈추면 비움
  // 그룹 방 파일 제안에 도장 찍어서 다른 멤버가 여기서 바이트를 직접 당기게 함 (_transfers로 seam 전달)
  ({String host, int port})? localEndpoint;

  // 이번 실행에서 차단한 기기의 peerId (_LinkRegistryBlocking). 신원 키가 실행마다 바뀌어 RAM에만 둠
  final Set<String> _blockedPeers = <String>{};

  // hello의 peerId를 받을지: null이면 진행, 아니면 그 이유로 닫음 (_LinkRegistryBlocking)
  SystemEventKind? _refusal(String peerId, {required bool dialledByUs});

  // 앱 피어 링크 (대화 하나 = 링크 하나). 웹 게스트 링크는 포털 룸 하나에 여러 게스트가 붙어서 _roomLinks로 빠짐
  final Map<String, PeerLink> _links = <String, PeerLink>{};

  // 호스트 중계 방에 붙어있는 링크 전부: 브라우저 게스트(_webGuestRoomId)와 앱 그룹
  // 멤버(_appRoomId)가 섞여 있어서 필터링은 항상 link.conversationId로
  // 함
  // (비밀 1:1/앱 전용 방과 웹 게스트 방을 자동으로 합치지 않으려고 방을 둘로 분리, _LinkRegistryRoom 참고)
  final List<PeerLink> _roomLinks = <PeerLink>[];

  // 호스트가 중계하는 방 파일 경로: 키는 (전송 id, attempt), 값은 그 offer를 낸 멤버 링크와 받을 멤버 링크
  // 링크가 닫히거나 attempt가 끝나면 지움 (_RoomFileRouting)
  final Map<(String, String), _RoomFileRoute> _roomFileRoutes = {};

  // 발신자당 미완료 경로 상한 (테스트만 낮춰 봄)
  int _maxRoomFileRoutesPerSender = _kMaxRoomFileRoutesPerSender;

  // 테스트만 세팅: connectToPeer의 소켓 다이얼을 인메모리 채널로 바꿈. 프로덕션에선 null
  Future<StreamChannel<dynamic>> Function(PeerDevice peer)? _debugDial;

  // 모든 브라우저 게스트가 들어오는 공유 대화. 첫 게스트가 토큰 검증을
  // 통과한 web_hello를 보낼 때 생기고 세션 소각 전까지 유지됨
  // (게스트가 없어도 offline 상태로 남음). 앱 그룹 방(_appRoomId)과는
  // 별개라 웹 게스트가 앱 전용 방/비밀 대화를 볼 방법이 없음
  String? _webGuestRoomId;

  // 아직 아무도 안 붙었으면 null
  String? get portalRoomId => _webGuestRoomId;

  // 앱 피어들이 모인 호스트 중계 그룹 방. inviteToRoom/addPeersToRoom이 만들거나 재사용하고 웹 게스트 방과는 별개
  String? _appRoomId;

  // 내 앱 그룹 방을 끝낼 때마다 오름. 끝나기 전에 보낸 초대가 그 뒤에 증명을 마쳐도 새 방을 안 만들게 함
  int _appRoomEpoch = 0;

  String? get appRoomId => _appRoomId;

  bool _isRoomHub(String conversationId) =>
      conversationId == _webGuestRoomId || conversationId == _appRoomId;

  late final TransferCoordinator _transfers;

  StreamSubscription<({String conversationId, String messageId})>?
  _localBurnSub;

  PeerLink? linkFor(String conversationId) {
    final direct = _links[conversationId];
    if (direct != null) return direct;
    // 호스트 중계 방: 멤버가 정확히 한 명이면 그 링크로 라우팅 (호스트<->단일 상대 파일 전송이 계속 되게)
    // 여러 명이면 모호해서 null: 다중 멤버/게스트 방은 파일 전송 없이 텍스트 대화만
    final inRoom = _memberLinks(conversationId);
    return inRoom.length == 1 ? inRoom.single : null;
  }

  // 인커밍 전송의 accept/reject/cancel/retry/ACK를 되돌려 보낼 발신자
  // 링크. 1:1/멤버 링크는 대화당 하나라 바로 찾고, 내가 호스트인 방이면 실제로 보낸 링크를
  // FileTransfer.senderPeerId로 고름 (웹 게스트는 peerId가 없어 alias).
  // alias가 겹쳐 못 좁히면 null: 엉뚱한 게스트에게 push 토큰이 새지 않게 함
  PeerLink? linkForIncomingTransfer(FileTransfer transfer) {
    final direct = _links[transfer.conversationId];
    if (direct != null) return direct;
    final senderId = transfer.senderPeerId;
    if (senderId == null) return linkFor(transfer.conversationId);
    final senders = _roomLinks
        .where(
          (link) =>
              link.conversationId == transfer.conversationId &&
              !link.isClosed &&
              (link.remotePeerId ?? link.peerAlias) == senderId,
        )
        .toList();
    if (senders.length == 1) return senders.single;
    // 앱 멤버는 같은 peerId 링크가 둘이면(재접속 직후 옛 링크가
    // 아직 안 닫힘) 가장 최근 링크로 (방 offer 라우팅과 같은
    // 규칙)
    // 웹 게스트는 alias만 겹칠 뿐 같은 사람이라는 근거가 없어 못 좁히면 null
    final latest = senders.lastOrNull;
    return latest != null && latest.remotePeerId != null ? latest : null;
  }

  // linkFor의 다중 수신자판: 호스트 중계 방이면 붙어있는 멤버별 링크(멤버당
  // 가장 최근 하나), 1:1이면 linkFor와 같은 걸 최대 한 개짜리 리스트로
  // linkFor는 멤버가 둘 이상이면 모호해서 null인데(파일 전송 라우팅용),
  // 그룹 파일 offer는 대상 전원에게 각자 나가야 해서 별도로 둠
  List<PeerLink> linksForTransfer(String conversationId) {
    final direct = _links[conversationId];
    if (direct != null) return <PeerLink>[direct];
    return _memberLinks(conversationId);
  }

  Iterable<String> get activeConversationIds => _links.keys;

  // 아직 PeerLink로 감싸지 못한(자원 소유자가 없는) 채널을 닫음: disposed/상한
  // 초과로 _register/acceptInbound가 등록을 거부할 때 씀
  // 소켓이 이미 죽었으면 조용히 무시
  Future<void> _closeAbandonedChannel(StreamChannel<dynamic> channel) async {
    try {
      await channel.sink.close();
    } on Object {
      // 이미 사라짐
    }
  }

  // conversationId 슬롯에 link를 채택함. 이미 다른(살아있는)
  // 링크가 있으면(재연결/재합류 경합) 그 늦은 shutdown이
  // 방금 등록된 새 링크의 online/typing 상태를 덮어쓰지 않게 markSuperseded 함
  void _adoptLink(String conversationId, PeerLink link) {
    final stale = _links[conversationId];
    if (stale != null && !identical(stale, link)) {
      stale.markSuperseded();
    }
    _links[conversationId] = link;
  }

  // host별 최근 인바운드 접속 시각 (RAM만). _admitInbound의 빈도 상한이 보고 _now는 테스트 seam이 바꿈
  final Map<String, List<DateTime>> _inboundAccepts =
      <String, List<DateTime>>{};
  DateTime Function() _now = DateTime.now;

  // 상한 검사를 통과해 첫 await 전에 예약했지만 아직 _links에 안 오른(세션을 만드는 중인) 미인증 접속
  // _admitInbound가 _links의 미인증 링크와 합쳐 동시 상한을 셈
  final Set<_InboundSlot> _inboundSlots = <_InboundSlot>{};

  // 테스트만 세팅: _register의 세션 생성을 바꿈 (지연/실패를 결정적으로). 프로덕션에선 null
  Future<CryptoSession> Function()? _debugCreateSession;
}

// connectToPeer/reconnect가 공유하는 실제 소켓 열기. 리터럴 IP/RFC1918만
// NetworkGuard.assertReachable이 통과시킴
// 8초 타임아웃 (원본 Future는 취소 안 되니 늦게 도착한 소켓은 바로 닫음). 성공하면 ping interval까지 걸어서 줌
// 상대 서버가 보내는 메시지도 다 모이기 전에 상한을 거는 채널로 돌려줌 (capped_socket.dart)
Future<StreamChannel<dynamic>> _dialPeerSocket(
  String host,
  int port, {
  required LargeMessageMode Function() mode,
}) async {
  if (NetworkGuard.parsePeerEndpoint(host, port) == null) {
    throw SecurityException('non-RFC1918 peer endpoint "$host:$port"');
  }
  final address = InternetAddress.tryParse(host);
  if (address == null) {
    throw SecurityException('peer host "$host" is not a literal IP');
  }
  NetworkGuard.assertReachable(address);

  CappedSocket? capped;
  final client = NetworkGuard.createPeerHttpClient(
    wrap: (socket) =>
        capped = CappedSocket(socket, (n) => wireBudget(n, mode())),
  );
  // WebSocket 업그레이드도 내부적으로 HTTP 요청 하나: 이 client의
  // connectionFactory가 최초 연결이든 리다이렉트로 튄 곳이든
  // 실제 소켓을 열 때마다 재검증함 (NetworkGuard.createPeerHttpClient 참고)
  final connecting = WebSocket.connect(
    'ws://${NetworkGuard.hostForUri(host)}:$port/ws',
    customClient: client,
  );
  try {
    final socket = await connecting.timeout(const Duration(seconds: 8));
    socket.pingInterval = kSocketPingInterval;
    return cappedChannel(socket, capped);
  } on Object {
    unawaited(connecting.then((s) => s.close(), onError: (_) {}));
    rethrow;
  } finally {
    client.close(force: true);
  }
}
