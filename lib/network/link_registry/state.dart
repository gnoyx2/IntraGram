part of '../link_registry.dart';

abstract class _LinkRegistryState {
  _LinkRegistryState({
    required this.store,
    required this.crypto,
    required this.identity,
    Future<String?> Function(String suggestedName)? chooseDirectory,
    Duration ackTimeout = kFileReceivedAckTimeout,
  }) {
    // 증적(영수증·소각·정리)은 이 실행의 신원 키로 서명함 (키 없는 화면 테스트 신원이면 아무것도 안 남김)
    store.evidence.bindSigner(identity);
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
    // 여기 타이머가 메시지를 태우면 상대한테도 알림: 시계나 절전 상태가 어긋나도 양쪽이 같이 버림
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

  // disposeAll이 첫 await 전에 세움: 그 뒤 등록은 전부 거부. 다음 세션은 새 LinkRegistry로 시작
  bool _disposed = false;

  // disposeAll마다 오름. _register가 세션을 만들고 돌아왔을 때 값이 바뀌었으면(그사이 disposeAll) 늦은 채널·세션은 버림
  int _generation = 0;

  // 이 기기 서버의 사설 host:port (ServerController가 채우고 비움). 방 파일 offer에 찍어서 다른 멤버가 여기서 직접 당겨 감
  ({String host, int port})? localEndpoint;

  // 이번 실행에서 차단한 peerId. 신원 키가 실행마다 바뀌어서 RAM에만 둠
  final Set<String> _blockedPeers = <String>{};

  // hello의 peerId를 받을지: null이면 진행, 아니면 그 이유로 닫음
  SystemEventKind? _refusal(String peerId, {required bool dialledByUs});

  // 대화 하나 = 링크 하나 (내가 호스트인 방의 멤버·게스트 링크는 _roomLinks)
  final Map<String, PeerLink> _links = <String, PeerLink>{};

  // 내가 호스트인 방의 링크 전부. 웹 게스트 방과 앱 그룹 방 것이 섞여 있어서 늘 link.conversationId로 거름
  final List<PeerLink> _roomLinks = <PeerLink>[];

  // 호스트가 중계하는 방 파일 경로: (전송 id, attempt) → 낸 멤버·받을 멤버 링크. 링크가 닫히거나 attempt가 끝나면 지움
  final Map<(String, String), _RoomFileRoute> _roomFileRoutes = {};

  // 발신자당 미완료 경로 상한 (테스트만 낮춤)
  int _maxRoomFileRoutesPerSender = _kMaxRoomFileRoutesPerSender;

  // 테스트 전용: 소켓 다이얼 대신 인메모리 채널 (프로덕션은 null)
  Future<StreamChannel<dynamic>> Function(PeerDevice peer)? _debugDial;

  // 브라우저 게스트가 다 들어오는 방. 첫 게스트가 토큰을 통과하면 생기고 세션 소각까지 남음 (게스트 없으면 offline).
  // 앱 그룹 방과 따로라 웹 게스트는 앱 전용 방이나 1:1을 볼 길이 없음
  String? _webGuestRoomId;

  String? get portalRoomId => _webGuestRoomId;

  // 내가 호스트인 앱 그룹 방. inviteToRoom·addPeersToRoom이 만들거나 다시 씀
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
    // 내가 호스트인 방: 멤버가 딱 한 명일 때만 그 링크. 여럿이면 모호해서 null (방 파일은 linksForTransfer로 감)
    final inRoom = _memberLinks(conversationId);
    return inRoom.length == 1 ? inRoom.single : null;
  }

  // 받는 전송의 accept·reject·cancel·retry·ACK를 돌려보낼 발신자 링크. 내가 호스트인 방이면 senderPeerId로 고름
  // (웹 게스트는 peerId가 없어 alias). 못 좁히면 null: 엉뚱한 게스트한테 push 토큰이 새면 안 됨
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
    // 앱 멤버는 같은 peerId 링크가 둘이면(재접속 직후) 최신 것. 웹 게스트는 alias만 같을 뿐 같은 사람이란 근거가 없음
    final latest = senders.lastOrNull;
    return latest != null && latest.remotePeerId != null ? latest : null;
  }

  // linkFor의 여러 수신자판: 내가 호스트인 방이면 멤버마다 최신 링크 하나씩, 1:1이면 그 링크 하나 (방 파일 offer는 전원에게 따로 나감)
  List<PeerLink> linksForTransfer(String conversationId) {
    final direct = _links[conversationId];
    if (direct != null) return <PeerLink>[direct];
    return _memberLinks(conversationId);
  }

  Iterable<String> get activeConversationIds => _links.keys;

  // PeerLink가 되기 전에 거부한 채널을 닫음 (이미 죽은 소켓이면 무시)
  Future<void> _closeAbandonedChannel(StreamChannel<dynamic> channel) async {
    try {
      await channel.sink.close();
    } on Object {
      // 이미 사라짐
    }
  }

  // 자리에 다른 링크가 있으면(재연결 경합) 대체 표시: 옛 링크가 늦게 닫혀도 새 링크의 online·typing을 안 덮음
  void _adoptLink(String conversationId, PeerLink link) {
    final stale = _links[conversationId];
    if (stale != null && !identical(stale, link)) {
      stale.markSuperseded();
    }
    _links[conversationId] = link;
  }

  // host별 최근 인바운드 접속 시각 (RAM만). _admitInbound 빈도 상한용
  final Map<String, List<DateTime>> _inboundAccepts =
      <String, List<DateTime>>{};
  DateTime Function() _now = DateTime.now;

  // 검사를 통과해 예약했지만 아직 세션을 만드는 중이라 _links에 없는 미인증 접속. 동시 상한에 같이 셈
  final Set<_InboundSlot> _inboundSlots = <_InboundSlot>{};

  // 테스트 전용: 세션 생성을 바꿔 지연·실패를 재현 (프로덕션은 null)
  Future<CryptoSession> Function()? _debugCreateSession;
}

// 실제 소켓 다이얼. 리터럴 사설 IP만 통과. 8초 타임아웃 뒤 늦게 붙은 소켓은 바로 닫음 (Future는 취소가 안 됨).
// 상대가 보내는 메시지도 다 모이기 전에 상한을 거는 채널로 돌려줌
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
  // 업그레이드도 HTTP 요청이라 리다이렉트로 튄 곳까지 소켓을 열 때마다 이 client가 다시 검사함
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
