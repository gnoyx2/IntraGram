part of 'settings_screen.dart';

// 백그라운드 자동 잠금 선택지(분). 저장된 값이 목록 밖이면 그 값도 같이 보여 줌
const List<int> _kAutoLockChoices = [1, 5, 15, 30, 60];

// 개인정보 절: 이 기기에 보관(기본 꺼짐)과 보관 범위·PIN·저장된 대화
class _PrivacySection extends StatelessWidget {
  const _PrivacySection({required this.settings, required this.notifier});

  final VaultSettings settings;
  final VaultSettingsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(s.t('settings.sectionPrivacy')),
        BoxedList(
          children: [
            SwitchListTile.adaptive(
              title: Text(s.t('settings.keepChats')),
              subtitle: Text(s.t('settings.keepChatsSub')),
              value: settings.enabled,
              onChanged: notifier.setEnabled,
            ),
            SwitchListTile.adaptive(
              title: Text(s.t('settings.messages')),
              subtitle: Text(s.t('settings.messagesSub')),
              value: settings.keepMessages,
              onChanged: settings.enabled ? notifier.setKeepMessages : null,
            ),
            SwitchListTile.adaptive(
              title: Text(s.t('settings.fileHistory')),
              subtitle: Text(s.t('settings.fileHistorySub')),
              value: settings.keepTransfers,
              onChanged: settings.enabled ? notifier.setKeepTransfers : null,
            ),
            ListTile(
              enabled: settings.enabled,
              leading: Icon(
                settings.pinProtected ? Icons.lock : Icons.lock_open,
              ),
              title: Text(s.t('settings.pinProtect')),
              subtitle: Text(
                settings.pinProtected
                    ? s.t('settings.pinProtectOnSub')
                    : s.t('settings.pinProtectOffSub'),
              ),
              trailing: settings.pinProtected
                  ? const Icon(Icons.chevron_right)
                  : Text(s.t('settings.set')),
              onTap: settings.enabled
                  ? () => PinDialog.show(
                      context,
                      alreadySet: settings.pinProtected,
                    )
                  : null,
            ),
            // PIN이 있을 때만: 백그라운드에서 이 시간이 지나면 다시 PIN을 물음
            if (settings.enabled && settings.pinProtected)
              ListTile(
                leading: const Icon(Icons.lock_clock_outlined),
                title: Text(s.t('settings.autoLock')),
                trailing: DropdownButton<int>(
                  value: settings.autoLockMinutes,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final n in {
                      ..._kAutoLockChoices,
                      settings.autoLockMinutes,
                    }.toList()..sort())
                      DropdownMenuItem(
                        value: n,
                        child: Text(
                          s.t('settings.autoLockMinutes', {'n': '$n'}),
                        ),
                      ),
                  ],
                  onChanged: (n) {
                    if (n != null) notifier.setAutoLockMinutes(n);
                  },
                ),
              ),
            ListTile(
              enabled: settings.enabled,
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(s.t('settings.savedChats')),
              subtitle: Text(s.t('settings.savedChatsSub')),
              trailing: const Icon(Icons.chevron_right),
              onTap: settings.enabled
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SavedChatsScreen(),
                      ),
                    )
                  : null,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xs,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
          child: Text(
            s.t('settings.restoredNote'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
