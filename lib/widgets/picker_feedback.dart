import 'dart:async';

import 'package:flutter/material.dart';

import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/registry/incoming_path_resolver.dart';

// 파일·폴더 대화상자를 못 띄웠을 때 원인 안내 (Linux에 xdg-desktop-portal 백엔드가 없는 게 대부분)
void showPickerUnavailable(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(S.of(context).t('picker.unavailable'))),
  );
}

// 수락은 저장 폴더를 물을 수 있어서 대화상자 실패를 화면에 알림 (나머지 실패는 타일 상태가 보여 줌)
void acceptWithPicker(BuildContext context, Future<void> Function() accept) {
  final messenger = ScaffoldMessenger.of(context);
  final message = S.of(context).t('picker.unavailable');
  unawaited(
    accept().catchError(
      (Object _) =>
          messenger.showSnackBar(SnackBar(content: Text(message))).closed,
      test: (error) => error is PickerUnavailableException,
    ),
  );
}
