#!/bin/sh
# IntraGram을 이 사용자 계정의 앱 메뉴에 등록함 (관리자 권한 필요 없음). 압축을 푼 폴더에서 실행
# 메뉴에서 빼려면: ./install.sh --uninstall   (폴더를 옮기면 다시 실행)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
data="${XDG_DATA_HOME:-$HOME/.local/share}"
app_id=com.yonghun0310.intragram
sizes="16 24 32 48 64 128 256 512"

if [ "${1:-}" = "--uninstall" ]; then
  rm -f "$data/applications/$app_id.desktop"
  for size in $sizes; do
    rm -f "$data/icons/hicolor/${size}x${size}/apps/intragram.png"
  done
  echo "IntraGram is no longer in the app menu."
  exit 0
fi

for size in $sizes; do
  src="$here/share/icons/hicolor/${size}x${size}/apps/intragram.png"
  [ -f "$src" ] || continue
  mkdir -p "$data/icons/hicolor/${size}x${size}/apps"
  cp "$src" "$data/icons/hicolor/${size}x${size}/apps/intragram.png"
done

# 메뉴 항목이 PATH가 아니라 이 폴더의 실행 파일을 직접 부르게 Exec를 절대 경로로 바꿈
# ponytail: 경로에 | 나 " 가 있으면 sed 치환이 깨짐, 그런 폴더는 옮겨서 실행
mkdir -p "$data/applications"
sed "s|^Exec=.*|Exec=\"$here/intragram\"|" \
  "$here/share/applications/$app_id.desktop" > "$data/applications/$app_id.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$data/applications" || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t "$data/icons/hicolor" || true
fi
echo "IntraGram is in your app menu. Run ./install.sh --uninstall to remove it."
