import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/core/peer_code.dart';
import 'package:intragram/core/target_platform.dart';
import 'package:intragram/features/chat/open_chat.dart';
import 'package:intragram/features/connect/scan_screen.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/action_menu.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';
import 'connect_failure.dart';
import 'widgets/manual_connect_dialog.dart';

export 'package:intragram/features/chat/open_chat.dart' show openChat;
export 'home_panic_action.dart';

Future<void> connectAndOpenPeer(
  BuildContext context,
  WidgetRef ref,
  PeerDevice peer,
) {
  return _runConnectFlow(
    context,
    () => ref.read(linkRegistryProvider).connectToPeer(peer),
  );
}

// 멀티캐스트를 막는 Wi-Fi라 피어가 안 보일 때의 탈출구. 사설 IP와 포트만 받음 (나머지는 다이얼로그가 거부)
Future<void> manualConnect(BuildContext context, WidgetRef ref) async {
  final target = await showDialog<({String host, int port})>(
    context: context,
    builder: (_) => const ManualConnectDialog(),
  );
  if (target == null || !context.mounted) return;
  await _runConnectFlow(
    context,
    () => ref
        .read(linkRegistryProvider)
        .connectManual(host: target.host, port: target.port),
  );
}

// 데스크톱은 스캔 대신 IP로 연결이 그 자리를 채움
bool get canScanQr => isMobileTarget;

// 상대가 방을 열고 있으면 room_join이 방으로 들이고 아니면 1:1 (LAN 밖 코드는 ScanScreen이 이미 거름)
Future<void> scanConnect(BuildContext context, WidgetRef ref) async {
  final target = await Navigator.of(context).push<PeerCode>(
    MaterialPageRoute<PeerCode>(builder: (_) => const ScanScreen()),
  );
  if (target == null || !context.mounted) return;
  // 기기 코드에 실린 peerId가 있으면 그 기기하고만 이어짐 (다른 기기가 그 주소에 있으면 거절)
  await _runConnectFlow(
    context,
    () => ref
        .read(linkRegistryProvider)
        .connectManual(
          host: target.host,
          port: target.port,
          expectedPeerId: target.peerId,
        ),
  );
}

Future<void> peerActions(
  BuildContext context,
  WidgetRef ref,
  PeerDevice peer, {
  Offset? at,
}) async {
  final s = S.of(context);
  final action = await showActionMenu<String>(
    context,
    at: at,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.content_paste),
          title: Text(s.t('homeActions.sendClipText')),
          onTap: () => Navigator.of(sheetContext).pop('clip'),
        ),
        ListTile(
          leading: const Icon(Icons.group_add_outlined),
          title: Text(s.t('homeActions.addToRoom')),
          subtitle: Text(s.t('homeActions.addToRoomSub')),
          onTap: () => Navigator.of(sheetContext).pop('room'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case 'clip':
      await sendClipboardToPeer(context, ref, peer);
    case 'room':
      await ref.read(linkRegistryProvider).inviteToRoom(peer);
  }
}

Future<void> sendClipboardToPeer(
  BuildContext context,
  WidgetRef ref,
  PeerDevice peer,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final s = S.of(context);
  String? text;
  try {
    text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  } on PlatformException {
    text = null;
  } on MissingPluginException {
    text = null;
  }
  final trimmed = (text ?? '').trim();
  if (trimmed.isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text(s.t('input.clipboardEmpty'))),
    );
    return;
  }
  if (!context.mounted) return;
  await _runConnectFlow(context, () async {
    final registry = ref.read(linkRegistryProvider);
    final id = await registry.connectToPeer(peer);
    await registry.sendText(id, trimmed);
    return id;
  });
}

// 연결 중엔 모달 스피너, 성공하면 대화로 들어가고 실패하면 이유별 스낵바 (주소 검사에 걸리면 사설 주소 안내)
Future<void> _runConnectFlow(
  BuildContext context,
  Future<String> Function() connect,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final s = S.of(context);
  // 취소해도 연결 시도는 못 멈춤 (Future는 취소 불가): 다이얼로그만 접고 나중에 끝나도 화면 전환·스낵바를 건너뜀.
  // 취소 버튼뿐 아니라 뒤로(예측형 포함)·Esc로 닫아도 취소로 봄 (안 그러면 닫은 뒤에 대화가 열리고 엉뚱한 화면을 닫음)
  var cancelled = false;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AppAlertDialog(
        cupertino: isCupertinoDialog(dialogContext),
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(s.t('homeActions.connecting'))),
          ],
        ),
        actions: dialogActions(dialogContext, [
          AdaptiveDialogAction(
            cupertino: isCupertinoDialog(dialogContext),
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: s.t('common.cancel'),
          ),
        ]),
      ),
    ).whenComplete(() => cancelled = true),
  );
  try {
    final conversationId = await connect();
    if (cancelled) return;
    if (navigator.canPop()) navigator.pop();
    pushChat(navigator, conversationId);
  } on SecurityException {
    if (cancelled) return;
    if (navigator.canPop()) navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(s.t('connect.notPrivate'))));
  } on PeerUnreachableException catch (e) {
    if (cancelled) return;
    if (navigator.canPop()) navigator.pop();
    messenger.showSnackBar(connectFailureSnackBar(s, e.reason));
  } on Exception {
    if (cancelled) return;
    if (navigator.canPop()) navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(s.t('homeActions.couldNotConnect'))),
    );
  }
}
