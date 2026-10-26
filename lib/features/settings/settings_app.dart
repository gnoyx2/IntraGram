part of 'settings_screen.dart';

class _AppSection extends StatelessWidget {
  const _AppSection({required this.settings});

  final VaultSettings settings;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(s.t('settings.sectionApp')),
        BoxedList(
          children: [
            _LanguageTile(current: settings.langOverride),
            // 폰·태블릿은 OS 글자 크기를 그대로 따름. 데스크톱은 macOS처럼 OS 값이 안 들어오거나
            // 창 단위로 키울 길이 없어서 앱 배율을 둠
            if (_isDesktop(context)) _TextSizeTile(current: settings.textScale),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(s.t('privacy.title')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(s.t('settings.licenses')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  showLicensePage(context: context, applicationName: kAppName),
            ),
          ],
        ),
      ],
    );
  }

  static bool _isDesktop(BuildContext context) =>
      switch (Theme.of(context).platform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => true,
        _ => false,
      };
}

class _TextSizeTile extends ConsumerWidget {
  const _TextSizeTile({required this.current});

  final double current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final mac = Theme.of(context).platform == TargetPlatform.macOS;
    return ListTile(
      leading: const Icon(Icons.format_size),
      title: Text(s.t('settings.textSize')),
      subtitle: Text(
        s.t('settings.textSizeKeys', {
          'keys': mac ? '⌘+ · ⌘− · ⌘0' : 'Ctrl++ · Ctrl+- · Ctrl+0',
        }),
      ),
      trailing: DropdownButton<double>(
        value: kTextScales.contains(current) ? current : 1.0,
        underline: const SizedBox.shrink(),
        onChanged: (value) {
          if (value != null) {
            ref.read(vaultSettingsProvider.notifier).setTextScale(value);
          }
        },
        items: [
          for (final value in kTextScales)
            DropdownMenuItem(
              value: value,
              child: Text('${(value * 100).round()}%'),
            ),
        ],
      ),
    );
  }
}
