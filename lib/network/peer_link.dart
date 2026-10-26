import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/audit/attestation.dart' show canonicalAttestationWire;
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/path_safety.dart' show safeBasename;
import 'package:intragram/core/secure_bytes.dart' show constantTimeEquals;
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';
import 'crypto_engine.dart';
import 'peer_auth.dart';
import 'protocol.dart';
import 'org_auth.dart';
import 'room_integrity.dart';

part 'peer_link_inbound.dart';
part 'peer_link_auth.dart';
part 'peer_link_secure.dart';
part 'peer_link_dispatch.dart';
part 'peer_link_dispatch_file.dart';
part 'peer_link_outbound.dart';
part 'peer_link_outbound_file.dart';
part 'peer_link_authorization.dart';
part 'peer_link_authorization_wire.dart';
part 'peer_link_authorization_file.dart';
part 'peer_link_lifecycle.dart';
part 'peer_link_org.dart';
part 'peer_link_room_integrity.dart';

// (전송 id, 시도 id, 인증된 발신자 id). 지금 attempt·수신자가 맞는지는 registry가 봄
typedef FileControlCallback =
    void Function(String transferId, String attemptId, String actorId);

// 첫 유효 hello 한 번만 받음. app↔web 전환·두 번째 hello·다른 버전은 전부 close로 떨어짐
enum _LinkPhase { awaitingHello, handshaking, app, web, closed }

// 양방향 채널 하나 위의 살아 있는 1:1 링크 (프로덕션은 WebSocket, 테스트는 인메모리 페어). 다이얼했든 받았든 똑같이 핸드셰이크하고
// CryptoSession을 쥠. 브라우저 게스트는 web_hello로 평문(사설 LAN 전용)으로 떨어져 insecure로 표시됨. 프레임 일은 part 파일들이 나눠 맡음
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
    // 필드는 nullable(웹 게스트면 세션을 부숨)이지만 시작은 늘 진짜 세션이라 required
    // ignore: prefer_initializing_formals
    : _crypto = crypto;

  // 보통 불변. 웹 게스트가 web_hello를 보내면 레지스트리가 딱 한 번 포털 방으로 옮김 (그래서 같은 호스트 게스트끼리 보임)
  String conversationId;
  final StreamChannel<dynamic> channel;
  final InMemoryStore store;
  final AppIdentity identity;
  final String? remoteHost;
  final int? remotePort;

  // 이 기기 서버 리스닝 포트. hello에 실어서 상대가 파일을 다시 밀 때 accept가 본 ephemeral 포트 대신 이걸 다이얼함
  final int? localPort;
  final bool dialledByUs;

  // 재연결·기존 피어 재접속 때만 세팅. hello의 peerId가 다르면(DHCP로 다른 기기가 그 주소에 있음) 닫음: 예전 대화를 딴 기기에 조용히 안 이어붙임
  final String? expectedPeerId;

  // web_hello 처리 시점의 토큰을 콜백으로 읽음 (소켓 받을 때 복사해 두면 그 사이 포털을 꺼도 대기 링크가 통과함)
  final String? Function()? requiredWebToken;

  CryptoSession? _crypto;
  StreamSubscription<dynamic>? _subscription;
  _LinkPhase _phase = _LinkPhase.awaitingHello;

  // 방 역할. registry가 검증한 구조로만 markHostedMember/markWebGuest가 바꾸고 그 뒤 room_join/room_state는 거부됨.
  // direct → remoteHost는 정당한 room_join을 처음 인가할 때 한 번만 바뀜
  _RoomLinkRole _roomRole = _RoomLinkRole.direct;
  void markHostedMember() => _roomRole = _RoomLinkRole.localHostMember;
  void markWebGuest() => _roomRole = _RoomLinkRole.webGuest;

  // 핸드셰이크가 안 끝나면 끊는 워치독. 신원 증명이 끝나거나 web_hello를 받으면 취소
  Timer? _handshakeWatchdog;

  // 리스너가 다이얼러 auth를 기다리는 동안만 있음
  Future<void> Function(AuthOuter auth)? _awaitingAuth;

  String peerAlias = 'peer';
  String peerPlatform = 'Unknown';
  PeerTransport transport = PeerTransport.app;

  // 증명된 상대 peerId (공개키 해시). hello 전이거나 웹 게스트면 null
  String? remotePeerId;
  Uint8List? _remoteIdentityKey;
  Uint8List? get remoteIdentityKey => _remoteIdentityKey;

  bool _closed = false;

  // 내가 다이얼한 링크가 핸드셰이크에서 실패한 이유. 닫힐 때 '연결 끊김' 대신 이 줄을 남김
  SystemEventKind? _failReason;

  // 이 세션이 예전 확인을 이어받았는지. 그러면 상대 verify가 와도 '양쪽 다 확인' 줄은 안 남김 (바뀐 숫자는 아무도 다시 안 맞춤)
  bool _carried = false;

  // 여러 곳에서 close()를 불러도 진짜 정리 하나를 같이 기다림
  Future<void>? _closeFuture;

  // registry가 같은 대화에 새 링크를 채택했으면 true: 이 링크가 늦게 닫혀도 대화 상태(online·typing·끊김 줄)는 안 덮고
  // 소켓·구독·암호만 정리함
  bool _superseded = false;

  void markSuperseded() {
    _superseded = true;
    _stopOrgAttestation();
  }

  final List<Map<String, dynamic>> _pending = <Map<String, dynamic>>[];
  int _pendingBytes = 0;

  // 소켓에 쓴 내 메시지 중 ack 못 받은 id. 링크가 닫히면 failed로 내려서 다시 보내게 함
  final Set<String> _unacked = <String>{};

  // 큐에서 기다리거나 처리 중인 프레임 수·바이트. _pending과 합쳐 64개/1MiB 상한을 지킴
  int _inFlightFrames = 0;
  int _inFlightBytes = 0;

  int _outSeq = 0;
  bool _orgListening = false;
  bool _orgSending = false;
  String? _sentOrgDigest;
  int _orgChecks = 0;
  bool _orgVerifying = false;
  Map<String, dynamic>? _orgPending;

  // seq 배정 → seal → sink.add를 호출 순서대로 줄 세우는 큐
  Future<void> _sendQueue = Future<void>.value();

  // 마지막으로 인증 통과한 수신 seq. 이하면 리플레이·역행으로 보고 버림 (링크마다 새로 시작)
  int _lastSeenSeq = -1;

  // 파일 제어 콜백: 지금 attempt·수신자가 맞는지는 registry가 봄. pushToken은 상대가 발급한 POST /api/transfer 토큰 (push 전용)
  void Function(String id, String attemptId, String pushToken, String actorId)?
  onFileAccepted;
  FileControlCallback? onFileRejected;

  FileControlCallback? onFileCancelled;

  // EOF가 아니라 이 ACK(+EOF)로 완료를 정함
  FileControlCallback? onFileReceived;

  // ACK에 수신 영수증이 실려 오면 onFileReceived보다 먼저 불림 (검증·기록은 보내는 쪽 registry가 함)
  void Function(
    String id,
    String attemptId,
    String actorId,
    Map<String, dynamic>,
  )?
  onDeliveryReceipt;

  // 받는 쪽이 실패한 시도를 다시 받고 싶다고 함 (그 수신자에게만 재offer)
  FileControlCallback? onFileRetryRequested;

  // 호스트가 (전송, attempt)의 offer를 그 수신자에게 못 넘겼다고 알림 (방 멤버가 낸 전송)
  FileControlCallback? onFileUnavailable;

  // 자동 수락 대화에 offer가 오면 불림 (프롬프트 없이 수락)
  void Function(String transferId)? onAutoAcceptOffer;

  // 토큰 검증을 통과한 웹 게스트면 한 번 불림: 레지스트리가 포털 방으로 옮김
  void Function()? onWebGuestHello;

  // 인바운드 링크가 앱 피어로 밝혀지면 한 번 불림: 같은 host의 기존 대화가 있으면 그리로 옮김 (재연결)
  void Function()? onAppPeerIdentified;

  // 앱 피어 핸드셰이크가 끝나 secure가 되면 한 번 불림 (초대 흐름의 '증명 뒤 방에 넣기')
  void Function()? onSecure;

  // hello의 peerId를 거절할 이유 (차단, '내가 연 대화만 받기'). null이면 진행
  SystemEventKind? Function(String peerId)? refusePeer;

  // 방 멤버 링크만 있음: 인가된 inner 프레임을 받을 때마다 불려서 레지스트리가 다른 멤버에게 중계함
  void Function(Map<String, dynamic> innerJson)? onRoomFrame;
  bool Function(PeerLink, String, String, String)? authorizeRoomFileControl;

  // 멤버만: 호스트가 알린 방 앱 피어 id 목록 (room_join/room_state)
  void Function(List<String> peerIds)? onRoomRoster;

  // 정리가 다 끝나면 한 번 불림. 링크 자신을 넘겨서 호출부가 지금 맵 값과 같을 때만 지움 (늦게 닫힌 옛 링크가 새 링크를 안 지우게)
  void Function(PeerLink link)? onClosed;

  bool get isClosed => _closed;

  // 핸드셰이크가 끝나고 상대가 자기 peerId 주인임이 증명된 앱 링크
  bool get isSecure => _phase == _LinkPhase.app && (_crypto?.isReady ?? false);

  // 아직 핸드셰이크 중(앱 hello·키 교환, 웹 게스트 토큰 검증 전). 미인증 동시 상한에 씀
  bool get isPendingHandshake =>
      _phase == _LinkPhase.awaitingHello || _phase == _LinkPhase.handshaking;

  // 방 멤버별 SAS를 RoomMember로 옮길 때 씀 (대화 하나를 여러 링크가 나눠 써서 Conversation.sas로는 구분 안 됨)
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
    // 앱 링크는 우리 hello로 시작. 웹 게스트는 자기가 먼저 말하고, 인바운드는 누군지 알 때까지 기다림
    final crypto = _crypto;
    if (dialledByUs && crypto != null) {
      final idKey = identity.publicKey;
      if (idKey == null) {
        await _shutdown(); // 키 없는 신원은 증명을 못 함
        return;
      }
      _sendOuter(_helloFrame(crypto, idKey));
    }
  }

  Future<void> close() => _shutdown();
}
