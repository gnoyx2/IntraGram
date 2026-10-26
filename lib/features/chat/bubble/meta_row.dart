part of '../message_bubble.dart';

// 시각·틱·카운트가 한 줄에서 픽셀 단위로 맞도록 글자 상자를 폰트 em 높이로 고정함
// height 1 + 균등 행간이면 상자 중심이 숫자 대문자 높이의 중심과 0.2px 안쪽으로 겹쳐서
// Row 가운데 정렬만으로 아이콘 중심과 숫자 중심이 맞음
TextStyle? _metaStyle(BuildContext context, Color color) =>
    Theme.of(context).textTheme.labelSmall?.copyWith(
      color: color,
      height: 1,
      leadingDistribution: TextLeadingDistribution.even,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.message,
    required this.foreground,
    required this.chat,
    this.roomMemberCount,
    this.canRetry = false,
  });

  final EphemeralMessage message;
  final Color foreground;
  final ChatColors chat;

  // 1:1이면 null (상대가 하나뿐이라 읽음 카운트 불필요)
  final int? roomMemberCount;

  // 탭은 말풍선 전체가 받고(MessageBubble의 onRetry) 여기선 다시 보내기 표시만 그림
  final bool canRetry;

  @override
  Widget build(BuildContext context) {
    final muted = foreground.withValues(alpha: AppOpacity.secondaryText);
    // 파일 메시지는 TransferTile이 진짜 상태를 보여줌. 체크를 같이 띄우면
    // 방금 제안만 한 파일도 "전송됨"처럼 보임
    final showDeliveryIcon = message.isMine && message.kind != MessageKind.file;
    // 시각·전달 상태도 OS 200%까지는 따라 커짐 (그 위로는 말풍선 본문만 키움)
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 2,
      child: Builder(
        builder: (context) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.hasTimer && message.burnAt != null) ...[
              BurnCountdown(burnAt: message.burnAt!, color: chat.burn),
              const SizedBox(width: AppSpacing.xs),
            ],
            Flexible(
              child: Text(
                S
                    .of(context)
                    .clock(
                      message.createdAt,
                      use24h: MediaQuery.alwaysUse24HourFormatOf(context),
                    ),
                style: _metaStyle(context, muted),
              ),
            ),
            if (showDeliveryIcon) ...[
              const SizedBox(width: AppSpacing.xs),
              _DeliveryIcon(
                state: message.delivery,
                muted: muted,
                chat: chat,
                readCount: message.readBy.length,
                roomMemberCount: roomMemberCount,
              ),
            ],
            if (showDeliveryIcon && canRetry) ...[
              const SizedBox(width: AppSpacing.xs),
              // 전송 상태 아이콘과 같은 크기라 줄 높이가 시각 글자 높이 그대로 유지됨
              Semantics(
                button: true,
                label: S.of(context).t('msg.retry'),
                child: Icon(
                  Icons.refresh,
                  size: MediaQuery.textScalerOf(context).scale(14),
                  color: chat.burn,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// sending은 시계, sent는 체크 하나, delivered는 회색 이중 체크, read는 액센트 이중 체크
// 글리프 크기를 숫자 높이에 맞춘 한 단계로 통일해서 상태가 바뀌어도 줄이 출렁이지 않음
class _DeliveryIcon extends StatelessWidget {
  const _DeliveryIcon({
    required this.state,
    required this.muted,
    required this.chat,
    this.readCount = 0,
    this.roomMemberCount,
  });

  final DeliveryState state;
  final Color muted;
  final ChatColors chat;

  final int readCount;

  final int? roomMemberCount;

  @override
  Widget build(BuildContext context) {
    // 아이콘은 텍스트 스케일을 자동으로 안 따라가서, 큰 글씨 설정에선 아이콘만 안 보일 정도로 작아짐
    final size = MediaQuery.textScalerOf(context).scale(14);
    final readColor = Theme.of(context).colorScheme.primary;
    final (glyph, color) = switch (state) {
      DeliveryState.sending => (Icons.schedule, muted),
      DeliveryState.sent => (Icons.check, muted),
      DeliveryState.delivered => (Icons.done_all, muted),
      DeliveryState.read => (Icons.done_all, readColor),
      DeliveryState.failed => (Icons.error_outline, chat.burn),
    };
    final icon = Icon(
      glyph,
      // 시계는 원형이라 같은 상자에서 체크보다 커 보여서 한 단계 줄임
      size: state == DeliveryState.sending ? size - 2 : size,
      color: color,
    );
    final label = switch (state) {
      DeliveryState.sending => S.of(context).t('a11y.deliverySending'),
      DeliveryState.sent => S.of(context).t('a11y.deliverySent'),
      DeliveryState.delivered =>
        roomMemberCount == null
            ? S.of(context).t('a11y.deliveryDelivered')
            : S.of(context).t('a11y.deliveryHostDelivered'),
      DeliveryState.read => S.of(context).t('a11y.deliveryRead'),
      DeliveryState.failed => S.of(context).t('a11y.deliveryFailed'),
    };
    // 나 빼고 읽을 수 있는 사람이 2명 이상일 때만 카운트 표시 (멤버 2명짜리 방은 사실상 1:1)
    final possibleReaders = roomMemberCount == null
        ? null
        : math.max(roomMemberCount! - 1, readCount);
    if (state != DeliveryState.read ||
        possibleReaders == null ||
        possibleReaders < 2) {
      return Semantics(label: label, child: icon);
    }
    final countLabel = '$readCount/$possibleReaders';
    return Semantics(
      label: '$label ($countLabel)',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: AppSpacing.xxs),
          Text(
            countLabel,
            style: _metaStyle(
              context,
              chat.accentInk,
            )?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
