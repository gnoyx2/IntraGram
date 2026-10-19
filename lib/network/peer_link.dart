import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/secure_bytes.dart' show constantTimeEquals;
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';
import 'crypto_engine.dart';
import 'peer_auth.dart';
import 'protocol.dart';

part 'peer_link_inbound.dart';
part 'peer_link_auth.dart';
part 'peer_link_secure.dart';
part 'peer_link_dispatch.dart';
part 'peer_link_dispatch_file.dart';
part 'peer_link_outbound.dart';
part 'peer_link_outbound_file.dart';
part 'peer_link_authorization.dart';
part 'peer_link_authorization_file.dart';
part 'peer_link_lifecycle.dart';

// (전송 id, 그 프레임이 가리키는 시도 id, 인증된 발신자 id). 현재 attempt/수신자 검사는 registry가 함
typedef FileControlCallback =
    void Function(String transferId, String attemptId, String actorId);

// 최초 유효 hello 한 번만 허용하고 app<->web 전환/후속 hello/구버전은 전부
// close로 떨어지는 상태 기계 (_PeerLinkInbound._onFrame 참고)
enum _LinkPhase { awaitingHello, handshaking, app, web, closed }

// 단일 양방향 채널 위의 살아있는 1:1 링크 (프로덕션은 WebSocket, 테스트는 인메모리 페어). 소켓을 다이얼했든 받았든
// 대칭으로 핸드셰이크, CryptoSession 소유, 인바운드 프레임의 스토어 반영, 타입 지정 send API를 담당
// 브라우저 게스트는 web_hello로 자기를 알리고 평문 프레이밍(사설 LAN 전용)으로
// 떨어져 UI에서 insecure로 표시됨. 프레임 작업은 part 파일들이 나눠 맡음
class PeerLink {
  PeerLink({
    required this.conversationId,
    required this.channel,
    required this.store,
    required this.identity,
    required CryptoSession crypto,
    this.remoteHost,
    this.remotePort,
    this.localPort,
    this.dialledByUs = false,
    this.expectedPeerId,
    this.requiredWebToken,
  })
    // nullable 필드지만 (웹 게스트 핸드셰이크가 세션을 부숨) 생성은
    // 항상 진짜 세션으로 시작해서 required non-null 파라미터
    // ignore: prefer_initializing_formals
    : _crypto = crypto;

  // 보통은 불변. 유일한 예외: 웹 게스트가 web_hello를 보내면 레지스트리가
  // 이 링크를 임시 1:1 대화에서 공유 포털 룸으로 딱 한 번 옮김
  // (프레임 디스패치 시작 전에). 그래서 같은 앱에 붙은 브라우저 게스트끼리 서로 보임
  String conversationId;
  final StreamChannel<dynamic> channel;
  final InMemoryStore store;
  final AppIdentity identity;
  final String? remoteHost;
  final int? remotePort;

  // 이 기기 서버의 리스닝 포트. hello에 실어서 피어가 (TCP accept가 보는 우리 아웃바운드 ephemeral 포트가 아니라)
  // 파일을 다시 밀 때 다이얼할 실제 포트를 알게 함
  final int? localPort;
  final bool dialledByUs;

  // 재연결/기존 피어 재접속에서만 세팅. hello의 peerId가 다르면(DHCP
  // 재할당 등으로 다른 기기가 그 자리에 있음) 링크를 닫음:
  // 예전 대화를 새 기기에 조용히 이어붙이지 않음
  final String? expectedPeerId;

  // web_hello 처리 시점의 RAM 토큰을 읽음. 소켓 접수 시점의 토큰을
  // 복사하면 그 사이 포털 OFF가 돼도 대기 링크가 통과해서 콜백으로 조회
  final String? Function()? requiredWebToken;

  CryptoSession? _crypto;
  StreamSubscription<dynamic>? _subscription;
  _LinkPhase _phase = _LinkPhase.awaitingHello;

  // 방 역할. registry가 검증한 topology로만 markHostedMember/markWebGuest가
  // 바꾸고 그 뒤로 room_join/room_state는 거부됨
  // direct -> remoteHost는 _PeerLinkAuthorization이
  // 최초 정당한 room_join 처리 때 한 번만 스스로 함
  _RoomLinkRole _roomRole = _RoomLinkRole.direct;
  void markHostedMember() => _roomRole = _RoomLinkRole.localHostMember;
  void markWebGuest() => _roomRole = _RoomLinkRole.webGuest;

  // 소켓은 붙었는데 핸드셰이크가 안 끝나면 링크를 끊는 워치독. 신원 증명이 끝난 앱 피어 또는 web_hello(게스트)에서 취소됨
  Timer? _handshakeWatchdog;

  // 리스너가 다이얼러의 auth(신원 증명)를 기다리는 동안만 세팅 (_PeerLinkAuth._onPeerHello)
  Future<void> Function(AuthOuter auth)? _awaitingAuth;

  String peerAlias = 'peer';
  String peerPlatform = 'Unknown';
  PeerTransport transport = PeerTransport.app;

  // 상대의 안정적 기기 식별자(hello의 peerId). IP보다 안정적이라
  // 방 멤버 재합류 매칭에 씀 (onAppPeerIdentified)
  // 앱 피어 hello 전이거나 웹 게스트면 null
  String? remotePeerId;

  bool _closed = false;

  // 내가 다이얼한 링크가 핸드셰이크에서 실패한 이유. 닫힐 때 '연결 끊김' 대신 이 줄을 남김
  SystemEventKind? _failReason;

  // 이 세션이 예전 확인을 이어받았는지(_carryVerification). 그러면 상대 verify가 와도 '양쪽 다 코드를 확인'
  // 줄은 안 남김: 바뀐 숫자는 아무도 다시 맞추지 않았음
  bool _carried = false;

  // _shutdown이 반환하는 Future를 캐싱해서 동시에 여러 호출자가
  // close()를 불러도(내부 에러 경로 + 외부 close 등)
  // 전부 실제 cleanup 완료 하나를 같이 기다림
  Future<void>? _closeFuture;

  // registry가 이 링크를 conversationId 소유권에서
  // 밀어내면(재연결/재합류 경합으로 같은 대화에 새 링크가 채택) true
  // 이후 닫혀도 이미 최신이 아닌 conversation
  // 상태(online/typing/disconnected)를 안 덮어쓰고 소켓/구독/크립토 정리만 함
  bool _superseded = false;

  void markSuperseded() => _superseded = true;

  final List<Map<String, dynamic>> _pending = <Map<String, dynamic>>[];
  int _pendingBytes = 0;

  // 이 링크로 소켓에 쓴 내 메시지 중 상대 ack가 아직 안 온 id. 링크가 닫히면 failed로 내려 재시도하게 함
  final Set<String> _unacked = <String>{};

  // _sendInner가 호출 시점에 예약하고 완료 시 해제하는 카운터.
  // 핸드셰이크 끝난 뒤 _sendQueue에서 대기/처리 중인 프레임도
  // _pending과 합쳐 64 frames/1MiB 상한을 안 넘게 함
  int _inFlightFrames = 0;
  int _inFlightBytes = 0;

  // 아웃바운드 enc 프레임 카운터 (0부터 전송마다 증가)
  int _outSeq = 0;

  // 아웃바운드 send를 seq 배정 -> seal -> sink.add 순서
  // 그대로 직렬화하는 큐 (PeerLinkOutbound._sendInner 참고)
  Future<void> _sendQueue = Future<void>.value();

  // 마지막으로 인증(복호화 성공) 통과한 인바운드 seq. 이보다 작거나 같은 seq는 리플레이/역행으로 보고 버림
  // 링크(= 크립토 세션)는 재연결마다 새로 만들어져서 자연 리셋됨
  int _lastSeenSeq = -1;

  // 파일 제어 콜백들: 현재 attempt/수신자 일치 검사는 registry가 하고 어긋나면 상태를 안 건드림
  // 수락의 pushToken은 피어가 발급한 POST /api/transfer 인가 토큰 (push에서만 씀)
  void Function(String id, String attemptId, String pushToken, String actorId)?
  onFileAccepted;
  FileControlCallback? onFileRejected;

  // 피어가 진행 중이거나 아직 안 끝난 전송(아웃고잉/인커밍)을 무름
  FileControlCallback? onFileCancelled;

  // 아웃고잉 전송 완전 확인: EOF가 아니라 ACK가 (EOF와 함께) 완료를 결정함
  FileControlCallback? onFileReceived;

  // 받는 쪽이 실패한 시도를 다시 받고 싶다는 요청 (그 수신자에게만 재offer)
  FileControlCallback? onFileRetryRequested;

  // 호스트가 (전송, attempt)의 offer를 세 번째 인자 수신자에게 못 넘겼다고 알림 (방 멤버가 낸 전송)
  FileControlCallback? onFileUnavailable;

  // 자동 수락으로 표시한 대화에 인커밍 제안이 오면 호출됨 (레지스트리가 프롬프트 없이 수락)
  void Function(String transferId)? onAutoAcceptOffer;

  // 이 링크가 웹 게스트(web_hello, 토큰 검증 통과)로 판명되면 딱 한 번 호출됨
  // 레지스트리가 이 링크를 공유 방으로 옮겨 같은 호스트의 게스트끼리 한 방에서 대화하게 함
  void Function()? onWebGuestHello;

  // 인바운드 링크가 hello로 앱 피어임을 밝히면 한 번 호출됨 (다이얼한 쪽은 이미 host로 dedupe해서 세팅 안 함)
  // 레지스트리가 같은 host의 기존 대화가 있으면 이 링크를 거기로 옮김 (피어 재연결, 예: 무선 디버깅 끊김)
  void Function()? onAppPeerIdentified;

  // 앱 피어 핸드셰이크가 끝나 secure 상태가 되면 한 번 호출됨 (레지스트리가
  // inviteToRoom 흐름에서 "secure 되면 방에 넣기"에 씀)
  void Function()? onSecure;

  // hello의 peerId를 거절할 이유 (차단, '내가 연 대화만 받기'). null이면 진행
  SystemEventKind? Function(String peerId)? refusePeer;

  // 이 링크가 방 멤버일 때만 세팅 (레지스트리가 방 합류 시). inner 프레임이 도착할 때마다 파싱된 JSON으로 호출되고
  // 레지스트리가 같은 방의 다른 멤버에게 중계함 (호스트 허브 역할). 1:1 링크엔 없어서 중계 없음
  void Function(Map<String, dynamic> innerJson)? onRoomFrame;
  bool Function(PeerLink, String, String, String)? authorizeRoomFileControl;

  // 멤버만: 호스트가 알린 방의 앱 피어 id 목록 갱신 (room_join/room_state)
  void Function(List<String> peerIds)? onRoomRoster;

  // 링크가 완전히 정리되면 한 번 호출됨. PeerLink 자신을 넘겨서 호출부가 현재 맵 값과 identical일 때만 제거하게 함
  // (대체된 옛 링크의 뒤늦은 종료가 방금 등록된 새 링크를 지우지 않게)
  void Function(PeerLink link)? onClosed;

  bool get isClosed => _closed;

  // 핸드셰이크가 끝나고 상대가 자기 peerId를 가진 쪽임이 증명된 앱 링크
  bool get isSecure => _phase == _LinkPhase.app && (_crypto?.isReady ?? false);

  // 핸드셰이크가 안 끝난 링크(앱 피어 hello/키교환 중, 또는 웹 게스트
  // 토큰 검증 전)면 true: registry의 동시 미인증 연결 상한에
  // 씀
  bool get isPendingHandshake =>
      _phase == _LinkPhase.awaitingHello || _phase == _LinkPhase.handshaking;

  // 핸드셰이크 전이거나 웹 게스트면 null. 방 멤버별 SAS를 _LinkRegistryRoom이
  // RoomMember.sas로 옮겨 적을 때 씀
  // (여러 멤버 링크가 대화 하나를 공유해서 Conversation.sas만으론 구분 못 함)
  String? get sasDigits => _crypto?.sasDigits;

  Future<void> start() async {
    _subscription = channel.stream.listen(
      _onRawFrame,
      onError: (_) => _shutdown(),
      onDone: _shutdown,
      cancelOnError: false,
    );
    _handshakeWatchdog = Timer(kHandshakeTimeout, () {
      if (!_closed && isPendingHandshake) {
        _failReason ??= SystemEventKind.handshakeTimedOut;
        _shutdown();
      }
    });
    // 앱 링크는 우리 hello로 시작. 웹 게스트는 자기가 먼저 말하고(web_hello),
    // 인바운드 소켓은 어떤 피어인지 알 때까지 기다림
    final crypto = _crypto;
    if (dialledByUs && crypto != null) {
      final idKey = identity.publicKey;
      if (idKey == null) {
        await _shutdown(); // 키 없는 신원은 신원 증명을 못 해서 앱 피어 링크를 못 맺음
        return;
      }
      _sendOuter(_helloFrame(crypto, idKey));
    }
  }

  // 종료 로직(프레임 pause/resume, _shutdown 멱등 캐싱,
  // cleanup)은 peer_link_lifecycle.dart에 있음
  Future<void> close() => _shutdown();
}
