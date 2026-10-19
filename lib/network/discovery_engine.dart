import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/store/models.dart';

part 'discovery_engine/broadcast.dart';
part 'discovery_engine/scan.dart';

// 유저 동작 전에 도는 유일한 네트워크 동작이지만 링크를 안 벗어남 (mDNS는 224.0.0.251 멀티캐스트라 라우터가 전달 안 함)
// 광고를 멈춘 피어(앱 종료, 네트워크 이탈)는 목록에서 빠짐
// _DiscoveryBroadcast(광고)와 _DiscoveryScan(스캔, stale sweep) part로 나뉘고,
// 이 파일엔 라이프사이클(start/stop/refresh)과 상태 필드만 남음
class DiscoveryController extends Notifier<List<PeerDevice>> {
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  Timer? _staleSweep;

  // peerId로 키: mDNS 서비스 name엔 alias가 박혀 있어
  // rename마다 바뀜. name으로 키하면 rename마다 새 항목이 생겨
  // 옛 항목이 goodbye나 _sweepStale(최대 60초)까지 랜덤 alias로 남아 방 초대 목록에 두 항목이 뜨던 문제가 있음
  // peerId는 불변이라 rename이 같은 자리를 덮어씀
  final Map<String, PeerDevice> _peers = <String, PeerDevice>{};
  // peerId -> 현재 서비스 name. ServiceLostEvent는 name만 주므로 그 name이 지금도 최신일 때만 지움
  // (rename으로 밀려난 옛 이름의 뒤늦은 goodbye가 방금 갱신된 항목을 지우는 걸 막음)
  final Map<String, String> _serviceNames = <String, String>{};
  String? _selfPeerId;

  // 재브로드캐스트에 필요한 마지막 start 인자 + 현재 방 호스팅 여부
  AppIdentity? _identity;
  int? _port;
  bool _hostsRoom = false;

  // 호스트든 멤버든 지금 방 안에 있는지. _hostsRoom은 "탭하면 합류"만 뜻해서 멤버는 안 켜지므로
  // 멤버 기기도 "방 참여 중"이 뜨게 따로 둠
  bool _inRoom = false;

  @override
  List<PeerDevice> build() {
    ref.onDispose(stop);
    return const <PeerDevice>[];
  }

  bool get isRunning => _discovery != null;

  // stop/start마다 증가. _restartScan이 async 경합 중 이 값이 바뀐 걸 보면 방금 만든 것도 버리고 물러남
  int _generation = 0;

  // 다시 불러도 안전 (예: 서버 포트가 바뀐 뒤 재시작)
  Future<void> start({required AppIdentity identity, required int port}) async {
    await stop();
    final generation = _generation;
    _selfPeerId = identity.peerId;
    _identity = identity;
    _port = port;

    // mDNSResponder 데몬 연결이 막 죽은 순간(Wi-Fi 갈아탄 직후 실기기에서
    // DefunctConnection PlatformException으로 관찰)엔
    // initialize() 자체가 던짐. 못 잡으면 앱 전체가 죽음. 광고 실패는 삼키고 다음 start 재호출이 복구함
    BonsoirBroadcast? broadcast;
    try {
      broadcast = BonsoirBroadcast(service: _service(identity, port));
      await broadcast.initialize();
      await broadcast.start();
      if (generation != _generation) {
        await broadcast.stop();
        return;
      }
      _broadcast = broadcast;
    } on Object {
      // initialize()는 됐는데 start()가 던진 경우 등: 반쯤 만든 인스턴스를 안 남김
      await broadcast?.stop();
      _broadcast = null;
    }

    await _restartScan(generation);
    if (generation != _generation) return;
    _staleSweep = Timer.periodic(kDiscoveryRefresh, (_) => _sweepStale());
  }

  Future<void> stop() async {
    _generation++; // 진행 중이던 start()/refresh()가 스스로 정리하고 물러남
    _staleSweep?.cancel();
    _staleSweep = null;
    await _subscription?.cancel();
    _subscription = null;
    await _discovery?.stop();
    _discovery = null;
    await _broadcast?.stop();
    _broadcast = null;
    _peers.clear();
    _serviceNames.clear();
    if (ref.mounted) state = const <PeerDevice>[];
  }

  // 브라우즈 스트림만 재시작 (광고와 현재 피어 목록은 안 건드림): mDNS 리스폰더가 스캔을 놓았을 때의 안전장치
  // 사라진 피어는 _staleSweep이 걸러냄. start가 한 번도 안 불려 identity가 없으면 no-op
  // isRunning(_discovery != null)은 안 봄: 이전 시도가 실패해 스캐너가 죽은 상태에서도 재시작을 시도함
  // (죽은 스캐너 위에서 새로고침 버튼이 무력했던 문제)
  Future<void> refresh() async {
    if (_identity == null) return;
    await _restartScan(_generation);
  }

  // start/refresh가 공유하는 브라우즈 스트림 (재)생성 본체. 실패하면 만들다 만 구독/Bonsoir 인스턴스까지 정리하고
  // 필드에 안 남김. async 경합 중 stop/새 start가 오면(generation 불일치) 방금 만든 것도 즉시 버림
  Future<void> _restartScan(int generation) async {
    if (generation != _generation) return;
    await _subscription?.cancel();
    _subscription = null;
    await _discovery?.stop();
    _discovery = null;

    // 같은 DefunctConnection이 스캔 쪽에서도 터질 수 있어서 한 번 실패하면 잠깐 쉬었다 새 인스턴스로 한 번 더 시도함
    // 그래도 안 되면 광고(내 존재감)는 유지한 채 스캔만 포기. 실패를 삼키지만 isRunning이 false로 남아 호출부가 안 속음
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

  // room=1 TXT를 넣거나 빼서 광고를 다시 뿌림 (광고 중일 때만)
  // 한계: bonsoir엔 라이브 TXT 업데이트 API가 없어서 브로드캐스트를 재시작함. 그 순간 다른 피어 목록에서
  // 이 기기가 사라졌다 다시 뜸. room 힌트는 부가 정보라 감수함 (스캔은 안 건드림)
  Future<void> setHostsRoom(bool value) async {
    if (value == _hostsRoom) return;
    _hostsRoom = value;
    await _restartBroadcast();
  }

  // setHostsRoom과 같은 깜빡임 트레이드오프
  Future<void> setInRoom(bool value) async {
    if (value == _inRoom) return;
    _inRoom = value;
    await _restartBroadcast();
  }

  // 새 이름으로 광고를 다시 뜸 (setHostsRoom과 같은 깜빡임 트레이드오프)
  Future<void> restartBroadcast() => _restartBroadcast();

  // ref/state가 Riverpod의 @protected 멤버라
  // extension(_DiscoveryScan)에선 직접 못 건드려서 이 메서드만 클래스 본체에 둠
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
