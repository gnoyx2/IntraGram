import 'package:flutter/material.dart';

import 'package:intragram/core/haptics.dart';
import 'package:intragram/core/peer_code.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/scanner_view.dart';

// 모바일만. parsePeerCode가 WAN·호스트명·형식이 틀린 코드를 걸러서 계속 스캔하고, 첫 유효 코드에서 PeerCode를 들고 pop함
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _onCode(String raw) {
    final target = parsePeerCode(raw);
    if (target == null || !mounted) return false;
    AppHaptics.mediumImpact();
    Navigator.of(context).pop(target);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // 짧은 변의 62%를 180~280으로 묶음 (작은 폰에서 안 넘치고 태블릿·폴더블에서 너무 안 커짐)
    final reticleSide = (MediaQuery.sizeOf(context).shortestSide * 0.62)
        .clamp(180, 280)
        .toDouble();
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).t('home.scanDevice'))),
      body: ScannerView(
        onCode: _onCode,
        hint: S.of(context).t('scanScreen.hint'),
        noCamera: S.of(context).t('scanScreen.noCamera'),
        reticleSide: reticleSide,
        reticleRadius: AppRadius.lg,
      ),
    );
  }
}
