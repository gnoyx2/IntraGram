part of 'settings_screen.dart';

// 연결 절: 모르는 기기 거절(모든 플랫폼)과 Android 백그라운드 연결 유지
class _ConnectionSection extends ConsumerWidget {
  const _ConnectionSection({required this.settings, required this.notifier});

  final VaultSettings settings;
  final VaultSettingsNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final service = ref.read(foregroundServiceProvider);
    return Column(
      children: [
        SectionHeader(s.t('settings.sectionConnection')),
        BoxedList(
          children: [
            SwitchListTile.adaptive(
              title: Text(s.t('settings.onlyChatsIStart')),
              subtitle: Text(s.t('settings.onlyChatsIStartSub')),
              value: settings.onlyChatsIStart,
              onChanged: notifier.setOnlyChatsIStart,
            ),
            // iOS엔 백그라운드 연결 유지가 없음: 끊기는 이유를 미리 알림
            if (defaultTargetPlatform == TargetPlatform.iOS)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(s.t('settings.iosForegroundOnly')),
              ),
            // 시스템이 막아 설정이 저절로 꺼졌으면 스위치 밑에 이유를 둠 (말없이 꺼지면 왜인지 모름)
            if (defaultTargetPlatform == TargetPlatform.android)
              ValueListenableBuilder<bool>(
                valueListenable: service.stoppedBySystem,
                builder: (context, stopped, _) => SwitchListTile.adaptive(
                  title: Text(s.t('settings.stayConnected')),
                  subtitle: Text(
                    stopped && !settings.stayConnectedInBackground
                        ? '${s.t('settings.stayConnectedSub')}\n'
                              '${s.t('settings.stayConnectedStopped')}'
                        : s.t('settings.stayConnectedSub'),
                  ),
                  value: settings.stayConnectedInBackground,
                  onChanged: (value) {
                    service.stoppedBySystem.value = false;
                    notifier.setStayConnected(value);
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }
}
