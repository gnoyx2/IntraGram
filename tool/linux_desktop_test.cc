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
  // First background = first Flutter frame: the engine reads the portal
  // color-scheme when present, otherwise only a "-dark" theme suffix.
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
  // Without a portal light/dark choice the session's GTK preference stays.
  assert(intragram_overrides_dark(1));
  assert(intragram_overrides_dark(2));
  assert(!intragram_overrides_dark(0));
  assert(!intragram_overrides_dark(-1));
}
