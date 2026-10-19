part of 'app.dart';

// 앱 글자 배율과 macOS '동작 줄이기'를 MediaQuery에 얹음
// macOS 임베더는 OS 글자 크기·동작 줄이기를 Flutter에 안 넘겨서 설정·⌘+/⌘−와 채널로 채움
mixin _AppAccessibility on ConsumerState<IntraGramApp> {
  bool _macReduceMotion = false;

  Widget _withAccessibility(BuildContext context, Widget child) {
    final scale = ref.watch(vaultSettingsProvider.select((s) => s.textScale));
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: scale == 1
            ? media.textScaler
            : TextScaler.linear(media.textScaler.scale(1) * scale),
        disableAnimations: media.disableAnimations || _macReduceMotion,
      ),
      child: child,
    );
  }

  void _stepTextSize(int step) {
    final notifier = ref.read(vaultSettingsProvider.notifier);
    final current = ref.read(vaultSettingsProvider).textScale;
    unawaited(notifier.setTextScale(stepTextScale(current, step)));
  }

  void _readMacReduceMotion() {
    unawaited(
      OsPrivacy.macReduceMotion().then((value) {
        if (mounted && value != _macReduceMotion) {
          setState(() => _macReduceMotion = value);
        }
      }),
    );
  }
}
