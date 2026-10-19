import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data' show Endian;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'package:intragram/core/haptics.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/core/constants.dart' show kMaxThumbBytes;
import 'package:intragram/core/file_kind.dart';
import 'package:intragram/core/native_open.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/core/voice/voice_clip.dart';
import 'package:intragram/core/voice/voice_wav.dart';
import 'package:intragram/core/voice_producer_registry.dart';
import 'package:intragram/features/chat/widgets/image_viewer_screen.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/registry/incoming_path_resolver.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/motion.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart'
    show dialogActions;
import 'package:intragram/widgets/picker_feedback.dart';
import 'package:intragram/widgets/press_scale.dart';
import 'package:intragram/widgets/safe_file_image.dart';
import 'package:intragram/widgets/share_origin.dart';

part 'transfer_tile/kind_badge.dart';
part 'transfer_tile/progress_line.dart';
part 'transfer_tile/tile_body.dart';
part 'transfer_tile/tile_thumbnail.dart';
part 'transfer_tile/tile_actions.dart';
part 'transfer_tile/received_actions.dart';
part 'transfer_tile/voice_button.dart';
part 'transfer_tile/voice_player.dart';
part 'transfer_tile/voice_waveform.dart';
part 'transfer_tile/tile_voice_control.dart';

// 파일 카드 폭. 말풍선이 이보다 좁으면 말풍선 폭을 따름 (카드마다 폭이 들쭉날쭉하지 않게)
const double _kCardWidth = 280;

class TransferTile extends ConsumerWidget {
  const TransferTile({
    required this.transferId,
    required this.mine,
    required this.onBubble,
    super.key,
  });

  final String transferId;
  final bool mine;
  final Color onBubble;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfer = ref.watch(transferProvider(transferId));
    // 리빌드마다가 아니라 실제 상태 전이에서만 한 번 울림
    ref.listen(transferProvider(transferId), (previous, next) {
      if (next?.state == TransferState.complete &&
          previous?.state != TransferState.complete) {
        AppHaptics.mediumImpact();
      }
    });
    final muted = onBubble.withValues(alpha: AppOpacity.secondaryText);

    if (transfer == null) {
      return Text(
        S.of(context).t('transfer.fileGone'),
        style: TextStyle(color: muted, fontStyle: FontStyle.italic),
      );
    }
    // 재생할 바이트가 있으면 플레이어만 보이고, 수락 대기·수신 중처럼 아직 없으면
    // 무엇을 받는지 알 수 있게 음성 제목과 크기를 위에 붙임
    if (transfer.voice) {
      final control = _control(context, ref, transfer, muted);
      if (transfer.voiceBytes != null) return control;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _voiceTitle(context, transfer, muted),
          const SizedBox(height: AppSpacing.sm),
          control,
        ],
      );
    }

    final kind = FileKind.of(transfer.fileName, mimeType: transfer.mimeType);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _kCardWidth),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _FileKindBadge(kind: kind),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: _titleBlock(context, transfer, muted)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _control(context, ref, transfer, muted),
          ],
        ),
      ),
    );
  }

  Widget _voiceTitle(
    BuildContext context,
    FileTransfer transfer,
    Color muted,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const _FileKindBadge(kind: FileKind.audio, size: 36),
      const SizedBox(width: AppSpacing.md),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              S.of(context).t('transfer.voiceLabel'),
              style: TextStyle(color: onBubble, fontWeight: FontWeight.w600),
            ),
            Text(
              formatBytes(transfer.totalBytes),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _titleBlock(BuildContext context, FileTransfer transfer, Color muted) {
    final size = formatBytes(transfer.totalBytes);
    final ext = p.extension(transfer.fileName).replaceFirst('.', '');
    final batch = transfer.batchLabel;
    // 확장자가 길면(임의 문자열) 배지만으로 충분해서 크기만 보임
    final sizeLine = batch != null
        ? S.of(context).t('transfer.batchLine', {'label': batch, 'size': size})
        : ext.isEmpty || ext.length > 5
        ? size
        : '${ext.toUpperCase()} · $size';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                transfer.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: onBubble, fontWeight: FontWeight.w600),
              ),
            ),
            if (transfer.encrypted) ...[
              const SizedBox(width: AppSpacing.xs),
              Semantics(
                label: S.of(context).t('a11y.encrypted'),
                child: Icon(
                  Icons.lock_rounded,
                  size: MediaQuery.textScalerOf(context).scale(12),
                  color: muted,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          sizeLine,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: muted,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
