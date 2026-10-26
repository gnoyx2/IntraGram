import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/constants.dart' show kAppName;
import 'package:intragram/features/home/widgets/home_sections.dart';
import 'package:intragram/features/settings/pin_dialog.dart';
import 'package:intragram/features/settings/privacy_screen.dart';
import 'package:intragram/features/settings/saved_chats_screen.dart';
import 'package:intragram/l10n/locale_controller.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/store/vault.dart' show VaultSettings, kTextScales;
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';
import 'package:intragram/widgets/boxed_list.dart';
import 'package:intragram/widgets/readable_list.dart';

part 'settings_app.dart';
part 'settings_privacy.dart';
part 'settings_language.dart';
part 'settings_connection.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  // 이름이 있어야 단축키·메뉴 막대가 같은 화면을 두 번 쌓지 않음
  static Route<void> route() => MaterialPageRoute<void>(
    settings: const RouteSettings(name: 'settings'),
    builder: (_) => const SettingsScreen(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(vaultSettingsProvider);
    final notifier = ref.read(vaultSettingsProvider.notifier);
    final s = S.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings.title'))),
      body: ReadableList(
        children: [
          _PrivacySection(settings: settings, notifier: notifier),
          SectionHeader(s.t('settings.largeMessages')),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.t('settings.largeMessagesSub'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                SegmentedButton<LargeMessageMode>(
                  direction:
                      MediaQuery.sizeOf(context).width < 480 &&
                          MediaQuery.textScalerOf(context).scale(14) > 20
                      ? Axis.vertical
                      : Axis.horizontal,
                  style: SegmentedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  segments: [
                    ButtonSegment(
                      value: LargeMessageMode.inline,
                      label: Text(s.t('settings.large.inline')),
                    ),
                    ButtonSegment(
                      value: LargeMessageMode.unlimited,
                      label: Text(s.t('settings.large.unlimited')),
                    ),
                    ButtonSegment(
                      value: LargeMessageMode.spillToFile,
                      label: Text(s.t('settings.large.file')),
                    ),
                  ],
                  selected: {settings.largeMessageMode},
                  onSelectionChanged: (sel) =>
                      notifier.setLargeMessageMode(sel.first),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  switch (settings.largeMessageMode) {
                    LargeMessageMode.inline => s.t('settings.large.inlineDesc'),
                    LargeMessageMode.unlimited => s.t(
                      'settings.large.unlimitedDesc',
                    ),
                    LargeMessageMode.spillToFile => s.t(
                      'settings.large.fileDesc',
                    ),
                  },
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _AppSection(settings: settings),
          _ConnectionSection(settings: settings, notifier: notifier),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: Text(s.t('settings.eraseSaved')),
              onPressed: () => _confirmErase(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmErase(BuildContext context, WidgetRef ref) async {
    final s = S.of(context);
    final cupertino = isCupertinoDialog(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        cupertino: cupertino,
        title: Text(s.t('settings.eraseTitle')),
        content: Text(s.t('settings.eraseBody')),
        actions: dialogActions(dialogContext, [
          AdaptiveDialogAction(
            cupertino: cupertino,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: s.t('common.cancel'),
          ),
          AdaptiveDialogAction(
            cupertino: cupertino,
            emphasis: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: s.t('settings.erase'),
          ),
        ]),
      ),
    );
    if (ok == true && context.mounted) {
      await ref.read(vaultSettingsProvider.notifier).setEnabled(false);
    }
  }
}
