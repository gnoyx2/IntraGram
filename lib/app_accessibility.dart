part of 'app.dart';

// 앱 글자 배율과 네이티브 접근성 변경을 테마·MediaQuery에 함께 반영함.
mixin _AppAccessibility on ConsumerState<IntraGramApp> {
  bool get _reduceTransparency => OsPrivacy.reduceTransparency.value;

  void _watchAccessibility() {
    OsPrivacy.reduceTransparency.addListener(_systemChanged);
    OsPrivacy.reduceMotion.addListener(_systemChanged);
    OsPrivacy.highContrast.addListener(_systemChanged);
    DisplayRegions.features.addListener(_systemChanged);
    unawaited(OsPrivacy.refreshAccessibility());
  }

  void _stopAccessibility() {
    OsPrivacy.reduceTransparency.removeListener(_systemChanged);
    OsPrivacy.reduceMotion.removeListener(_systemChanged);
    OsPrivacy.highContrast.removeListener(_systemChanged);
    DisplayRegions.features.removeListener(_systemChanged);
  }

  void _systemChanged() {
    if (mounted) setState(() {});
  }

  // 고대비 테마에도 투명도 줄이기를 넘김: 둘을 같이 켜도 OS가 고른 고대비 테마에서 한쪽이 빠지지 않음
  ThemeData _theme({required bool dark, bool highContrast = false}) => dark
      ? AppTheme.dark(
          highContrast: highContrast || OsPrivacy.highContrast.value,
          reduceTransparency: _reduceTransparency,
        )
      : AppTheme.light(
          highContrast: highContrast || OsPrivacy.highContrast.value,
          reduceTransparency: _reduceTransparency,
        );

  Widget _withAccessibility(BuildContext context, Widget child) {
    final scale = ref.watch(vaultSettingsProvider.select((s) => s.textScale));
    final media = MediaQuery.of(context);
    final regions = DisplayRegions.features.value;
    return MediaQuery(
      data: media.copyWith(
        textScaler: scale == 1
            ? media.textScaler
            : TextScaler.linear(media.textScaler.scale(1) * scale),
        disableAnimations:
            media.disableAnimations || OsPrivacy.reduceMotion.value,
        highContrast: media.highContrast || OsPrivacy.highContrast.value,
        // iOS 27.1+ 접는 iPhone의 접힘선을 Android처럼 넣음: 2단 나누기·테이블탑·대화상자 힌지 피하기가 그대로 씀
        displayFeatures: regions == null
            ? null
            : [...media.displayFeatures, ...regions],
      ),
      child: child,
    );
  }

  void _stepTextSize(int step) {
    final notifier = ref.read(vaultSettingsProvider.notifier);
    final current = ref.read(vaultSettingsProvider).textScale;
    unawaited(notifier.setTextScale(stepTextScale(current, step)));
  }
}
