import 'dart:io' show InternetAddress;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:intragram/core/haptics.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';

// 에어갭 검사 두 개 중 첫 번째: 리터럴 IPv4가 아니면 거부하고(InternetAddress.tryParse가
// router.local 같은 이름을 거부) RFC 1918 + link-local 밖도 거부함
// 레지스트리가 소켓을 열기 전에 assertReachable을 또 돌려서 여기 버그가 있어도 패킷은 못 나감
// 이 레이어는 실패한 연결 대신 읽을 수 있는 이유를 바로 주려는 것
class ManualConnectDialog extends StatefulWidget {
  const ManualConnectDialog({super.key});

  @override
  State<ManualConnectDialog> createState() => _ManualConnectDialogState();
}

class _ManualConnectDialogState extends State<ManualConnectDialog> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '$kPreferredPort',
  );
  String? _error;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _submit() {
    final s = S.of(context);
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    if (InternetAddress.tryParse(host) == null) {
      setState(() => _error = s.t('manualConnect.notIpv4'));
      return;
    }
    if (!NetworkGuard.isLinkLocalOrPrivate(host)) {
      setState(() => _error = s.t('manualConnect.notPrivate', {'host': host}));
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = s.t('manualConnect.badPort'));
      return;
    }
    AppHaptics.selectionClick();
    Navigator.of(context).pop((host: host, port: port));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cupertino = isCupertinoDialog(context);

    final fields = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(s.t('manualConnect.body')),
        const SizedBox(height: AppSpacing.md),
        _adaptiveField(
          context,
          cupertino: cupertino,
          controller: _hostController,
          label: s.t('manualConnect.peerIpLabel'),
          placeholder: '192.168.0.12',
          autofocus: true,
          // 숫자 키보드면 IPv6(콜론 + 16진 문자)를 입력할 수 없음
          keyboardType: TextInputType.text,
          autocorrect: false,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: AppSpacing.md),
        _adaptiveField(
          context,
          cupertino: cupertino,
          controller: _portController,
          label: s.t('manualConnect.portLabel'),
          keyboardType: TextInputType.number,
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );

    return AlertDialog.adaptive(
      title: Text(s.t('home.connectByIp')),
      // Cupertino 경로는 CupertinoTextField라
      // Material 조상이 필요 없고 Material 경로의 TextField만
      // debugCheckHasMaterial에 걸림. transparency 타입으로 시각 변화 없이 요구만 충족시킴
      content: cupertino
          ? fields
          : Material(type: MaterialType.transparency, child: fields),
      actions: dialogActions(context, [
        AdaptiveDialogAction(
          cupertino: cupertino,
          onPressed: () => Navigator.of(context).pop(),
          label: s.t('common.cancel'),
        ),
        AdaptiveDialogAction(
          cupertino: cupertino,
          emphasis: true,
          onPressed: _submit,
          label: s.t('manualConnect.connect'),
        ),
      ]),
    );
  }
}

// Cupertino면 라벨을 위 Text로 따로 두고 테두리 박스 CupertinoTextField를 씀
// (네이티브 iOS엔 Material식 떠있는 라벨이 없음)
Widget _adaptiveField(
  BuildContext context, {
  required bool cupertino,
  required TextEditingController controller,
  required String label,
  required ValueChanged<String> onSubmitted,
  String? placeholder,
  bool autofocus = false,
  TextInputType? keyboardType,
  bool autocorrect = true,
}) {
  if (cupertino) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: AppSpacing.xs),
        CupertinoTextField(
          enableIMEPersonalizedLearning: false,
          controller: controller,
          autofocus: autofocus,
          keyboardType: keyboardType,
          autocorrect: autocorrect,
          textCapitalization: TextCapitalization.none,
          placeholder: placeholder,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: CupertinoColors.separator),
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          onSubmitted: onSubmitted,
        ),
      ],
    );
  }
  return TextField(
    enableIMEPersonalizedLearning: false,
    controller: controller,
    autofocus: autofocus,
    keyboardType: keyboardType,
    autocorrect: autocorrect,
    textCapitalization: TextCapitalization.none,
    decoration: InputDecoration(labelText: label, hintText: placeholder),
    onSubmitted: onSubmitted,
  );
}
