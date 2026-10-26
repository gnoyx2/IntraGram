import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/peer_code.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

class PortalQr extends ConsumerWidget {
  const PortalQr({required this.url, super.key});

  final String url;

  // 흰 배경은 스캐너가 잘 읽게 일부러 둠. 다크 표면에서 얼룩이 아니라 카드로 보이게 그림자를 줌
  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
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
        child: Semantics(
          label: S.of(context).t('a11y.qrCodeUrl'),
          child: QrImageView(
            // 앱이 찍으면 이 기기 신원으로 고정됨. 브라우저는 #t만 읽고 p는 무시함
            data: portalCodeWithPeer(url, ref.read(appIdentityProvider).peerId),
            version: QrVersions.auto,
            size: 208,
            backgroundColor: Colors.white,
          ),
        ),
      ),
    ),
  );
}
