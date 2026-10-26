import 'package:flutter/material.dart';

import 'package:intragram/core/target_platform.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

// 카메라 촬영은 없음: image_picker 카메라는 앱 캐시에 파일을 써서 제로 디스크와 안 맞음 (사진첩 선택으로 대신함)
enum AttachChoice { photoLibrary, file }

Future<AttachChoice?> showAttachSheet(BuildContext context) {
  return showModalBottomSheet<AttachChoice>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _AttachSheet(),
  );
}

class _AttachSheet extends StatelessWidget {
  const _AttachSheet();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // 큰 글씨의 작은 플로팅 창에선 두 줄도 시트 높이를 넘어서 스크롤되게 함
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 데스크톱엔 진짜 사진첩이 없어서 모바일에서만 보임 (호출부도 데스크톱에선 시트를 건너뜀)
            if (isMobileTarget)
              _AttachOption(
                icon: Icons.photo_library_outlined,
                label: s.t('attach.photoLibrary'),
                onTap: () =>
                    Navigator.of(context).pop(AttachChoice.photoLibrary),
              ),
            _AttachOption(
              icon: Icons.attach_file,
              label: s.t('attach.file'),
              onTap: () => Navigator.of(context).pop(AttachChoice.file),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(leading: Icon(icon), title: Text(label), onTap: onTap);
  }
}
