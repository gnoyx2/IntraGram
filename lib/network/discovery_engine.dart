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

  // peerId를 키로 사용함. 서비스 name에 alias가 포함되어 이름 변경 시 이전 이름이 최대 60초간 함께 남던 문제를 방지함
  final Map<String, PeerDevice> _peers = <String, PeerDevice>{};
  // peerId → 현재 서비스 name. Lost 이벤트는 name만 전달하므로 최신 name과 일치할 때만 삭제함 (이전 이름의 지연 goodbye 수신으로 새 항목이 삭제되는 현상을 방지함)
  final Map<String, String> _serviceNames = <String, String>{};
  String? _selfPeerId;

  // 광고를 다시 뿌릴 때 쓰는 마지막 start 인자와 방 상태
  AppIdentity? _identity;
  int? _port;
  bool _hostsRoom = false;

  // 호스트 또는 멤버로서 방 참여 여부임. _hostsRoom은 호스트 참여 유도용이라 일반 멤버 참여 상태와 구분하려 별도 관리함
  bool _inRoom = false;

  @override
  List<PeerDevice> build() {
    ref.onDispose(stop);
    return const <PeerDevice>[];
  }

  bool get isRunning => _discovery != null;

  // stop·재시작마다 오름. 그사이 바뀌었으면 방금 만든 것도 버리고 물러남
  int _generation = 0;

  // 다시 불러도 안전함 (예: 서버 포트가 바뀐 뒤 재시작)
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

  // 스캔만 다시 시작함 (광고·목록은 그대로 둠): mDNS 리스폰더가 스캔을 놓쳤을 때 사용함 (중단된 스캐너도 새로고침이 되살려야 함)
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

    // 스캔에서도 DefunctConnection이 발생할 수 있어 1초 대기 후 한 번 더 시도함. 그래도 실패하면 광고는 유지하고 스캔만 중단함
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
