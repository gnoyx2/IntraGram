import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart' show addTearDown;

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/foreground_service.dart';
import 'package:intragram/core/identity_store.dart';
import 'package:intragram/core/notifications.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/registry/incoming_session_files.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/vault.dart';

void mockDirectorySettings() {
  final dir = Directory.systemTemp.createTempSync('intragram_widget_settings_');
  IncomingSessionFiles.settingsFileForTesting = File(
    '${dir.path}/download_directories.json',
  );
  addTearDown(() {
    IncomingSessionFiles.settingsFileForTesting = null;
    dir.deleteSync(recursive: true);
  });
}

// 위젯 FakeAsync에서 실제 앱 경로를 찾지 않고 패닉 순서만 검증함
class PanicVault extends Vault {
  @override
  Future<bool> isEncrypted() async => false;

  @override
  Future<VaultSnapshot?> load({String? pin}) async => null;

  @override
  Future<void> erase() async {}
}

class PanicIdentityStore extends IdentityStore {
  const PanicIdentityStore();

  @override
  Future<String?> loadAlias() async => null;

  @override
  Future<void> clear() async {}
}

// 패닉 정지 단계를 테스트가 직접 쥐는 Completer 묶음: 진짜 시간/플랫폼 채널에
// 기대지 않아서 위젯 테스트(FakeAsync)에서도 pump만으로 결정적으로 돎
// (진짜 이벤트 루프 턴이 필요한 native 채널 응답을 기다리다 300초씩 멈추던 원인을 없앰)
class PanicSteps {
  final calls = <String>[];
  final voice = Completer<void>();
  final notifications = Completer<void>();
  final foreground = Completer<bool>();
  final server = Completer<void>();
  final links = Completer<void>();
  final native = Completer<void>();

  void completeAllExceptLinks() {
    if (!voice.isCompleted) voice.complete();
    if (!notifications.isCompleted) notifications.complete();
    if (!foreground.isCompleted) foreground.complete(true);
    if (!server.isCompleted) server.complete();
  }

  void completeAll() {
    completeAllExceptLinks();
    if (!links.isCompleted) links.complete();
    if (!native.isCompleted) native.complete();
  }
}

class PanicNotifications extends NotificationService {
  PanicNotifications(this.steps);
  final PanicSteps steps;

  @override
  Future<void> init() async {}

  @override
  Future<void> cancelAll() {
    steps.calls.add('notifications');
    return steps.notifications.future;
  }
}

class PanicForeground extends ForegroundService {
  PanicForeground(this.steps) : super(isAndroid: false);
  final PanicSteps steps;

  @override
  Future<bool> stop() {
    steps.calls.add('foreground');
    return steps.foreground.future;
  }
}

class PanicServer extends ServerController {
  PanicServer(this.steps);
  final PanicSteps steps;

  @override
  Future<void> stop() {
    steps.calls.add('server');
    return steps.server.future;
  }
}

// disposeAll이 PanicSteps.links를 기다리는 registry. delegate가 켜지면
// 진짜 정리(LinkRegistry.disposeAll)를 탐 (실제 전송/.part 정리 검증용)
class PanicRegistry extends LinkRegistry {
  PanicRegistry(
    this.steps, {
    required super.store,
    super.chooseDirectory,
    AppIdentity? identity,
  }) : super(
         crypto: CryptoEngine(),
         identity:
             identity ??
             AppIdentity(peerId: '1' * 32, alias: 'me', platform: 'test'),
       );

  final PanicSteps steps;
  bool delegate = false;

  @override
  Future<void> disposeAll() {
    steps.calls.add('links');
    if (delegate) return super.disposeAll();
    return steps.links.future;
  }
}
