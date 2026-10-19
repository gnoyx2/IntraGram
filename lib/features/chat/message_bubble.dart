import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/core/haptics.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/native_open.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/core/punycode.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/motion.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/action_menu.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart'
    show dialogActions;
import 'package:intragram/widgets/keyboard_access.dart';
import 'package:intragram/widgets/press_scale.dart';
import 'burn_countdown.dart';
import 'transfer_tile.dart';

part 'bubble/actions.dart';
part 'bubble/action_run.dart';
part 'bubble/bubble_shape.dart';
part 'bubble/hover_actions.dart';
part 'bubble/linkable_text.dart';
part 'bubble/quoted_strip.dart';
part 'bubble/reaction_chips.dart';
part 'bubble/meta_row.dart';
part 'bubble/press_scale.dart';
part 'bubble/system_message.dart';
part 'bubble/wrap_effects.dart';

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    required this.message,
    this.onReply,
    this.onJumpToMessage,
    this.animateIn = false,
    this.joinsPrevious = false,
    this.joinsNext = false,
    super.key,
  });

  final EphemeralMessage message;

  // 같은 발신자의 연속 메시지 묶음 안에서 위·아래 이웃과 붙는지. 붙는 쪽 모서리와 간격이 줄어듦
  final bool joinsPrevious;
  final bool joinsNext;

  final void Function(String messageId)? onReply;

  final void Function(String messageId)? onJumpToMessage;

  // 세션 중 새로 도착한 메시지에만 MessageList가 켬 (화면 열 때 이미 있던 기록은 제외)
  final bool animateIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = context.chat;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (message.kind == MessageKind.system) {
      return _SystemMessageBubble(message: message);
    }

    final mine = message.isMine;
    final foreground = mine ? chat.onBubbleMine : chat.onBubbleTheirs;
    // 대화 객체 전체가 아니라 isRoom/memberCount만 select함. peerTyping/online/sas가
    // 바뀔 때마다 버블 전체가 리빌드되는 걸 막음 (타이핑 중엔 계속 바뀜)
    final (isRoom, memberCount) = ref.watch(
      conversationProvider(message.conversationId).select(
        (conversation) =>
            (conversation?.isRoom ?? false, conversation?.memberCount ?? 0),
      ),
    );
    // 묶음의 첫 말풍선에만 이름을 붙임
    final showSender = isRoom && !mine && !joinsPrevious;

    // 전송 실패로 바뀌는 순간에만 한 번 울림 (transfer_tile의 완료 햅틱과 같은 패턴)
    // 네트워크 계층에 Flutter 의존성을 안 넣으려고 프레젠테이션 쪽에서 전이를 지켜봄
    ref.listen(
      messageByIdProvider((
        conversationId: message.conversationId,
        messageId: message.id,
      )),
      (previous, next) {
        if (next?.delivery == DeliveryState.failed &&
            previous?.delivery != DeliveryState.failed) {
          AppHaptics.mediumImpact();
        }
      },
    );

    // 스크린 리더에는 누가 보냈는지를 항상 알려줌. 1:1은 좌/우 정렬로만 표시해서 시각 신호가 없으면 유실됨
    // MergeSemantics로 이 라벨과 본문/시간/전송상태를 버블 하나짜리 시맨틱 노드로 합침
    final fromLabel = mine
        ? S.of(context).t('a11y.fromMe')
        : S.of(context).t('a11y.fromPeer', {'name': message.senderAlias});

    // 전송 실패한 글은 말풍선 어디를 눌러도 다시 보냄. 부모 영역 밖 탭은 자식에 안 닿아서
    // 메타 줄 안에서 48dp 탭 영역을 만들려면 줄 자체가 48dp로 커짐. 표시만 작게 두고 탭은 말풍선이 받음
    final onRetry =
        message.delivery == DeliveryState.failed &&
            message.kind == MessageKind.text
        ? () {
            AppHaptics.mediumImpact();
            ref.read(linkRegistryProvider).resendFailed(message.id);
          }
        : null;

    final body = Container(
      constraints: BoxConstraints(
        maxWidth: math.min(MediaQuery.sizeOf(context).width * 0.78, 520),
      ),
      margin: _bubbleMargin(joinsPrevious, joinsNext),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      decoration: bubbleDecoration(
        chat: chat,
        scheme: scheme,
        mine: mine,
        joinsPrevious: joinsPrevious,
        joinsNext: joinsNext,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(label: fromLabel),
          if (showSender)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Text(
                message.senderAlias,
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: chat.accentInk,
                ),
              ),
            ),
          if (message.replyToId != null)
            _QuotedStrip(
              conversationId: message.conversationId,
              parentId: message.replyToId!,
              mine: mine,
              foreground: foreground,
              onTap: onJumpToMessage == null
                  ? null
                  : () => onJumpToMessage!(message.replyToId!),
            ),
          if (message.kind == MessageKind.file && message.transferId != null)
            TransferTile(
              transferId: message.transferId!,
              mine: mine,
              onBubble: foreground,
            )
          else
            _LinkableText(
              text: message.text ?? '',
              style:
                  textTheme.bodyMedium?.copyWith(color: foreground) ??
                  TextStyle(color: foreground),
              linkColor: mine ? foreground : chat.accentInk,
              // 실패한 글은 말풍선 클릭이 다시 보내기라 선택이 그 클릭을 가로채지 않게 뺌
              selectable: _desktop && onRetry == null,
              onMenu: (at) => _promptActions(context, ref, at),
            ),
          const SizedBox(height: AppSpacing.xs),
          _MetaRow(
            message: message,
            foreground: foreground,
            chat: chat,
            roomMemberCount: isRoom ? memberCount : null,
            canRetry: onRetry != null,
          ),
        ],
      ),
    );

    final bubble = Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 키보드: Tab·화살표로 말풍선에 오고 Enter·Space·메뉴 키·Shift+F10으로 동작 시트를 엶
        // (Enter는 ActivateIntent라 말풍선 안 버튼에 포커스가 있으면 그 버튼이 먼저 받음)
        Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) =>
                  _promptActions(context, ref, menuAnchor(context)),
            ),
          },
          child: CallbackShortcuts(
            bindings: menuKeyBindings(
              () => _promptActions(context, ref, menuAnchor(context)),
            ),
            // 보낸이·본문·시각과 길게 누르기·사용자 지정 동작(답장·복사·반응·삭제)을 한 노드로:
            // 스크린 리더가 이름 없는 바깥 칸에서 길게 누를 필요 없이 말풍선에서 바로 고름
            child: MergeSemantics(
              child: Semantics(
                customSemanticsActions: _semanticActions(context, ref),
                child: Focus(
                  child: _PressScale(
                    onTap: onRetry,
                    onLongPress: () => _promptActions(context, ref),
                    onSecondaryTapUp: (details) =>
                        _promptActions(context, ref, details.globalPosition),
                    child: body,
                  ),
                ),
              ),
            ),
          ),
        ),
        _ReactionChips(
          message: message,
          mine: mine,
          onAddReaction: () => _promptActions(context, ref),
        ),
      ],
    );

    return _wrapEffects(
      context,
      _withHoverActions(context, ref, bubble),
      scheme,
    );
  }
}
