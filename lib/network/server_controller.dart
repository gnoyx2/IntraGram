import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/core/secure_bytes.dart' show generateSecureToken;
import 'discovery_engine.dart';
import 'local_server.dart';

export 'server_controller/room_hints.dart';

part 'server_controller/state.dart';

class ServerController extends Notifier<ServerState> {
  LocalServer? _server;

  // 병렬 start 호출(앱 재개와 수동 새로고침이 겹침)이 각자 새 LocalServer를 만들어 하나가 영영 못 닫히는 걸 막음
  Future<void>? _startFuture;

  // stop/panic마다 증가. start가 await 사이에서 이 값이 바뀐 걸 보면
  // 늦은 자기 결과(서버 바인딩 등)를 스스로 정리하고 물러남
  int _generation = 0;

  // 사용자가 마지막으로 원한 상태 (start가 true, stop이 false).
  // ServerState.running(실제 바인딩 여부)과 다른 축이라
  // 네트워크 유실로 _stopTransport만 도는 동안엔 안 바뀜
  // refreshNetwork가 이걸 봐서, 수동 OFF/패닉 뒤 다음 네트워크 점검이나 앱 재개가 서버를 멋대로 다시 켜지 않게 함
  bool _desiredRunning = false;

  // foreground 동안만 도는 단일 네트워크 점검 타이머 (setForeground
  // 참고). 주기는 mDNS 재스캔 주기(kDiscoveryRefresh)와
  // 같은 20초 (관심사는 달라서 합치진 않되 굳이 다른 숫자를 새로 정할 이유도 없음)
  Timer? _networkCheckTimer;

  @override
  ServerState build() {
    ref.onDispose(() {
      _networkCheckTimer?.cancel();
      _server?.stop();
    });
    return const ServerState();
  }

  // foreground로 들어오면 즉시 한 번, 이후 _networkCheckInterval마다 refreshNetwork를 부름
  // (인터페이스 목록만 비교, 외부 ping/HTTP probe 없음). 백그라운드에선 타이머를 멈춤:
  // 모바일 OS가 어차피 일시정지시킬 수 있는 걸 영구 생존으로 포장하지 않음
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
    final registry = ref.read(linkRegistryProvider);
    final identity = ref.read(appIdentityProvider);
    final server = LocalServer(
      registry: registry,
      identity: identity,
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
        // stop/panic이 이 await 사이에 옴: 아무도 안 쓸 서버라 필드에 안 남기고 바로 닫음 (고아 서버 누수 지점)
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
      // 포털은 옵트인: 서버가 뜨는 것만으로 웹 게스트 토큰을 발급하지 않고 setPortalEnabled가 켤 때만 발급함
      state = ServerState(running: true, host: bound.host, port: bound.port);
      // 그룹 방 멤버가 이 기기에서 파일 바이트를 직접 당길 주소
      registry.localEndpoint = (host: bound.host, port: bound.port);
      await ref
          .read(discoveryControllerProvider.notifier)
          .start(identity: identity, port: bound.port);
      if (generation != _generation) {
        // 디스커버리 시작을 기다리는 사이에도 stop/panic이 올 수 있음: 방금 세운 상태를 두면 stop 뒤에 서버가
        // 다시 살아난 것처럼 보여서 직접 되돌림 (바깥 stop을 다시 부르면 generation을 한 번 더 올려서 안 씀)
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

  // 사용자/패닉이 명시적으로 끔: _desiredRunning을 내려서 이후 refreshNetwork가 되살리지 않게 함
  Future<void> stop() async {
    _desiredRunning = false;
    await _stopTransport();
  }

  // 실제 소켓/디스커버리 종료. 네트워크가 잠깐 사라지거나 주소가 바뀌어 refreshNetwork가 다시 묶을 때도 쓰는데,
  // 사용자가 명시 OFF한 게 아니라서 _desiredRunning은 그대로
  // 둬 네트워크가 돌아오면 되살릴 수 있게 함 외부에서 끄는 stop과 안 섞음
  Future<void> _stopTransport() async {
    _generation++; // 진행 중이던 start()가 스스로 정리하고 물러나게 함
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

  // 실제 바인드 주소가 바뀌었으면(또는 꺼져 있다가 다시 잡히면) 그 위에
  // 서버를 다시 올림 (옛 IP가 QR/파일 source에 남는 문제의 다른
  // 축)
  // 수동 OFF/패닉이면 _desiredRunning이 false라 손 안 댐 (없으면 OFF 직후
  // 다음 점검/앱 재개에 서버가 멋대로 켜짐). 네트워크 자체가 사라지면 transport만 내림:
  // 서버/mDNS는 인프라라 네트워크를 따라가는 게 맞고 피어 자동 재다이얼 금지 원칙(app.dart)과는
  // 별개
  Future<void> refreshNetwork({bool probeListener = false}) async {
    if (!_desiredRunning) return;
    final address = await NetworkGuard.localBindAddress();
    // 주소 조회 중 수동 OFF/패닉이 오면 이 refresh는 뒤늦게 서버를 못 켬
    if (!_desiredRunning) return;
    if (address == null) {
      if (state.running) await _stopTransport();
      return;
    }
    if (state.running && _server?.boundHost == address.address) {
      if (!probeListener || await _listenerAlive()) return;
    }
    if (state.running) await _stopTransport();
    if (!_desiredRunning) return; // transport 정리 중 수동 OFF가 들어올 수 있음
    await start();
  }

  // 내 서버 포트에 TCP로 붙어 봄. 앱이 정지된 사이 OS가 소켓을 거뒀으면 거절돼서 다시 띄움
  Future<bool> _listenerAlive() async {
    final host = _server?.boundHost;
    final port = _server?.boundPort;
    if (host == null || port == null) return false;
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 1),
      );
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    }
  }

  // 웹 포털(브라우저 게스트 입장) 옵트인 스위치. OFF는 토큰을 즉시 폐기하고 붙어있는 웹 게스트 링크도 전부 닫음
  // (폐기한 토큰으로 pending web_hello가 통과하는 창을 안 남김).
  // ON은 항상 새 256-bit RAM 토큰을 뽑음 서버가 꺼져 있으면 효과 없음
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
