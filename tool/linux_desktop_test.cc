#include "../linux/runner/desktop_environment.h"
#include <cassert>
#include <initializer_list>

int main() {
  assert(intragram_uses_header_bar("GNOME", TRUE, nullptr));
  assert(intragram_uses_header_bar("ubuntu:GNOME", TRUE, nullptr));
  assert(intragram_uses_header_bar("Pantheon", FALSE, nullptr));
  assert(intragram_uses_header_bar("Budgie", TRUE, nullptr));
  assert(intragram_uses_header_bar(nullptr, FALSE, "GNOME Shell"));
  for (const gchar* name : {"KDE", "plasma", "Sway", "Hyprland", "COSMIC", "i3",
                            "GNOME:Hyprland", "KDE:GNOME"}) {
    assert(!intragram_uses_header_bar(name, TRUE, "GNOME Shell"));
    assert(!intragram_uses_header_bar(name, FALSE, "GNOME Shell"));
  }
  assert(!intragram_uses_header_bar(nullptr, TRUE, nullptr));
  // 첫 배경색 = 첫 Flutter 프레임: 엔진은 포털 color-scheme이 있으면 이를 우선 읽고,
  // 없을 때만 테마명의 '-dark' 접미사로 판정함
  for (const gchar* theme : {"Adwaita", "Adwaita-dark", "HighContrast",
                             "HighContrastInverse"}) {
    assert(intragram_prefers_dark(1, theme));
    assert(!intragram_prefers_dark(0, theme));
    assert(!intragram_prefers_dark(2, theme));
  }
  assert(intragram_prefers_dark(-1, "Adwaita-dark"));
  assert(intragram_prefers_dark(-1, "Yaru-dark"));
  for (const gchar* theme : {"Adwaita", "HighContrast", "HighContrastInverse",
                             "Breeze-Dark", "Darkling", "Adwaita-darker"}) {
    assert(!intragram_prefers_dark(-1, theme));
  }
  assert(!intragram_prefers_dark(-1, nullptr));
  // 포털의 라이트/다크 선택이 없으면 세션의 기본 GTK 설정을 유지함
  assert(intragram_overrides_dark(1));
  assert(intragram_overrides_dark(2));
  assert(!intragram_overrides_dark(0));
  assert(!intragram_overrides_dark(-1));
}
