import 'package:flutter/material.dart';

import 'package:intragram/core/app_settings.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

// 카메라를 못 쓸 때(데스크톱, 권한 거부, 카메라 없음) 스캔 자리에 대안 경로 문구를 보여 줌. 권한 거부면 설정 열기를 붙임
class CameraUnavailable extends StatelessWidget {
  const CameraUnavailable({required this.text, this.denied = false, super.key});

  final String text;
  final bool denied;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                denied ? '${s.t('scan.cameraDenied')} $text' : text,
                textAlign: TextAlign.center,
              ),
              if (denied && canOpenSettings(SettingsPane.camera)) ...[
                const SizedBox(height: AppSpacing.lg),
                FilledButton.tonal(
                  onPressed: () => openSettings(SettingsPane.camera),
                  child: Text(s.t('settings.open')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
