#ifndef INTRAGRAM_DESKTOP_ENVIRONMENT_H_
#define INTRAGRAM_DESKTOP_ENVIRONMENT_H_

#include <glib.h>

// 혼합 데스크톱 목록(예: GNOME:Hyprland)에서는 명시적인 SSD/타일링 환경명이 우선함
inline gboolean intragram_uses_header_bar(const gchar* desktop,
                                         gboolean wayland,
                                         const gchar* x11_wm) {
  g_auto(GStrv) names = g_strsplit(desktop == nullptr ? "" : desktop, ":", -1);
  gboolean csd = FALSE;
  for (gchar** entry = names; *entry != nullptr; ++entry) {
    g_autofree gchar* name = g_ascii_strdown(*entry, -1);
    if (g_str_equal(name, "kde") || g_str_equal(name, "plasma") ||
        g_str_equal(name, "sway") || g_str_equal(name, "hyprland") ||
        g_str_equal(name, "cosmic") || g_str_equal(name, "i3")) {
      return FALSE;
    }
    csd |= g_str_equal(name, "gnome") || g_str_equal(name, "ubuntu") ||
           g_str_equal(name, "pantheon") || g_str_equal(name, "budgie");
  }
  return csd || (!wayland && g_strcmp0(x11_wm, "GNOME Shell") == 0);
}

// 첫 배경색은 Flutter의 첫 프레임과 일치해야 함. 엔진 구현(fl_settings_portal.cc,
// fl_gnome_settings.cc)과 동일하게 포털 color-scheme이 있으면 그 값만 따르고(1만 다크),
// 포털 값이 없을 때만 테마명의 '-dark' 접미사 유무로 다크 여부를 판정함.
// HighContrastInverse는 해당 접미사가 없어 엔진에서도 라이트로 렌더링됨
inline gboolean intragram_prefers_dark(gint portal_scheme,
                                       const gchar* gtk_theme) {
  if (portal_scheme >= 0) return portal_scheme == 1;
  return gtk_theme != nullptr && g_str_has_suffix(gtk_theme, "-dark");
}

// 포털 값이 다크(1) 또는 라이트(2)일 때만 GtkSettings 값을 덮어씀
inline gboolean intragram_overrides_dark(gint portal_scheme) {
  return portal_scheme == 1 || portal_scheme == 2;
}

#endif  // INTRAGRAM_DESKTOP_ENVIRONMENT_H_
