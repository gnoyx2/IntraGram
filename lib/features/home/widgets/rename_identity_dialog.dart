import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';

// 확정하면 (alias, save)를 pop. alias가 빈 문자열이면 호출부가 랜덤으로 리셋하라는 신호, 취소하면 null
class RenameIdentityDialog extends StatefulWidget {
  const RenameIdentityDialog({required this.currentAlias, super.key});

  final String currentAlias;

  @override
  State<RenameIdentityDialog> createState() => _RenameIdentityDialogState();
}

class _RenameIdentityDialogState extends State<RenameIdentityDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.currentAlias,
  );

  // 일부러 이름을 정하는 거라 다음에도 쓰는 쪽이 기본값
  bool _save = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.of(context).pop((alias: _controller.text.trim(), save: _save));

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cupertino = isCupertinoDialog(context);

    final field = cupertino
        ? CupertinoTextField(
            enableIMEPersonalizedLearning: false,
            controller: _controller,
            autofocus: true,
            maxLength: 32,
            placeholder: s.t('identity.renameHint'),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              border: Border.all(color: CupertinoColors.separator),
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            onSubmitted: (_) => _submit(),
          )
        : TextField(
            enableIMEPersonalizedLearning: false,
            controller: _controller,
            autofocus: true,
            maxLength: 32,
            decoration: InputDecoration(
              hintText: s.t('identity.renameHint'),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          );

    final toggleRow = Row(
      children: [
        Expanded(child: Text(s.t('identity.saveToggle'))),
        cupertino
            ? CupertinoSwitch(
                value: _save,
                onChanged: (v) => setState(() => _save = v),
              )
            : Checkbox(
                value: _save,
                onChanged: (v) => setState(() => _save = v ?? false),
              ),
      ],
    );

    return AppAlertDialog(
      cupertino: cupertino,
      title: Text(s.t('identity.renameTitle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          field,
          const SizedBox(height: AppSpacing.sm),
          toggleRow,
        ],
      ),
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
          label: s.t('identity.renameConfirm'),
        ),
      ]),
    );
  }
}
