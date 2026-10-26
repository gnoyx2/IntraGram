import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/core/haptics.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';

import 'pin_field.dart';

export 'pin_field.dart' show kPinInputFormatters;

// 새 PIN은 6자 이상, 영숫자 혼합 가능. 예전 4~5자리 숫자 PIN도 게이트에선 그대로 열림
const int kMinPinLength = 6;

// PIN을 걸면 다음 저장부터 vault.json이 봉인되고, 떼면 평문으로 돌아감. 보관소가 꺼져 있으면 안 열림
// duress면 협박 대비 PIN을 설정함: 이걸로 열면 빈 세션이 뜨고 변경은 저장 안 됨
class PinDialog extends ConsumerStatefulWidget {
  const PinDialog({required this.alreadySet, this.duress = false, super.key});

  final bool alreadySet;
  final bool duress;

  static Future<void> show(
    BuildContext context, {
    required bool alreadySet,
    bool duress = false,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PinDialog(alreadySet: alreadySet, duress: duress),
  );

  @override
  ConsumerState<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends ConsumerState<PinDialog> {
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = S.of(context);
    final pin = _pin.text.trim();
    if (pin.length < kMinPinLength) {
      AppHaptics.mediumImpact();
      setState(() => _error = s.t('pin.tooShort'));
      return;
    }
    if (pin != _confirm.text.trim()) {
      AppHaptics.mediumImpact();
      setState(() => _error = s.t('pin.mismatch'));
      return;
    }
    setState(() => _busy = true);
    try {
      final notifier = ref.read(vaultSettingsProvider.notifier);
      final ok = widget.duress
          ? await notifier.setDecoyPin(pin: pin)
          : await notifier.setPinProtected(value: true, pin: pin);
      if (!mounted) return;
      if (!ok) {
        AppHaptics.mediumImpact();
        setState(() => _error = s.t('pin.mustDiffer'));
        return;
      }
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final notifier = ref.read(vaultSettingsProvider.notifier);
      if (widget.duress) {
        await notifier.setDecoyPin(pin: null);
      } else {
        await notifier.setPinProtected(value: false);
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cupertino = isCupertinoDialog(context);

    final pin = pinField(
      context,
      cupertino: cupertino,
      controller: _pin,
      label: s.t('pin.pinLabel'),
      autofocus: true,
    );
    final confirm = pinField(
      context,
      cupertino: cupertino,
      controller: _confirm,
      label: s.t('pin.confirmLabel'),
      onSubmitted: (_) => _save(),
    );

    final fields = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.duress ? s.t('pin.duressBody') : s.t('pin.body'),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        pin,
        const SizedBox(height: AppSpacing.md),
        confirm,
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (widget.alreadySet && !widget.duress)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.shield_outlined, size: 18),
              label: Text(s.t('pin.duressTitle')),
              onPressed: _busy
                  ? null
                  : () => PinDialog.show(
                      context,
                      alreadySet: false,
                      duress: true,
                    ),
            ),
          ),
      ],
    );

    return PopScope(
      canPop: !_busy,
      child: AppAlertDialog(
        cupertino: cupertino,
        title: Text(
          widget.duress
              ? s.t('pin.duressTitle')
              : widget.alreadySet
              ? s.t('pin.changeTitle')
              : s.t('pin.setTitle'),
        ),
        // Material 경로의 TextField만 Material 조상이 필요함 (manual_connect_dialog.dart 참고)
        content: cupertino
            ? fields
            : Material(type: MaterialType.transparency, child: fields),
        actions: dialogActions(
          context,
          leading: widget.alreadySet || widget.duress
              ? AdaptiveDialogAction(
                  cupertino: cupertino,
                  onPressed: _busy ? null : _remove,
                  label: widget.duress
                      ? s.t('common.remove')
                      : s.t('pin.removePin'),
                )
              : null,
          [
            AdaptiveDialogAction(
              cupertino: cupertino,
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              label: s.t('common.cancel'),
            ),
            AdaptiveDialogAction(
              cupertino: cupertino,
              emphasis: true,
              onPressed: _busy ? null : _save,
              label: s.t('common.save'),
            ),
          ],
        ),
      ),
    );
  }
}
