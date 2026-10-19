import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/core/peer_code.dart';
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

// mDNS 멀티캐스트가 필터링돼 피어가 안 나타나는 Wi-Fi용 탈출구
// 사설 IP + 포트만 받음 (다이얼로그가 그 외는 거부)
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

// 데스크톱은 스캔 진입점을 숨기고 "Connect by IP"가 그 자리를 채움
bool get canScanQr => Platform.isAndroid || Platform.isIOS;

// 상대가 방을 호스팅 중이면 기존 room_join 디스패치가 방으로, 아니면 1:1로 연결됨
// (ScanScreen이 에어갭 밖 코드를 이미 거름)
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

// connect가 도는 동안 모달 스피너, 이후 방 push, 실패면 이유를 담은 SnackBar
// SecurityException(에어갭 가드)은 사설 주소 안내, 다이얼 실패는 이유별 안내(connect_failure.dart)
Future<void> _runConnectFlow(
  BuildContext context,
  Future<String> Function() connect,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final s = S.of(context);
  // 취소해도 네트워크 콜은 중단 안 됨 (Future는 취소 불가). 다이얼로그를 접고,
  // connect가 나중에 끝나도 화면 전환/에러 스낵바를 건너뜀
  var cancelled = false;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog.adaptive(
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
          onPressed: () {
            cancelled = true;
            Navigator.of(dialogContext).pop();
          },
          label: s.t('common.cancel'),
        ),
      ]),
    ),
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
