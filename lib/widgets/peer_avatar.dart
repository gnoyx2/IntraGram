import 'package:flutter/material.dart';

import 'package:intragram/core/platform_icons.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

// 프로필 사진이 없는 피어용 이니셜 원형 아바타
// 색은 이름이 아니라 기기 ID 해시를 따라가서 이름을 바꿔도 그대로임
// 라이트는 파스텔 듀오톤에 짙은 글자, 다크는 깊은 듀오톤에 밝은 글자
// 명도 값은 360개 색조 전부에서 글자 대비 7:1 이상이 나오게 맞춘 값
// platform을 주면 오른쪽 아래에 기기 배지를 달고 스크린 리더에 기기 종류를 읽어줌
class PeerAvatar extends StatelessWidget {
  const PeerAvatar({
    super.key,
    required this.peerId,
    required this.alias,
    this.platform,
    this.radius = 22,
  });

  final String peerId;
  final String alias;
  final String? platform;
  final double radius;

  // FNV-1a 32비트. 플랫폼·실행마다 같은 값이 나와야 해서 String.hashCode를 안 씀
  static int hueFor(String peerId) {
    var hash = 0x811C9DC5;
    for (final unit in peerId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash % 360;
  }

  static LinearGradient gradientFor(String peerId, Brightness brightness) {
    final hue = hueFor(peerId).toDouble();
    final dark = brightness == Brightness.dark;
    HSLColor tone(double shift, double saturation, double lightness) =>
        HSLColor.fromAHSL(1, (hue + shift) % 360, saturation, lightness);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        (dark ? tone(0, 0.42, 0.27) : tone(0, 0.70, 0.88)).toColor(),
        (dark ? tone(36, 0.48, 0.19) : tone(36, 0.62, 0.80)).toColor(),
      ],
    );
  }

  static String initialsFor(String alias) {
    final words = alias.trim().split(RegExp(r'[\s_-]+'));
    final letters = words.where((word) => word.isNotEmpty).take(2);
    return letters.isEmpty
        ? '?'
        : letters.map((word) => word.characters.first).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final face = Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradientFor(peerId, scheme.brightness),
        border: Border.all(
          color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.08),
          width: AppBorder.hairline,
        ),
      ),
      child: Text(
        initialsFor(alias),
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: radius * 0.68,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          height: 1,
          color: dark ? const Color(0xFFF1F5FC) : const Color(0xFF14233B),
        ),
      ),
    );
    final device = platform;
    if (device == null) return ExcludeSemantics(child: face);
    final badge = radius * 0.78;
    return Semantics(
      label: S.of(context).t('a11y.platformDevice', {'platform': device}),
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: radius * 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              face,
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: badge,
                  height: badge,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.surfaceContainerHighest,
                    border: Border.all(color: scheme.surface, width: 2),
                  ),
                  child: Icon(
                    platformIcon(device),
                    size: badge * 0.58,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
