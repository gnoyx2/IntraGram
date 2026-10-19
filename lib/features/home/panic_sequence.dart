import 'dart:async';
import 'dart:io';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/foreground_service.dart';
import 'package:intragram/core/identity_store.dart';
import 'package:intragram/core/mobile_file_source.dart';
import 'package:intragram/core/notifications.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/core/temp_sweep.dart';
import 'package:intragram/core/voice_producer_registry.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/registry/incoming_session_files.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/in_memory_store.dart';

final class PanicStepFailure {
  const PanicStepFailure(this.step, {required this.timedOut, this.error});

  // 사용자 데이터/경로를 안 담는 고정 라벨이라 로그/화면에 그대로 써도 됨
  final String step;

  // kPanicStepTimeout 안에 안 끝나 기다리길 포기했으면 true. 그 Future는 취소 안 되고 계속 돌 수 있고,
  // 뒤늦은 완료가 새 세션을 못 건드리게 하는 건 admission 차단(각 producer가 패닉 첫 동기 구간에서 닫음)이 맡음
  final bool timedOut;

  final Object? error;

  @override
  String toString() => 'PanicStepFailure($step, timedOut: $timedOut)';
}

// failures가 비어야만 완전 소각
final class PanicWipeResult {
  const PanicWipeResult(this.failures);

  final List<PanicStepFailure> failures;

  bool get isComplete => failures.isEmpty;
}

// 순서: admission 동기적으로 닫기 -> 실행 중 producer 정지/drain 대기 -> RAM
// 소각 -> 디스크(vault, 기기 이름) 삭제. 반대면 살아있던 I/O가 소각 뒤 상태를 되살릴 수 있음
// 각 단계는 stepTimeout까지만 기다리고 넘으면 PanicStepFailure로 기록한
// 뒤 진행 (native 호출 하나가 소각을 막으면 안 되지만 남은 위험은 숨기지 않음)
// 링크/서버가 멈춘 뒤 신원 키도 교체(rotateKey)해서 소각 전후 세션이
// peerId로 안 엮임. duress 세션도 실제 신원 파일까지 지움
// RAM 소각과 함께 OS 쪽 흔적(이미지 캐시, 클립보드, 고아 .part)도 지움.
// deleteReceivedFiles면 이번 세션에 받은 파일까지 지움
Future<PanicWipeResult> executePanicWipe({
  required InMemoryStore store,
  required LinkRegistry registry,
  required ServerController serverController,
  required ForegroundService foregroundService,
  required NotificationService notificationService,
  required VaultSettingsNotifier vaultSettings,
  required VaultAccessNotifier vaultAccess,
  required IdentityStore identityStore,
  required AppIdentity identity,
  required bool isDecoySession,
  bool deleteReceivedFiles = false,
  VoiceProducerRegistry? voiceProducers,
  Future<void> Function()? clearClipboard,
  Future<void> Function()? releaseNativeSources,
  Future<void> Function()? sweepTemp,
  File? directorySettingsFile,
  Duration stepTimeout = kPanicStepTimeout,
}) async {
  final failures = <PanicStepFailure>[];

  Future<void> guarded(String step, Future<void> Function() run) async {
    try {
      await run().timeout(stepTimeout);
    } on TimeoutException {
      failures.add(PanicStepFailure(step, timedOut: true));
    } on Object catch (e) {
      // Error 서브타입도 기록만 함: 어떤 단계가 버그로 터져도 뒤의 소각까지 가야 하고 failures로 드러남
      failures.add(PanicStepFailure(step, timedOut: false, error: e));
    }
  }

  final voice = voiceProducers ?? VoiceProducerRegistry.instance;

  // admission 차단: 아래 전부 첫 await 전에 동기적으로 실행됨
  store.stopPersisting(); // 디바운스 저장부터 끊음 (소각 중간값이 안 나가게)
  // 아직 아무도 안 읽은 vault snapshot 참조부터 없앰: store가
  // 소각된 뒤 provider가 재생성돼도 옛 내용이 재hydrate 못 하게
  vaultAccess.clearPendingSnapshot();
  voice.closeAdmission();

  try {
    // 정지 단계는 병렬: 한 단계가 안 끝나도 다른 단계 시작이 안 밀리고,
    // 각자 stepTimeout 상한이라 최악에도 한 번 분량만 기다림
    // 각 호출의 첫 동기 구간이 목록을 만드는 즉시 실행돼 admission이 한 틱에 닫힘
    await Future.wait(<Future<void>>[
      guarded('voiceProducers', voice.stopAll),
      guarded('notifications', notificationService.cancelAll),
      guarded('foregroundService', () async {
        if (!await foregroundService.stop()) {
          throw StateError('foreground service did not confirm stop');
        }
      }),
      guarded('server', serverController.stop),
      guarded('links', registry.disposeAll),
    ]);
    // 링크가 다 닫힌 뒤에 갈아야 핸드셰이크 도중인 링크가 옛 키로 서명하다 어긋나지 않음
    await guarded('identityKey', identity.rotateKey);
    // native 첨부 소스는 링크/전송 reader가 drain된 뒤에 무효화함
    // 그 뒤 도착하는 늦은 pick/open 결과는 native 쪽 generation 검사가 등록 자체를 막음
    await guarded(
      'nativeSources',
      releaseNativeSources ?? MobileFileSource.releaseAll,
    );

    store.secureWipe();
    await guarded('transferDrain', store.drainDisposals);
    OsPrivacy.clearDecodedImages();
    await guarded('clipboard', clearClipboard ?? OsPrivacy.clearClipboard);
    // 전송이 다 drain된 뒤라 남은 .part는 전부 고아
    await guarded('orphanPartials', IncomingSessionFiles.sweepOrphanPartials);
    // 플러그인이 임시 폴더에 만든 사본(공유·파일 선택·드래그·예전 음성 캐시)도 지움
    await guarded('tempFiles', sweepTemp ?? sweepAppTemp);
    if (deleteReceivedFiles) {
      await guarded('receivedFiles', IncomingSessionFiles.deleteReceived);
    }
    // 못 지운 파일이 남았으면 다음 패닉이 다시 시도하게 기록 유지
    if (!deleteReceivedFiles || IncomingSessionFiles.receivedCount == 0) {
      IncomingSessionFiles.forget();
    }
    await guarded(
      'directorySettings',
      () => IncomingSessionFiles.deleteDirectorySettings(
        settingsFile: directorySettingsFile,
      ),
    );

    await guarded('vaultErase', vaultSettings.eraseForPanic);
    await guarded('identityFile', identityStore.clear);
  } finally {
    voice.reopenAdmission();
  }
  return PanicWipeResult(List<PanicStepFailure>.unmodifiable(failures));
}
