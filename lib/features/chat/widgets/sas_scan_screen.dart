import 'package:flutter/material.dart';

import 'package:intragram/core/haptics.dart';
import 'package:intragram/core/sas_qr.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/scanner_view.dart';

// 일치하면 true, 숫자가 다른 보안 코드면 false로 pop (호출부가 확인이나 불일치 경고로 이어감).
// 보안 코드가 아닌 QR은 무시하고 계속 스캔. 모바일만 (데스크톱은 소리 내어 읽기)
class SasScanScreen extends StatefulWidget {
  const SasScanScreen({required this.expected, super.key});

  final String expected;

  @override
  State<SasScanScreen> createState() => _SasScanScreenState();
}

class _SasScanScreenState extends State<SasScanScreen> {
  bool _onCode(String raw) {
    final verdict = sasScanVerdict(raw, widget.expected);
    if (verdict == null || !mounted) return false;
    if (verdict) {
      AppHaptics.mediumImpact();
    } else {
      AppHaptics.heavyImpact();
    }
    Navigator.of(context).pop(verdict);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).t('sasScan.title'))),
      body: ScannerView(
        onCode: _onCode,
        hint: S.of(context).t('sasScan.hint'),
        noCamera: S.of(context).t('sasScan.noCamera'),
        reticleSide: 220,
        reticleRadius: AppRadius.md,
      ),
    );
  }
}
