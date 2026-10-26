part of '../image_viewer_screen.dart';

// 공유는 모바일만. iPad 공유 팝오버가 이 버튼을 가리키게 버튼의 context를 넘김
class _ViewerTopBar extends StatelessWidget {
  const _ViewerTopBar({required this.path, required this.canShare});

  final String path;
  final bool canShare;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: s.t('viewer.close'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        const Spacer(),
        if (canShare)
          Builder(
            builder: (buttonContext) => IconButton(
              icon: const Icon(Icons.share_outlined, color: Colors.white),
              tooltip: s.t('viewer.share'),
              onPressed: () => SharePlus.instance.share(
                ShareParams(
                  files: [XFile(path)],
                  sharePositionOrigin: shareOrigin(buttonContext),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
