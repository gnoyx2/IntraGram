import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:intragram/core/haptics.dart';
import 'package:intragram/core/sas_qr.dart';
import 'package:intragram/features/chat/widgets/sas_scan_screen.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';

// 사용자가 고른 결과. null은 "나중에"(아무것도 안 바뀜)
enum SasOutcome { matched, mismatched }

// "They match"를 눌렀거나 QR 스캔으로 숫자가 일치하면 matched, "숫자가 달라요"를 눌렀거나
// 다른 숫자의 코드를 찍으면 mismatched
// 사람이 맞춰야 하는 이유: 같은 Wi-Fi 공격자가 양쪽과 핸드셰이크를 따로 돌려 중계(MITM)해도 두 링크 다 "암호화됨"으로 보이지만
// 유도 키가 달라 SAS가 달라짐. 공격자가 통제 못 하는 채널(목소리, 같은 방의 카메라)로 대조해야 그 틈이 메워짐
// 그래서 이 채팅으로 코드를 보내 맞추는 건 의미가 없고, 복사 버튼도 두지 않음
Future<SasOutcome?> showSasFingerprintDialog(
  BuildContext context, {
  required String peerAlias,
  required String? sas,
  required bool localVerified,
  required bool verified,
}) {
  if (sas == null) return Future<SasOutcome?>.value();
  final canScan = Platform.isAndroid || Platform.isIOS;
  final cupertino = isCupertinoDialog(context);
  final s = S.of(context);
  final muted = Theme.of(context).colorScheme.onSurfaceVariant;
  return showDialog<SasOutcome>(
    context: context,
    builder: (dialogContext) => AlertDialog.adaptive(
      title: Text(s.t('sas.title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.t('sas.body', {'peer': peerAlias}),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              s.t('sas.dontSendHere'),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: muted),
            ),
            if (localVerified && !verified) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                s.t('sas.pendingNote'),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: muted),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            _SasDigits(sas: sas),
            const SizedBox(height: AppSpacing.lg),
            _SasQr(sas: sas, label: s.t('a11y.qrCodeSas')),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              s.t('qr.whiteBackgroundNote'),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: muted),
            ),
            if (canScan) ...[
              const SizedBox(height: AppSpacing.xs),
              TextButton.icon(
                onPressed: () async {
                  final matched = await Navigator.of(dialogContext).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => SasScanScreen(expected: sas),
                    ),
                  );
                  if (matched == null || !dialogContext.mounted) return;
                  Navigator.of(
                    dialogContext,
                  ).pop(matched ? SasOutcome.matched : SasOutcome.mismatched);
                },
                icon: const Icon(Icons.qr_code_scanner, size: 16),
                label: Text(s.t('sas.scan')),
              ),
            ],
          ],
        ),
      ),
      actions: dialogActions(dialogContext, [
        AdaptiveDialogAction(
          cupertino: cupertino,
          onPressed: () => Navigator.of(dialogContext).pop(),
          label: s.t('sas.notNow'),
        ),
        // 일치 버튼과 같은 무게로 둬서, 숫자가 다를 때 남는 출구가 "일치함"뿐이지 않게 함
        AdaptiveDialogAction(
          cupertino: cupertino,
          destructive: true,
          icon: Icons.gpp_bad_outlined,
          onPressed: () {
            AppHaptics.heavyImpact();
            Navigator.of(dialogContext).pop(SasOutcome.mismatched);
          },
          label: s.t('sas.mismatch'),
        ),
        AdaptiveDialogAction(
          cupertino: cupertino,
          emphasis: true,
          icon: Icons.verified_user,
          onPressed: () {
            AppHaptics.selectionClick();
            Navigator.of(dialogContext).pop(SasOutcome.matched);
          },
          label: s.t('sas.theyMatch'),
        ),
      ]),
    ),
  );
}

// 상대는 숫자를 한 자리씩 읽으므로 스크린 리더도 "1 2 3, 4 5 6"으로 읽게 라벨을 따로 줌
class _SasDigits extends StatelessWidget {
  const _SasDigits({required this.sas});

  final String sas;

  @override
  Widget build(BuildContext context) {
    final grouped = sas
        .replaceAllMapped(RegExp(r'.{3}'), (m) => '${m.group(0)} ')
        .trim();
    final spoken = grouped
        .split(' ')
        .map((group) => group.split('').join(' '))
        .join(', ');
    // FittedBox: 큰 글씨 접근성 설정에서도 여섯 자리가 고정폭 다이얼로그 밖으로 안 넘치게 줄어듦
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        // 고르기 복사도 막음: 이 코드는 채팅으로 보내 맞추는 게 아님 (위 복사 버튼을 안 두는 이유와 같음)
        child: Text(
          grouped,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _SasQr extends StatelessWidget {
  const _SasQr({required this.sas, required this.label});

  final String sas;
  final String label;

  // 흰 배경은 스캐너 가독성 때문에 의도적으로 유지. 다크 모드에서 밝은 얼룩으로 안 보이게 그림자를 줌
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.15),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    // 고정 크기 박스로 감쌈: AlertDialog가 intrinsic 측정할 때 QrImageView 내부 LayoutBuilder가 터지는 걸 막음
    child: SizedBox(
      width: 148,
      height: 148,
      child: Semantics(
        label: label,
        child: QrImageView(
          data: encodeSasQr(sas),
          version: QrVersions.auto,
          backgroundColor: Colors.white,
        ),
      ),
    ),
  );
}
