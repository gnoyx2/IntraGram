part of '../transfer_tile.dart';

const double _kThumbHeight = 180;
const int _kThumbMaxSide = 4096;

// 같은 바이트로 매 빌드마다 헤더를 다시 읽지 않게 결과를 붙여 둠
final Expando<Future<bool>> _thumbChecks = Expando<Future<bool>>();

// 수락 전 썸네일은 상대가 보낸 그대로라 디코드 전에 헤더만 읽어 해상도를 봄
// 64 KB짜리 PNG도 수만 px 캔버스면 디코드 순간 수 GB를 잡음 (cacheHeight는 디코드 뒤에 줄임)
Future<bool> _thumbFits(Uint8List bytes) async {
  if (bytes.length > kMaxThumbBytes) return false;
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return descriptor.width <= _kThumbMaxSide &&
        descriptor.height <= _kThumbMaxSide;
  } on Object {
    return false;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

class _OfferedFilePreview extends StatelessWidget {
  const _OfferedFilePreview({
    required this.thumbBytes,
    required this.preview,
    required this.mutedTextColor,
  });

  final Uint8List? thumbBytes;
  final String? preview;
  final Color mutedTextColor;

  @override
  Widget build(BuildContext context) {
    final thumb = thumbBytes;
    if (thumb != null) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      return FutureBuilder<bool>(
        future: _thumbChecks[thumb] ??= _thumbFits(thumb),
        builder: (context, snap) {
          if (snap.data != true) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _kThumbHeight),
                child: Image(
                  image: OsPrivacy.trackImage(
                    thumb,
                    ResizeImage(
                      MemoryImage(thumb),
                      height: (_kThumbHeight * dpr).round(),
                    ),
                  ),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          );
        },
      );
    }
    final text = preview;
    if (text != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(
          text,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: mutedTextColor),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

// 디스크에서 바로 디코드해서 사본을 안 만듦. 파일이 없거나 디코드 실패(예: SVG)면 아이콘으로 폴백
class _CompletedImagePreview extends StatelessWidget {
  const _CompletedImagePreview({
    required this.transfer,
    required this.onBubble,
  });

  final FileTransfer transfer;
  final Color onBubble;

  @override
  Widget build(BuildContext context) {
    final path = transfer.localPath;
    if (path == null) return const SizedBox.shrink();
    final kind = FileKind.of(transfer.fileName, mimeType: transfer.mimeType);
    if (kind != FileKind.image) return const SizedBox.shrink();
    if (!File(path).existsSync()) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ImageViewerScreen(path: path),
              ),
            ),
            child: Hero(
              tag: path,
              child: SafeFileImage(
                path: path,
                fit: BoxFit.cover,
                width: 720,
                height: 660,
                placeholder: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Icon(kind.icon, color: onBubble),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
