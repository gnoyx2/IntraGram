#!/usr/bin/env bash
# macOS sips·Swift·Dart로 아이콘과 실행 화면 표시를 만듦.
# 먼저 flutter test test/tool/icon_master.dart를 실행해야 함.
# test/tool/icon_master.dart를 바꾸면 다시 실행해야 함.
set -euo pipefail
cd "$(dirname "$0")/.."

MASTER=build/icon_master/master_full.png
MASTER_MACOS=build/icon_master/master_macos.png
MASTER_WINDOWS=build/icon_master/master_windows.png
FOREGROUND=build/icon_master/foreground.png
MONOCHROME=build/icon_master/monochrome.png
LAUNCH_MARK=build/icon_master/launch_mark.png
NOTIFICATION=build/icon_master/notification.png

SMALL=(build/icon_master/small_16.png build/icon_master/small_24.png build/icon_master/small_32.png)

for f in "$MASTER" "$MASTER_MACOS" "$MASTER_WINDOWS" "$FOREGROUND" "$MONOCHROME" "$LAUNCH_MARK" "$NOTIFICATION" "${SMALL[@]}"; do
  if [ ! -f "$f" ]; then
    echo "Missing $f — run: flutter test test/tool/icon_master.dart" >&2
    exit 1
  fi
done

SRGB_PROFILE="/System/Library/ColorSync/Profiles/sRGB Profile.icc"

echo "== sRGB color-match masters =="
for master in "$MASTER" "$MASTER_MACOS" "$MASTER_WINDOWS" "$FOREGROUND" "$MONOCHROME" "$LAUNCH_MARK" "${SMALL[@]}"; do
  sips --matchTo "$SRGB_PROFILE" "$master" >/dev/null
done

echo "== Android legacy mipmaps =="
for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density=${pair%%:*}; size=${pair##*:}
  sips -z "$size" "$size" "$MASTER" \
    --out "android/app/src/main/res/mipmap-$density/ic_launcher.png" >/dev/null
done

echo "== Android adaptive foreground + monochrome (108dp canvas / density) =="
for pair in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
  density=${pair%%:*}; size=${pair##*:}
  mkdir -p "android/app/src/main/res/mipmap-$density"
  sips -z "$size" "$size" "$FOREGROUND" \
    --out "android/app/src/main/res/mipmap-$density/ic_launcher_foreground.png" >/dev/null
  sips -z "$size" "$size" "$MONOCHROME" \
    --out "android/app/src/main/res/mipmap-$density/ic_launcher_monochrome.png" >/dev/null
done

echo "== Android launch mark =="
for pair in mdpi:200 hdpi:300 xhdpi:400 xxhdpi:600 xxxhdpi:800; do
  density=${pair%%:*}; size=${pair##*:}
  sips -z "$size" "$size" "$LAUNCH_MARK" \
    --out "android/app/src/main/res/mipmap-$density/ic_launch_mark.png" >/dev/null
done

echo "== Android notification small icon (24dp, white silhouette) =="
for pair in mdpi:24 hdpi:36 xhdpi:48 xxhdpi:72 xxxhdpi:96; do
  density=${pair%%:*}; size=${pair##*:}
  mkdir -p "android/app/src/main/res/drawable-$density"
  sips -z "$size" "$size" "$NOTIFICATION" \
    --out "android/app/src/main/res/drawable-$density/ic_stat_intragram.png" >/dev/null
done

echo "== Linux hicolor icons (16~32 small mark, 48+ from the 512 master) =="
for size in 16 24 32; do
  mkdir -p "linux/icons/hicolor/${size}x${size}/apps"
  cp "build/icon_master/small_$size.png" "linux/icons/hicolor/${size}x${size}/apps/intragram.png"
done
for size in 48 64 128 256; do
  mkdir -p "linux/icons/hicolor/${size}x${size}/apps"
  sips -z "$size" "$size" linux/icons/hicolor/512x512/apps/intragram.png \
    --out "linux/icons/hicolor/${size}x${size}/apps/intragram.png" >/dev/null
done

echo "== iOS AppIcon (15 fixed slots, filenames unchanged) =="
IOS_DIR="ios/Runner/Assets.xcassets/AppIcon.appiconset"
for pair in \
  "Icon-App-20x20@1x.png:20" "Icon-App-20x20@2x.png:40" "Icon-App-20x20@3x.png:60" \
  "Icon-App-29x29@1x.png:29" "Icon-App-29x29@2x.png:58" "Icon-App-29x29@3x.png:87" \
  "Icon-App-40x40@1x.png:40" "Icon-App-40x40@2x.png:80" "Icon-App-40x40@3x.png:120" \
  "Icon-App-60x60@2x.png:120" "Icon-App-60x60@3x.png:180" \
  "Icon-App-76x76@1x.png:76" "Icon-App-76x76@2x.png:152" \
  "Icon-App-83.5x83.5@2x.png:167" "Icon-App-1024x1024@1x.png:1024"; do
  name=${pair%%:*}; size=${pair##*:}
  sips -z "$size" "$size" "$MASTER" --out "$IOS_DIR/$name" >/dev/null
done
swift tool/flatten_ios_icons.swift "$IOS_DIR"/*.png

echo "== macOS AppIcon (7 fixed slots, filenames unchanged) =="
# 16·32px는 Windows·Linux와 같은 작은 마크: 방패는 이 크기에서 흰 덩어리로 뭉개짐
MACOS_DIR="macos/Runner/Assets.xcassets/AppIcon.appiconset"
for size in 16 32; do
  cp "build/icon_master/small_$size.png" "$MACOS_DIR/app_icon_$size.png"
done
for size in 64 128 256 512 1024; do
  sips -z "$size" "$size" "$MASTER_MACOS" --out "$MACOS_DIR/app_icon_$size.png" >/dev/null
done

echo "== Windows .ico source PNGs + pack =="
# 16~32px는 픽셀 격자에 맞춰 그린 단순 마크를 그대로 쓰고, 48px부터 스퀘어클 판 마스터를 줄임
mkdir -p build/icon_master/windows
for size in 16 24 32; do
  cp "build/icon_master/small_$size.png" "build/icon_master/windows/icon_$size.png"
done
for size in 48 64 128 256; do
  sips -z "$size" "$size" "$MASTER_WINDOWS" \
    --out "build/icon_master/windows/icon_$size.png" >/dev/null
done
dart run tool/pack_ico.dart

echo "== Linux icon =="
# GNOME 앱 아이콘 격자의 판 비율(약 81%)이 macOS 템플릿과 같아서 macOS 마스터를 씀
mkdir -p linux/icons/hicolor/512x512/apps
sips -z 512 512 "$MASTER_MACOS" --out "linux/icons/hicolor/512x512/apps/intragram.png" >/dev/null

echo "== iOS launch mark =="
# 라이트 외형은 흰 바탕에서 밝은 마크가 보이지 않아 남색 판이 포함된 macOS 마스터를 쓰고, 다크 외형은 투명 마크를 씀
LAUNCH_DIR="ios/Runner/Assets.xcassets/LaunchImage.imageset"
for pair in ":168" "@2x:336" "@3x:504"; do
  suffix=${pair%%:*}; size=${pair##*:}
  sips -z "$size" "$size" "$MASTER_MACOS" --out "$LAUNCH_DIR/LaunchImage$suffix.png" >/dev/null
  sips -z "$size" "$size" "$LAUNCH_MARK" --out "$LAUNCH_DIR/LaunchImageDark$suffix.png" >/dev/null
done

echo "Done."
