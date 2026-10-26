import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:intragram/core/network_guard.dart';
import 'package:intragram/core/peer_code.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';

// 게스트 포털과 무관하게 늘 보여 줄 수 있는 앱끼리 연결 QR (주소 + 이 기기 신원)
// 사설 IPv4가 아니면 스캐너가 어차피 거절해서 코드 대신 이유를 보여 줌
Future<void> showDeviceCodeDialog(
  BuildContext context, {
  required String? host,
  required int? port,
  required String peerId,
}) {
  final s = S.of(context);
  final endpoint = host == null || port == null
      ? null
      : NetworkGuard.parsePeerEndpoint(host, port);
  return showAdaptiveDialog<void>(
    context: context,
    builder: (dialogContext) => AppAlertDialog(
      cupertino: isCupertinoDialog(dialogContext),
      title: Text(s.t('deviceCode.title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (endpoint != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                color: Colors.white,
                child: Semantics(
                  label: s.t('deviceCode.title'),
                  child: SizedBox.square(
                    dimension: 200,
                    child: QrImageView(
                      data: deviceCode(
                        host: endpoint.host,
                        port: endpoint.port,
                        peerId: peerId,
                      ),
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(s.t('deviceCode.body'), textAlign: TextAlign.center),
            ] else
              Text(s.t('deviceCode.unavailable'), textAlign: TextAlign.center),
          ],
        ),
      ),
      actions: dialogActions(dialogContext, [
        AdaptiveDialogAction(
          cupertino: isCupertinoDialog(dialogContext),
          label: s.t('common.close'),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ]),
    ),
  );
}
