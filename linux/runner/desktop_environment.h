#ifndef INTRAGRAM_DESKTOP_ENVIRONMENT_H_
#define INTRAGRAM_DESKTOP_ENVIRONMENT_H_

#include <glib.h>

// Explicit SSD/tiling names win in mixed desktop lists (e.g. GNOME:Hyprland).
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

// The first background must match the first Flutter frame. Like the engine
// (fl_settings_portal.cc, fl_gnome_settings.cc): a portal color-scheme decides
// alone (dark only for 1); without it only a "-dark" theme suffix is dark.
// HighContrastInverse has no such suffix and the engine paints it light too.
inline gboolean intragram_prefers_dark(gint portal_scheme,
                                       const gchar* gtk_theme) {
  if (portal_scheme >= 0) return portal_scheme == 1;
  return gtk_theme != nullptr && g_str_has_suffix(gtk_theme, "-dark");
}

// Only a portal dark (1) or light (2) choice overrides the GtkSettings value.
inline gboolean intragram_overrides_dark(gint portal_scheme) {
  return portal_scheme == 1 || portal_scheme == 2;
}

#endif  // INTRAGRAM_DESKTOP_ENVIRONMENT_H_
