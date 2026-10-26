import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/network/protocol.dart' show wirePlatform;
import 'package:intragram/store/models.dart';

part 'discovery_engine/broadcast.dart';
part 'discovery_engine/scan.dart';

// 사용자가 뭘 하기 전에 도는 유일한 네트워크 일이지만 링크 밖으론 안 나감 (mDNS 224.0.0.251은 라우터가 안 넘김).
// 광고를 멈춘 피어(앱 종료, 망 이탈)는 목록에서 빠짐
class DiscoveryController extends Notifier<List<PeerDevice>> {
  BroadcastSession? _broadcast;
  _BroadcastSpec? _activeBroadcastSpec;
  Future<void> _broadcastSerial = Future<void>.value();
  bool _advertising = false;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  Timer? _staleSweep;

  // 테스트가 가짜 광고 핸들을 끼워 동시 재시작·정지 순서를 검증할 자리 (앱은 BonsoirBroadcast 사용)
  @visibleForTesting
  static BroadcastSession Function(BonsoirService service) createBroadcast =
      _BonsoirBroadcastSession.new;

  // peerId로 키: 서비스 name엔 alias가 들어가서 이름을 바꿀 때마다 새 항목이 생겨 옛 이름이 최대 60초 같이 떴음
  final Map<String, PeerDevice> _peers = <String, PeerDevice>{};
  // peerId → 지금 서비스 name. Lost 이벤트는 name만 줘서 그게 최신일 때만 지움 (옛 이름의 늦은 goodbye가 새 항목을 못 지우게)
  final Map<String, String> _serviceNames = <String, String>{};
  String? _selfPeerId;

  // 광고를 다시 뿌릴 때 쓰는 마지막 start 인자와 방 상태
  AppIdentity? _identity;
  int? _port;
  bool _hostsRoom = false;

  // 호스트든 멤버든 방 안인지. _hostsRoom은 '탭하면 합류'라 멤버는 안 켜져서 따로 둠
  bool _inRoom = false;

  @override
  List<PeerDevice> build() {
    ref.onDispose(stop);
    return const <PeerDevice>[];
  }

  bool get isRunning => _discovery != null;

  // stop·재시작마다 오름. 그사이 바뀌었으면 방금 만든 것도 버리고 물러남
  int _generation = 0;

  // 다시 불러도 안전 (예: 서버 포트가 바뀐 뒤 재시작)
  Future<void> start({required AppIdentity identity, required int port}) async {
    final generation = ++_generation;
    await _stopInternal(bumpGeneration: false);
    if (generation != _generation) return;
    _selfPeerId = identity.peerId;
    _identity = identity;
    _port = port;
    _advertising = true;

    await _syncBroadcast();
    if (generation != _generation) return;

    await _restartScan(generation);
    if (generation != _generation) return;
    _staleSweep = Timer.periodic(kDiscoveryRefresh, (_) => _sweepStale());
  }

  Future<void> stop() => _stopInternal(bumpGeneration: true);

  Future<void> _stopInternal({required bool bumpGeneration}) async {
    if (bumpGeneration) _generation++; // 도는 start·refresh가 알아서 물러남
    _advertising = false;
    _identity = null;
    _port = null;
    _staleSweep?.cancel();
    _staleSweep = null;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _discovery?.stop();
    } finally {
      _discovery = null;
      await _syncBroadcast();
    }
    _peers.clear();
    _serviceNames.clear();
    if (ref.mounted) state = const <PeerDevice>[];
  }

  // 스캔만 다시 시작 (광고·목록은 그대로): mDNS 리스폰더가 스캔을 놓쳤을 때용. isRunning은 안 봄 (죽은 스캐너도 새로고침이 되살려야 함)
  Future<void> refresh() async {
    if (_identity == null) return;
    await _restartScan(_generation);
  }

  // 스캔 (재)생성. 실패하면 만들다 만 구독·인스턴스까지 치우고, 그사이 stop이 오면 방금 만든 것도 버림
  Future<void> _restartScan(int generation) async {
    if (generation != _generation) return;
    await _subscription?.cancel();
    _subscription = null;
    await _discovery?.stop();
    _discovery = null;

    // 스캔에서도 DefunctConnection이 터질 수 있어서 1초 쉬고 한 번 더. 그래도 안 되면 광고는 두고 스캔만 포기 (isRunning이 false로 남음)
    var started = false;
    for (var attempt = 0; attempt < 2 && !started; attempt++) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 1));
      if (generation != _generation) return;
      BonsoirDiscovery? discovery;
      StreamSubscription<BonsoirDiscoveryEvent>? subscription;
      try {
        discovery = BonsoirDiscovery(type: kServiceType);
        await discovery.initialize();
        subscription = discovery.eventStream?.listen(
          _onEvent,
          onError: (Object _) => _onDiscoveryError(),
        );
        await discovery.start();
        if (generation != _generation) {
          await subscription?.cancel();
          await discovery.stop();
          return;
        }
        _subscription = subscription;
        _discovery = discovery;
        started = true;
      } on Object {
        await subscription?.cancel();
        await discovery?.stop();
      }
    }
  }

  // room=1·inRoom=1을 한 번에 갱신: 따로 부르면 광고 재시작이 두 번 겹쳐 Darwin mDNSResponder가 메인 스레드를 멈춤
  Future<void> setRoomHints({
    required bool hostsRoom,
    required bool inRoom,
  }) async {
    if (hostsRoom == _hostsRoom && inRoom == _inRoom) return;
    _hostsRoom = hostsRoom;
    _inRoom = inRoom;
    await _syncBroadcast();
  }

  // room=1 TXT를 넣거나 빼서 광고를 다시 뿌림. bonsoir엔 TXT만 바꾸는 API가 없어서 재시작이라 남의 목록에서 잠깐 깜빡임 (부가 정보라 감수)
  Future<void> setHostsRoom(bool value) =>
      setRoomHints(hostsRoom: value, inRoom: _inRoom);

  // setHostsRoom과 같은 깜빡임 트레이드오프
  Future<void> setInRoom(bool value) =>
      setRoomHints(hostsRoom: _hostsRoom, inRoom: value);

  // 새 이름으로 광고를 다시 뿌림 (같은 깜빡임)
  Future<void> restartBroadcast() => _syncBroadcast();

  // ref·state가 @protected라 extension에선 못 건드려서 이것만 클래스 본체에 둠
  void _publish() {
    if (!ref.mounted) return;
    final list = _peers.values.toList()
      ..sort((a, b) => a.alias.toLowerCase().compareTo(b.alias.toLowerCase()));
    state = List<PeerDevice>.unmodifiable(list);
  }
}

final discoveryControllerProvider =
    NotifierProvider<DiscoveryController, List<PeerDevice>>(
      DiscoveryController.new,
    );
