import 'package:flutter/material.dart';

import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/readable_list.dart';

// 개인정보 처리 방침. 스토어 심사가 요구하는 앱 안 방침이라 인터넷 링크 없이 로컬 문구로 보여 줌
// 저장소의 PRIVACY.md와 같은 내용 (test/ui/privacy_screen_test.dart가 두 쪽을 맞춰 봄)
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  // 'privacy.<key>Title'·'privacy.<key>Body' 문구 쌍의 순서
  static const List<String> sections = [
    'noServer',
    'onDevice',
    'network',
    'discovery',
    'permissions',
    'thirdParty',
    'contact',
  ];

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('privacy.title'))),
      body: ReadableList(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          for (final key in sections) ...[
            Text(s.t('privacy.${key}Title'), style: textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(s.t('privacy.${key}Body'), style: textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}
