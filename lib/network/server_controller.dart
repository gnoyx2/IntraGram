import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/core/secure_bytes.dart' show generateSecureToken;
import 'discovery_engine.dart';
import 'local_server.dart';

export 'server_controller/room_hints.dart';

part 'server_controller/state.dart';
part 'server_controller/listener.dart';

class ServerController extends Notifier<ServerState> {
  LocalServer? _server;

  // 병렬 start 호출(앱 재개와 수동 새로고침이 겹침)이 각자 새 LocalServer를 만들어 하나가 영영 못 닫히는 걸 막음
  Future<void>? _startFuture;

  // stop·패닉마다 오름. start가 await 뒤에 바뀐 걸 보면 늦은 결과를 스스로 치우고 물러남
  int _generation = 0;

  // 사용자가 원한 상태 (실제 바인드 여부인 running과 다름). 수동으로 끄거나 패닉 뒤엔 네트워크 점검이 서버를 멋대로 다시 안 켬
  bool _desiredRunning = false;

  // 포그라운드에서만 도는 네트워크 점검 타이머 (주기는 mDNS 재스캔과 같은 20초)
  Timer? _networkCheckTimer;

  // 테스트가 망 없음을 흉내낼 자리 (앱은 실제 인터페이스를 봄)
  @visibleForTesting
  static Future<InternetAddress?> Function() bindAddress =
      NetworkGuard.localBindAddress;

  @override
  ServerState build() {
    ref.onDispose(() {
      _networkCheckTimer?.cancel();
      _server?.stop();
    });
    return const ServerState();
  }

  // 포그라운드로 오면 바로 한 번, 그 뒤 주기마다 인터페이스만 비교함 (외부 ping 없음). 백그라운드에선 멈춤
  void setForeground(bool foreground) {
    if (!foreground) {
      _networkCheckTimer?.cancel();
      _networkCheckTimer = null;
      return;
    }
    // iOS는 정지된 앱의 리스닝 소켓을 거둘 수 있어서(TN2277) 복귀할 때만 내 포트가 살아 있는지 봄
    unawaited(refreshNetwork(probeListener: !kIsWeb && Platform.isIOS));
    _networkCheckTimer ??= Timer.periodic(kDiscoveryRefresh, (_) {
      unawaited(refreshNetwork());
    });
  }

  Future<void> start() {
    _desiredRunning = true;
    final existing = _startFuture;
    if (existing != null) return existing;
    if (state.running) return Future<void>.value();
    final generation = ++_generation;
    final future = _startLocked(generation);
    _startFuture = future;
    return future.whenComplete(() {
      if (identical(_startFuture, future)) _startFuture = null;
    });
  }

  Future<void> _startLocked(int generation) async {
    final permitted = await OsPrivacy.localNetworkPermission();
    if (!ref.mounted || generation != _generation) return;
    if (!permitted) {
      state = const ServerState(problem: ServerProblem.localNetworkDenied);
      return;
    }
    final address = await bindAddress();
    if (!ref.mounted || generation != _generation) return;
    final registry = ref.read(linkRegistryProvider);
    final identity = ref.read(appIdentityProvider);
    final server = LocalServer(
      registry: registry,
      identity: identity,
      bindAddress: address,
      onInboundError: (error, stack) {
        if (ref.mounted && generation == _generation) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'IntraGram network',
              context: ErrorDescription('registering an inbound WebSocket'),
            ),
          );
        }
      },
    );

    try {
      final bound = await server.start();
      if (generation != _generation) {
        // 그사이 stop·패닉이 옴: 아무도 안 쓸 서버라 바로 닫음
        await server.stop();
        return;
      }
      if (bound == null) {
        final address = await NetworkGuard.nonPrivateIpv4();
        if (generation != _generation) return;
        state = ServerState(
          problem: address == null
              ? ServerProblem.noNetwork
              : ServerProblem.notPrivate,
          address: address,
        );
        return;
      }
      _server = server;
      // 포털은 옵트인: 서버가 떠도 토큰은 setPortalEnabled가 켤 때만 뽑음
      state = ServerState(running: true, host: bound.host, port: bound.port);
      // 그룹 방 멤버가 이 기기에서 파일 바이트를 직접 당길 주소
      registry.localEndpoint = (host: bound.host, port: bound.port);
      await ref
          .read(discoveryControllerProvider.notifier)
          .start(identity: identity, port: bound.port);
      if (generation != _generation) {
        // 디스커버리를 기다리는 사이 stop·패닉이 옴: 방금 세운 걸 직접 되돌림 (stop을 다시 부르면 generation이 또 올라가서 안 씀)
        registry.localEndpoint = null;
        await ref.read(discoveryControllerProvider.notifier).stop();
        await server.stop();
        if (identical(_server, server)) _server = null;
      }
    } catch (e) {
      if (generation == _generation) {
        state = ServerState(problem: ServerProblem.failed, error: '$e');
        registry.localEndpoint = null;
      }
      await server.stop();
      if (identical(_server, server)) _server = null;
    }
  }

  // 사용자·패닉이 끔: 이후 네트워크 점검이 안 되살림
  Future<void> stop() async {
    _desiredRunning = false;
    await _stopTransport();
  }

  // 소켓·디스커버리만 내림. 네트워크가 잠깐 사라지거나 주소가 바뀔 때도 써서 _desiredRunning은 그대로 둠
  Future<void> _stopTransport() async {
    _generation++; // 도는 start가 알아서 물러남
    final registry = ref.read(linkRegistryProvider)..localEndpoint = null;
    await ref.read(discoveryControllerProvider.notifier).stop();
    // 서버를 닫아도 이미 넘겨받은(hijack된) 웹소켓은 살아 있어서, 토큰을 먼저 지우고 브라우저 게스트를
    // 직접 내보냄 (앱 피어의 종단 간 암호 링크는 서버와 따로라 그대로 둠)
    _server?.portalToken = null;
    await registry.disconnectWebGuests();
    await _server?.stop();
    _server = null;
    state = const ServerState();
  }

  Future<void> toggle() => state.running ? stop() : start();

  // 바인드 주소가 바뀌었거나 다시 잡히면 서버를 새로 올림 (옛 IP가 QR에 남지 않게). 수동으로 껐으면 손 안 댐.
  // 네트워크가 사라지면 transport만 내림 (서버·mDNS는 망을 따라가는 인프라라 피어 자동 재다이얼 금지와는 별개)
  Future<void> refreshNetwork({bool probeListener = false}) async {
    if (!_desiredRunning) return;
    final generation = _generation;
    final permitted = await OsPrivacy.localNetworkPermission();
    if (!ref.mounted || !_desiredRunning || generation != _generation) return;
    if (!permitted) {
      if (state.running) await _stopTransport();
      if (ref.mounted && _desiredRunning) {
        state = const ServerState(problem: ServerProblem.localNetworkDenied);
      }
      return;
    }
    final address = await bindAddress();
    // 주소 조회 중 수동 OFF/패닉이 오면 이 refresh는 뒤늦게 서버를 못 켬
    if (!_desiredRunning) return;
    if (address == null) {
      if (state.running) {
        await _stopTransport();
      } else if (state.problem == ServerProblem.localNetworkDenied) {
        // 설정에서 권한을 켜고 돌아왔는데 망이 없음: 거부 안내를 실제 이유(망 없음)로 바꿈
        await start();
      }
      return;
    }
    if (state.running && _server?.boundHost == address.address) {
      if (!probeListener || await _listenerAlive()) return;
    }
    if (state.running) await _stopTransport();
    if (!_desiredRunning) return; // transport 정리 중 수동 OFF가 들어올 수 있음
    await start();
  }

  // 포털 스위치. 끄면 토큰을 바로 버리고 웹 게스트 링크도 다 닫음 (대기 중인 web_hello도 못 지나감). 켜면 늘 새 256비트 토큰
  Future<void> setPortalEnabled(bool enabled) async {
    if (!state.running) return;
    final server = _server;
    if (server == null) return;
    if (!enabled) {
      server.portalToken = null;
      state = ServerState(
        running: state.running,
        host: state.host,
        port: state.port,
      );
      await ref.read(linkRegistryProvider).disconnectWebGuests();
      return;
    }
    final token = generateSecureToken();
    server.portalToken = token;
    state = state.copyWith(portalEnabled: true, portalToken: token);
  }
}

final serverControllerProvider =
    NotifierProvider<ServerController, ServerState>(ServerController.new);
