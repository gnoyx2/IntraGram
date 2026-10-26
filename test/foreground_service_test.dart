import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/foreground_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('intragram/foreground');
  late List<String> calls;

  setUp(() {
    calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  ForegroundService android() =>
      ForegroundService(channel: channel, isAndroid: true);

  test('start / stop hit the native channel on Android', () async {
    final service = android();
    await service.start();
    await service.stop();
    expect(calls, <String>['start', 'stop']);
  });

  test('does nothing off Android', () async {
    final service = ForegroundService(channel: channel, isAndroid: false);
    await service.start();
    await service.stop();
    expect(calls, isEmpty);
  });

  test('lifecycle: backgrounding starts the service when opted in', () async {
    final service = android();
    service.handleLifecycle(AppLifecycleState.paused, stayConnected: true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, <String>['start']);

    service.handleLifecycle(AppLifecycleState.resumed, stayConnected: true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, <String>['start', 'stop']);
  });

  test('lifecycle: backgrounding is a no-op when not opted in', () async {
    final service = android();
    service.handleLifecycle(AppLifecycleState.paused, stayConnected: false);
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
  });

  test(
    'lifecycle: resuming with the setting off still clears any service',
    () async {
      final service = android();
      service.handleLifecycle(AppLifecycleState.resumed, stayConnected: false);
      await Future<void>.delayed(Duration.zero);
      expect(calls, <String>['stop']);
    },
  );

  test('onTimedOut fires when the native side reports an FGS timeout', () async {
    final service = android();
    var timedOut = false;
    service.onTimedOut = () => timedOut = true;

    // 네이티브(ConnectionService.onTimeout)가 이 채널로 부르는 걸 흉내냄. 평소 mock 방향(Dart→플랫폼)과 반대라 binaryMessenger로 직접 넣음
    final message = channel.codec.encodeMethodCall(
      const MethodCall('onTimeout'),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, message, (_) {});

    expect(timedOut, isTrue);
    expect(service.stoppedBySystem.value, isTrue);
  });

  // 설정이 저절로 꺼진 이유를 설정 화면이 보여 줄 수 있게 표시가 남음
  test('a refused start marks the service as stopped by the system', () async {
    final service = ForegroundService(channel: channel, isAndroid: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'foreground_start_failed'),
        );
    var failed = false;
    service.onStartFailed = () => failed = true;

    expect(await service.start(), isFalse);
    expect(failed, isTrue);
    expect(service.stoppedBySystem.value, isTrue);
  });
}
