part of '../image_viewer_screen.dart';

// 닫기와 (모바일) 공유. 공유 팝오버는 iPad에서 이 버튼을 가리킴
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
