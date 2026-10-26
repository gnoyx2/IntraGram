import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:intragram/theme/tokens.dart';

final List<TextInputFormatter> kPinInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
];

// 네이티브 iOS에는 플로팅 라벨이 없어서 Cupertino면 라벨을 상단 Text로 분리함
Widget pinField(
  BuildContext context, {
  required bool cupertino,
  required TextEditingController controller,
  required String label,
  bool autofocus = false,
  ValueChanged<String>? onSubmitted,
}) {
  if (!cupertino) {
    return TextField(
      enableIMEPersonalizedLearning: false,
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      keyboardType: TextInputType.visiblePassword,
      inputFormatters: kPinInputFormatters,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(labelText: label),
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: AppSpacing.xs),
      CupertinoTextField(
        enableIMEPersonalizedLearning: false,
        controller: controller,
        autofocus: autofocus,
        obscureText: true,
        keyboardType: TextInputType.visiblePassword,
        inputFormatters: kPinInputFormatters,
        onSubmitted: onSubmitted,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(color: CupertinoColors.separator),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
      ),
    ],
  );
}
