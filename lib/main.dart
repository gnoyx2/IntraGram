import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'app_providers.dart';
import 'core/app_identity.dart';
import 'core/app_licenses.dart';
import 'core/os_privacy.dart';
import 'core/temp_sweep.dart';
import 'network/registry/incoming_session_files.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppLicenses();

  // Android 15+는 edge-to-edge가 강제라, 명시적으로 켜야 테마의
  // systemOverlayStyle(투명 내비바)이 적용됨
  if (!kIsWeb && Platform.isAndroid) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // 지난 실행이 크래시·강제 종료로 남긴 .part를 지움 (서버가 아직 안 떠서 받는 전송이 없음)
  try {
    await IncomingSessionFiles.restoreDirectories();
  } catch (e) {
    debugPrint('download directory restore failed: $e');
  }
  try {
    await IncomingSessionFiles.sweepOrphanPartials();
  } catch (e) {
    debugPrint('orphan partial sweep failed: $e');
  }
  // 지난 실행의 플러그인 사본(공유·파일 선택·드래그)과 예전 버전의 음성 캐시를 지움
  try {
    await sweepAppTemp();
  } catch (e) {
    debugPrint('temp sweep failed: $e');
  }

  // 신원 키는 메모리에만 둠. 컨테이너를 직접 쥐는 건 종료 시그널에서 RAM을 지우려는 목적임
  final identity = await AppIdentity.create();
  // iOS 27.1+가 접힘선을 알려 주는지 첫 화면 전에 정함 (알려 주지 않으면 펼친 iPhone은 화면 크기로 짐작함)
  await OsPrivacy.refreshDisplayRegions();
  await OsPrivacy.refreshAccessibility();
  final container = ProviderContainer(
    overrides: [appIdentityProvider.overrideWithValue(identity)],
  );
  _installShutdownScrub(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const IntraGramApp(),
    ),
  );
}

void _installShutdownScrub(ProviderContainer container) {
  if (kIsWeb) return;
  if (!(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) return;

  final signals = <ProcessSignal>[
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ];

  var shuttingDown = false;
  for (final signal in signals) {
    signal.watch().listen((_) async {
      if (shuttingDown) return;
      shuttingDown = true;
      try {
        final settings = container.read(vaultSettingsProvider);
        if (settings.enabled) {
          await container
              .read(vaultProvider)
              .save(container.read(inMemoryStoreProvider).toSnapshot(settings))
              .timeout(const Duration(seconds: 3));
        }
      } catch (e) {
        debugPrint('shutdown save failed: $e');
      } finally {
        // 저장 실패와 무관하게 링크부터 끊고 RAM 정리 후 종료함
        try {
          await container.read(linkRegistryProvider).disposeAll();
        } finally {
          try {
            container.read(inMemoryStoreProvider).secureWipe();
            OsPrivacy.clearDecodedImages();
          } finally {
            exit(0);
          }
        }
      }
    });
  }
}
