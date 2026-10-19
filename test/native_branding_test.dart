import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/theme/app_theme.dart';

void _png(String path, int size, {bool opaque = false}) {
  final bytes = File(path).readAsBytesSync();
  final header = ByteData.sublistView(bytes);
  expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10], reason: path);
  expect(header.getUint32(16), size, reason: path);
  expect(header.getUint32(20), size, reason: path);
  if (opaque) expect(bytes[25], 2, reason: '$path must be RGB without alpha');
}

void main() {
  test('Android density resources and Linux PNG have the expected sizes', () {
    for (final (density, factor) in [
      ('mdpi', 1.0),
      ('hdpi', 1.5),
      ('xhdpi', 2.0),
      ('xxhdpi', 3.0),
      ('xxxhdpi', 4.0),
    ]) {
      final base = 'android/app/src/main/res/mipmap-$density';
      for (final (name, size) in [
        ('ic_launcher', 48),
        ('ic_launcher_foreground', 108),
        ('ic_launcher_monochrome', 108),
        ('ic_launch_mark', 200),
      ]) {
        _png('$base/$name.png', (size * factor).round());
      }
      // 알림 small icon은 24dp 흰 실루엣(알파 있음)
      _png(
        'android/app/src/main/res/drawable-$density/ic_stat_intragram.png',
        (24 * factor).round(),
      );
    }
    for (final size in [16, 24, 32, 48, 64, 128, 256, 512]) {
      _png('linux/icons/hicolor/${size}x$size/apps/intragram.png', size);
    }
  });

  for (final platform in ['ios', 'macos']) {
    test('$platform icon catalog slots all have matching PNGs', () {
      final base = '$platform/Runner/Assets.xcassets/AppIcon.appiconset';
      final catalog = jsonDecode(
        File('$base/Contents.json').readAsStringSync(),
      );
      for (final image in catalog['images'] as List) {
        final size = double.parse((image['size'] as String).split('x').first);
        final scale = int.parse((image['scale'] as String).replaceAll('x', ''));
        _png(
          '$base/${image['filename']}',
          (size * scale).round(),
          opaque: platform == 'ios',
        );
      }
    });
  }

  test('Windows ICO contains seven correctly sized PNG entries', () {
    final bytes = File(
      'windows/runner/resources/app_icon.ico',
    ).readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    expect(data.getUint16(2, Endian.little), 1);
    expect(data.getUint16(4, Endian.little), 7);
    const sizes = [16, 24, 32, 48, 64, 128, 256];
    for (var i = 0; i < sizes.length; i++) {
      final entry = 6 + i * 16;
      expect(bytes[entry] == 0 ? 256 : bytes[entry], sizes[i]);
      expect(bytes[entry + 1] == 0 ? 256 : bytes[entry + 1], sizes[i]);
      final offset = data.getUint32(entry + 12, Endian.little);
      final length = data.getUint32(entry + 8, Endian.little);
      expect(offset + length, lessThanOrEqualTo(bytes.length));
      expect(data.getUint32(offset + 16), sizes[i]);
      expect(data.getUint32(offset + 20), sizes[i]);
    }
  });

  test(
    'native light and dark launch backgrounds match the Flutter first frame',
    () {
      final catalog = jsonDecode(
        File(
          'ios/Runner/Assets.xcassets/LaunchBackground.colorset/Contents.json',
        ).readAsStringSync(),
      );
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final dark = theme.brightness.name == 'dark';
        final argb = theme.scaffoldBackgroundColor.toARGB32();
        final rgb = (argb & 0xFFFFFF)
            .toRadixString(16)
            .padLeft(6, '0')
            .toUpperCase();
        final base = 'android/app/src/main/res/values${dark ? '-night' : ''}';
        expect(File('$base/colors.xml').readAsStringSync(), contains('#$rgb'));
        expect(
          File('$base/styles.xml').readAsStringSync(),
          contains(
            '<item name="android:windowBackground">@color/launch_bg</item>',
          ),
        );
        expect(
          File('$base-v31/styles.xml').readAsStringSync(),
          contains(
            '<item name="android:windowSplashScreenBackground">@color/launch_bg</item>',
          ),
        );
        final colors = catalog['colors'] as List;
        final components = colors.firstWhere(
          (c) => (c['appearances'] != null) == dark,
        )['color']['components'];
        final channels = [
          for (final key in ['red', 'green', 'blue'])
            (double.parse(components[key]) * 255).round(),
        ];
        expect(channels, [(argb >> 16) & 255, (argb >> 8) & 255, argb & 255]);
      }
    },
  );
  // 밝은 마크는 흰 바탕에서 안 보임(대비 1.25:1): 라이트 실행 화면만 남색 판 위에 올리고 다크는 투명 마크 그대로
  test('the light launch screen puts the mark on a navy plate', () {
    const res = 'android/app/src/main/res';
    String read(String path) => File(path).readAsStringSync();
    for (final dir in ['drawable', 'drawable-v21']) {
      expect(
        read('$res/$dir/launch_background.xml'),
        contains('launch_mark_plate'),
      );
      final night = dir.replaceFirst('drawable', 'drawable-night');
      expect(
        read('$res/$night/launch_background.xml'),
        isNot(contains('plate')),
      );
    }
    expect(
      read('$res/values-v31/styles.xml'),
      contains('windowSplashScreenIconBackgroundColor'),
    );
    expect(
      read('$res/values-night-v31/styles.xml'),
      isNot(contains('windowSplashScreenIconBackgroundColor')),
    );
    final images =
        jsonDecode(
              read(
                'ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json',
              ),
            )['images']
            as List;
    expect(
      images.where((i) => i['appearances'] != null).map((i) => i['filename']),
      [
        'LaunchImageDark.png',
        'LaunchImageDark@2x.png',
        'LaunchImageDark@3x.png',
      ],
    );
  });
}
