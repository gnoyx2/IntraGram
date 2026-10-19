import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

// 카메라 즉석 촬영은 없음: image_picker의 카메라 경로가 앱 캐시에
// 기록해서 zero-disk 원칙과 안 맞음 (로컬 이미지 파일 선택으로 대체)
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
    final isMobile = Platform.isIOS || Platform.isAndroid;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 데스크톱엔 진짜 사진첩이 없어서 "파일"과 똑같아 보이므로 모바일 전용
            // 호출부(drag_drop.dart)도 데스크톱에선 시트를 건너뛰지만 방어적으로 여기서도 숨김
            if (isMobile)
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
