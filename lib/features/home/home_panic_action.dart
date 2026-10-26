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
    builder: (dialogContext) => AppAlertDialog(
      cupertino: endCupertino,
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

// 도는 패닉 하나. 연타나 종료 신호와 겹쳐도 두 번째 호출은 도는 것에 합류함
Future<PanicWipeResult>? _panicInFlight;

// 되돌릴 수 없음. 한 단계라도 실패하거나 시간을 넘기면 지워짐이 아니라 부분 실패로 알림 (순서는 executePanicWipe)
Future<void> panicWipe(BuildContext context, WidgetRef ref) async {
  final s = S.of(context);
  final wipeCupertino = isCupertinoDialog(context);
  final hasReceived = IncomingSessionFiles.receivedCount > 0;
  var deleteReceivedFiles = false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AppAlertDialog(
        cupertino: wipeCupertino,
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

  // 아래는 다 async라 그사이 context·ref가 죽을 수 있어서 마운트된 지금 핸들을 잡아 둠
  final store = ref.read(inMemoryStoreProvider);
  final registry = ref.read(linkRegistryProvider);
  final serverController = ref.read(serverControllerProvider.notifier);
  final foregroundService = ref.read(foregroundServiceProvider);
  final notificationService = ref.read(notificationServiceProvider);
  final vaultSettings = ref.read(vaultSettingsProvider.notifier);
  final vaultAccess = ref.read(vaultAccessProvider.notifier);
  final identityStore = ref.read(identityStoreProvider);
  final identity = ref.read(appIdentityProvider);
  // await 뒤엔 ref를 못 쓸 수 있어서 앱 내내 사는 컨테이너를 잡아 둠
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
      deleteReceivedFiles: deleteReceivedFiles,
    );
    _panicInFlight = future;
    // whenComplete는 원본 에러를 복제한 새 Future를 만들어서 먼저 삼킴 (안 그러면 미처리 에러가 하나 더 생김. 진짜 결과는 아래 await가 봄)
    unawaited(
      future.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        _panicInFlight = null;
      }),
    );
  }
  final result = await future;
  // 다음 읽기에서 LinkRegistry를 새로 만듦: disposeAll이 끊은 burn 구독은 안 되살아나서 그대로 두면
  // 패닉 뒤 새 대화의 소각이 상대에게 안 감
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
