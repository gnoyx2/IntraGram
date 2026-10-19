part of '../transfer_tile.dart';

// 종류 색을 깐 둥근 정사각 배지. 왼쪽 위가 밝고 오른쪽 아래가 살짝 깊은 그라디언트에 흰 글리프
class _FileKindBadge extends StatelessWidget {
  const _FileKindBadge({required this.kind, this.size = 44});

  final FileKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = kind.tint;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.3),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tint, Color.lerp(tint, Colors.black, 0.2) ?? tint],
          ),
          boxShadow: [
            BoxShadow(
              color: tint.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(kind.icon, size: size * 0.5, color: Colors.white),
      ),
    );
  }
}

// 답장 인용처럼 좁은 자리용 정사각 미리보기. 이미지면 검증을 거친 썸네일, 아니면 종류 배지
class TransferThumb extends ConsumerWidget {
  const TransferThumb({required this.transferId, this.size = 36, super.key});

  final String transferId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfer = ref.watch(transferProvider(transferId));
    if (transfer == null) return const SizedBox.shrink();
    final kind = FileKind.of(transfer.fileName, mimeType: transfer.mimeType);
    final badge = _FileKindBadge(kind: kind, size: size);
    // 거절·취소·실패한 전송은 본 카드도 미리보기를 거두므로 인용에서도 배지만 보임
    const settled = {
      TransferState.rejected,
      TransferState.cancelled,
      TransferState.failed,
    };
    if (kind != FileKind.image ||
        transfer.voice ||
        settled.contains(transfer.state)) {
      return badge;
    }
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final path = transfer.localPath;
    final thumb = transfer.thumbBytes;
    final Widget image;
    if (path != null && transfer.state == TransferState.complete) {
      image = SafeFileImage(
        path: path,
        fit: BoxFit.cover,
        width: pixels,
        height: pixels,
        placeholder: badge,
      );
    } else if (thumb != null) {
      image = FutureBuilder<bool>(
        future: _thumbChecks[thumb] ??= _thumbFits(thumb),
        builder: (context, snap) => snap.data != true
            ? badge
            : Image(
                image: OsPrivacy.trackImage(
                  thumb,
                  ResizeImage(MemoryImage(thumb), width: pixels),
                ),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => badge,
              ),
      );
    } else {
      return badge;
    }
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child: SizedBox.square(dimension: size, child: image),
      ),
    );
  }
}
