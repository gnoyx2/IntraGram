part of 'settings_screen.dart';

class _LanguageTile extends ConsumerWidget {
  const _LanguageTile({required this.current});

  final String? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    return ListTile(
      leading: const Icon(Icons.language),
      title: Text(s.t('settings.language')),
      trailing: DropdownButton<String>(
        value: current ?? 'system',
        underline: const SizedBox.shrink(),
        onChanged: (value) => ref
            .read(localeControllerProvider.notifier)
            .setOverride(value == 'system' ? null : value),
        items: [
          DropdownMenuItem(
            value: 'system',
            child: Text(s.t('settings.langSystem')),
          ),
          DropdownMenuItem(
            value: 'ko',
            child: Text(s.t('settings.langKorean')),
          ),
          DropdownMenuItem(
            value: 'en',
            child: Text(s.t('settings.langEnglish')),
          ),
        ],
      ),
    );
  }
}
