import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/core/haptics.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/app_providers/conversation_actions.dart';
import 'package:intragram/features/home/panic_sequence.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/registry/incoming_session_files.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/widgets/action_menu.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';

// 홈에서 바로 "End conversation"을 띄움 (PeerTile과 대칭)
Future<void> conversationActions(
  BuildContext context,
  WidgetRef ref,
  Conversation conversation, {
  Offset? at,
}) async {
  final s = S.of(context);
  final action = await showActionMenu<String>(
    context,
    at: at,
    builder: (sheetContext) => ListTile(
      leading: const Icon(Icons.link_off),
      title: Text(s.t('chat.endConversation')),
      onTap: () => Navigator.of(sheetContext).pop('end'),
    ),
  );
  if (action != 'end' || !context.mounted) return;
  final endCupertino = isCupertinoDialog(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog.adaptive(
      title: Text(s.t('chat.endConversation')),
      content: Text(s.t('chat.endBody')),
      actions: dialogActions(dialogContext, [
        AdaptiveDialogAction(
          cupertino: endCupertino,
          onPressed: () => Navigator.of(dialogContext).pop(false),
          label: s.t('common.cancel'),
        ),
        AdaptiveDialogAction(
          cupertino: endCupertino,
          emphasis: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          label: s.t('chat.endButton'),
        ),
      ]),
    ),
  );
  if (ok != true || !context.mounted) return;
  await endConversation(ref, conversation.id);
}

// 재진입 가능한 단일 Future. 버튼 연타나 종료 시그널과 겹쳐도 두 번째 호출은 이미 도는 것에 합류함
Future<PanicWipeResult>? _panicInFlight;

// 확인받고, 실행 중인 걸 먼저 멈춘 뒤에만 RAM/디스크를 정리함 (executePanicWipe 참고). 되돌릴 수 없음
// 일부 단계가 끝까지 성공 못 하면(타임아웃/예외) "지워짐"이 아니라 부분 실패로 표시함
Future<void> panicWipe(BuildContext context, WidgetRef ref) async {
  final s = S.of(context);
  final wipeCupertino = isCupertinoDialog(context);
  // 이번 세션에 받은 파일이 있을 때만 "받은 파일도 삭제" 옵션을 보여줌
  final hasReceived = IncomingSessionFiles.receivedCount > 0;
  var deleteReceivedFiles = false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog.adaptive(
        title: Text(s.t('homeActions.wipeTitle')),
        content: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.t('homeActions.wipeBody')),
              if (hasReceived)
                CheckboxListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: deleteReceivedFiles,
                  onChanged: (v) =>
                      setDialogState(() => deleteReceivedFiles = v ?? false),
                  title: Text(s.t('homeActions.wipeReceivedFiles')),
                ),
            ],
          ),
        ),
        actions: dialogActions(dialogContext, [
          AdaptiveDialogAction(
            cupertino: wipeCupertino,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: s.t('common.cancel'),
          ),
          AdaptiveDialogAction(
            cupertino: wipeCupertino,
            emphasis: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: s.t('homeActions.wipe'),
          ),
        ]),
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;
  AppHaptics.heavyImpact();

  // 아래는 전부 async라 그 사이 context/ref가 죽을 수 있어서 마운트된 지금 provider 핸들을 잡음
  final store = ref.read(inMemoryStoreProvider);
  final registry = ref.read(linkRegistryProvider);
  final serverController = ref.read(serverControllerProvider.notifier);
  final foregroundService = ref.read(foregroundServiceProvider);
  final notificationService = ref.read(notificationServiceProvider);
  final vaultSettings = ref.read(vaultSettingsProvider.notifier);
  final vaultAccess = ref.read(vaultAccessProvider.notifier);
  final identityStore = ref.read(identityStoreProvider);
  final identity = ref.read(appIdentityProvider);
  final isDecoySession = ref.read(vaultProvider).isDecoyMode;
  // await 뒤엔 위젯이 죽어 ref를 못 써서, 앱 수명 내내 유효한 컨테이너를 지금 잡아둠
  final container = ProviderScope.containerOf(context);

  Navigator.of(context).popUntil((route) => route.isFirst);

  final existing = _panicInFlight;
  final Future<PanicWipeResult> future;
  if (existing != null) {
    future = existing;
  } else {
    future = executePanicWipe(
      sweepTemp: ref.read(tempSweepProvider),
      store: store,
      registry: registry,
      serverController: serverController,
      foregroundService: foregroundService,
      notificationService: notificationService,
      vaultSettings: vaultSettings,
      vaultAccess: vaultAccess,
      identityStore: identityStore,
      identity: identity,
      isDecoySession: isDecoySession,
      deleteReceivedFiles: deleteReceivedFiles,
    );
    _panicInFlight = future;
    // whenComplete는 원본이 에러면 그 에러를 복제한 새 Future를 만듦
    // catchError로 먼저 소비해 두 번째 미처리 에러를 막음 (실제 성공/실패는 아래 await future가 처리)
    unawaited(
      future.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        _panicInFlight = null;
      }),
    );
  }
  final result = await future;
  // 새 LinkRegistry(+TransferCoordinator, burn 구독)를 다음 읽기에서 다시 만듦
  // disposeAll이 취소한 구독은 되살아나지 않아서 invalidate 안 하면 패닉 뒤 새 대화의 burn이 피어에게 안 나감
  container.invalidate(linkRegistryProvider);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          s.t(
            result.isComplete
                ? 'homeActions.memoryWiped'
                : 'homeActions.memoryWipedPartial',
          ),
        ),
      ),
    );
  }
}
