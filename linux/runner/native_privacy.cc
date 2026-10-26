#include "native_privacy.h"
#include "desktop_environment.h"

#include <cstring>
#include <initializer_list>

struct PrivacyState {
  FlView* view;
  FlMethodChannel* channel;
  GCancellable* cancel;
  GDBusProxy* portal;
  GtkSettings* settings;
  GtkClipboard* clipboard;
  gchar* copied_text;
  guint64 settings_generation;
  // 포털 값이 없으면 -1(포털 부재·오류·키 누락), 기본 선호 없음 0, 다크 1, 라이트 2
  gint portal_scheme;
  gint portal_contrast;
  gint portal_motion;
  gboolean reduce_motion;
  gboolean high_contrast;
  gboolean setting_theme;
  // gtk-application-prefer-dark-theme에 애플리케이션 우선순위로 포털 값을 반영하며,
  // 재설정 시 세션 설정으로 되돌아감
  gboolean dark_override;
};

static void respond(FlMethodCall* call, FlValue* value) {
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(value));
  fl_method_call_respond(call, response, nullptr);
}

static void respond_bool(FlMethodCall* call, gboolean value) {
  g_autoptr(FlValue) result = fl_value_new_bool(value);
  respond(call, result);
}

static void push(PrivacyState* state, const gchar* name, gboolean enabled) {
  g_autoptr(FlValue) value = fl_value_new_bool(enabled);
  fl_method_channel_invoke_method(state->channel, name, value, nullptr, nullptr,
                                  nullptr);
}

// GTK3 위젯(헤더 바)은 포털의 color-scheme을 직접 읽지 않으므로, 포털에서 다크·라이트가
// 명시된 경우만 적용함. 그 외(포털 없음, 오류, 선호 없음, 알 수 없는 값)에는
// 앱 수준 설정을 초기화하여 XSettings/settings.ini 설정이 적용되도록 함
static void sync_dark_preference(PrivacyState* state) {
  const gboolean override = intragram_overrides_dark(state->portal_scheme);
  state->setting_theme = TRUE;
  if (override) {
    const gboolean dark = state->portal_scheme == 1;
    gboolean current = FALSE;
    g_object_get(state->settings, "gtk-application-prefer-dark-theme",
                 &current, nullptr);
    if (!state->dark_override || current != dark) {
      g_object_set(state->settings, "gtk-application-prefer-dark-theme", dark,
                   nullptr);
    }
  } else if (state->dark_override) {
    gtk_settings_reset_property(state->settings,
                                "gtk-application-prefer-dark-theme");
  }
  state->dark_override = override;
  state->setting_theme = FALSE;
}

static void sync_settings(PrivacyState* state) {
  gboolean animate = TRUE;
  g_autofree gchar* theme = nullptr;
  g_object_get(state->settings, "gtk-enable-animations", &animate,
               "gtk-theme-name", &theme, nullptr);
  const gboolean contrast = state->portal_contrast == 1 ||
      (theme != nullptr && g_strrstr(theme, "HighContrast") != nullptr);
  const gboolean motion = state->portal_motion == 1 || !animate;
  const gboolean dark = intragram_prefers_dark(state->portal_scheme, theme);
  sync_dark_preference(state);
  GdkRGBA background;
  gdk_rgba_parse(&background, dark ? "#0D0F14" : "#FFFFFF");
  fl_view_set_background_color(state->view, &background);
  if (contrast != state->high_contrast) {
    state->high_contrast = contrast;
    // 포털에는 투명도 줄이기 설정이 없으므로 고대비 설정으로 테두리를 결정함
    push(state, "onHighContrastChanged", contrast);
    push(state, "onReduceTransparencyChanged", contrast);
  }
  if (motion != state->reduce_motion) {
    state->reduce_motion = motion;
    push(state, "onReduceMotionChanged", motion);
  }
}

static void settings_changed(GtkSettings*, GParamSpec*, gpointer data) {
  auto* state = static_cast<PrivacyState*>(data);
  // 자체 쓰기로 발생한 변경 알림이 다시 루프로 들어오지 않도록 차단함
  if (!state->setting_theme) sync_settings(state);
}

static void apply_setting(PrivacyState* state, const gchar* key,
                          GVariant* value) {
  if (!g_variant_is_of_type(value, G_VARIANT_TYPE_UINT32)) return;
  const guint32 number = g_variant_get_uint32(value);
  if (g_str_equal(key, "color-scheme")) {
    state->portal_scheme = number <= 2u ? static_cast<gint>(number) : 0;
  } else if (g_str_equal(key, "contrast")) {
    state->portal_contrast = number == 1u ? 1 : 0;
  } else if (g_str_equal(key, "reduced-motion")) {
    state->portal_motion = number == 1u ? 1 : 0;
  }
}

static void portal_signal(GDBusProxy*, gchar*, gchar* signal,
                          GVariant* parameters, gpointer data) {
  if (!g_str_equal(signal, "SettingChanged") ||
      !g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ssv)"))) return;
  auto* state = static_cast<PrivacyState*>(data);
  const gchar* name;
  const gchar* key;
  g_autoptr(GVariant) value = nullptr;
  g_variant_get(parameters, "(&s&sv)", &name, &key, &value);
  if (!g_str_equal(name, "org.freedesktop.appearance")) return;
  ++state->settings_generation;
  apply_setting(state, key, value);
  sync_settings(state);
}

struct PortalRequest {
  FlView* view;
  guint64 generation;
};

static void read_settings_done(GObject* source, GAsyncResult* result,
                               gpointer data) {
  auto* request = static_cast<PortalRequest*>(data);
  auto* state = static_cast<PrivacyState*>(
      g_object_get_data(G_OBJECT(request->view), "intragram-privacy"));
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_proxy_call_finish(
      G_DBUS_PROXY(source), result, &error);
  if (state != nullptr && reply != nullptr &&
      state->settings_generation == request->generation &&
      g_variant_is_of_type(reply, G_VARIANT_TYPE("(a{sa{sv}})"))) {
    g_autoptr(GVariant) namespaces = g_variant_get_child_value(reply, 0);
    g_autoptr(GVariant) appearance = g_variant_lookup_value(
        namespaces, "org.freedesktop.appearance", G_VARIANT_TYPE("a{sv}"));
    if (appearance != nullptr) {
      GVariantIter iter;
      const gchar* key;
      GVariant* value;
      g_variant_iter_init(&iter, appearance);
      while (g_variant_iter_next(&iter, "{&sv}", &key, &value)) {
        apply_setting(state, key, value);
        g_variant_unref(value);
      }
      sync_settings(state);
    }
  }
  g_object_unref(request->view);
  delete request;
}

static void read_portal(PrivacyState* state) {
  const gchar* namespaces[] = {"org.freedesktop.appearance", nullptr};
  auto* request = new PortalRequest{FL_VIEW(g_object_ref(state->view)),
                                    state->settings_generation};
  g_dbus_proxy_call(state->portal, "ReadAll",
                    g_variant_new("(^as)", namespaces), G_DBUS_CALL_FLAGS_NONE,
                    1000, state->cancel, read_settings_done, request);
}

// 포털 프로세스가 종료되거나 재시작되면 기존 값이 무효화됨. 소유자가 없으면
// 세션 기본 설정을 적용하고, 새 소유자가 나타나면 값을 다시 읽음
static void portal_owner_changed(GObject*, GParamSpec*, gpointer data) {
  auto* state = static_cast<PrivacyState*>(data);
  ++state->settings_generation;
  state->portal_scheme = -1;
  state->portal_contrast = 0;
  state->portal_motion = 0;
  g_autofree gchar* owner = g_dbus_proxy_get_name_owner(state->portal);
  if (owner != nullptr) read_portal(state);
  sync_settings(state);
}

static void portal_ready(GObject*, GAsyncResult* result, gpointer data) {
  auto* view = FL_VIEW(data);
  auto* state = static_cast<PrivacyState*>(
      g_object_get_data(G_OBJECT(view), "intragram-privacy"));
  g_autoptr(GError) error = nullptr;
  GDBusProxy* proxy = g_dbus_proxy_new_for_bus_finish(result, &error);
  if (state != nullptr && proxy != nullptr) {
    state->portal = proxy;
    g_signal_connect(proxy, "g-signal", G_CALLBACK(portal_signal), state);
    g_signal_connect(proxy, "notify::g-name-owner",
                     G_CALLBACK(portal_owner_changed), state);
    read_portal(state);
  } else if (proxy != nullptr) {
    g_object_unref(proxy);
  }
  g_object_unref(view);
}

static void wipe_copy(PrivacyState* state) {
  if (state->copied_text == nullptr) return;
  volatile gchar* bytes = state->copied_text;
  const gsize length = strlen(state->copied_text);
  for (gsize i = 0; i < length; ++i) bytes[i] = 0;
  g_clear_pointer(&state->copied_text, g_free);
}

static void clipboard_get(GtkClipboard*, GtkSelectionData* selection,
                          guint info, gpointer owner) {
  auto* view = FL_VIEW(owner);
  auto* state = static_cast<PrivacyState*>(
      g_object_get_data(G_OBJECT(view), "intragram-privacy"));
  if (state == nullptr || state->copied_text == nullptr) return;
  if (info == 1) {
    const guchar hint[] = "secret";
    gtk_selection_data_set(selection, gtk_selection_data_get_target(selection),
                           8, hint, sizeof(hint) - 1);
  } else {
    gtk_selection_data_set_text(selection, state->copied_text, -1);
  }
}

static void clipboard_clear(GtkClipboard*, gpointer owner) {
  auto* state = static_cast<PrivacyState*>(
      g_object_get_data(G_OBJECT(owner), "intragram-privacy"));
  if (state != nullptr) wipe_copy(state);
}

static void clipboard_targets(GtkClipboard*, GdkAtom* atoms, gint count,
                              gpointer data) {
  auto* call = FL_METHOD_CALL(data);
  g_autoptr(FlValue) kinds = fl_value_new_map();
  gboolean image = FALSE;
  gboolean files = FALSE;
  if (atoms != nullptr) {
    for (gint i = 0; i < count; ++i) {
      g_autofree gchar* name = gdk_atom_name(atoms[i]);
      if (name == nullptr) continue;
      image |= g_str_has_prefix(name, "image/");
      files |= g_str_equal(name, "text/uri-list");
    }
  }
  fl_value_set_string_take(kinds, "image", fl_value_new_bool(image));
  fl_value_set_string_take(kinds, "files", fl_value_new_bool(files));
  respond(call, kinds);
  g_object_unref(call);
}

struct RevealRequest {
  FlMethodCall* call;
  gchar* uri;
};

static void reveal_done(GObject* source, GAsyncResult* result, gpointer data) {
  auto* request = static_cast<RevealRequest*>(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(source), result, &error);
  respond_bool(request->call, reply != nullptr);
  g_object_unref(request->call);
  g_free(request->uri);
  delete request;
}

static void reveal_bus_ready(GObject*, GAsyncResult* result, gpointer data) {
  auto* request = static_cast<RevealRequest*>(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus = g_bus_get_finish(result, &error);
  if (bus == nullptr) {
    respond_bool(request->call, FALSE);
    g_object_unref(request->call);
    g_free(request->uri);
    delete request;
    return;
  }
  const gchar* uris[] = {request->uri, nullptr};
  g_dbus_connection_call(bus, "org.freedesktop.FileManager1",
      "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1",
      "ShowItems", g_variant_new("(^ass)", uris, ""), nullptr,
      G_DBUS_CALL_FLAGS_NONE, 1500, nullptr, reveal_done, request);
}

static void method_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* state = static_cast<PrivacyState*>(data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (g_str_equal(method, "reduceTransparency") ||
      g_str_equal(method, "highContrast")) {
    respond_bool(call, state->high_contrast);
  } else if (g_str_equal(method, "reduceMotion")) {
    respond_bool(call, state->reduce_motion);
  } else if (g_str_equal(method, "copySensitive") &&
             fl_value_get_type(args) == FL_VALUE_TYPE_STRING) {
    // 텍스트를 교체하기 전에 소유권을 해제함. GTK가 이전 복사본의 clear를 호출함
    if (gtk_clipboard_get_owner(state->clipboard) == G_OBJECT(state->view)) {
      gtk_clipboard_clear(state->clipboard);
    }
    wipe_copy(state);
    state->copied_text = g_strdup(fl_value_get_string(args));
    GtkTargetEntry targets[] = {
        {const_cast<gchar*>("UTF8_STRING"), 0, 0},
        {const_cast<gchar*>("STRING"), 0, 0},
        {const_cast<gchar*>("TEXT"), 0, 0},
        {const_cast<gchar*>("text/plain;charset=utf-8"), 0, 0},
        {const_cast<gchar*>("x-kde-passwordManagerHint"), 0, 1}};
    const gboolean owned = gtk_clipboard_set_with_owner(
        state->clipboard, targets, G_N_ELEMENTS(targets), clipboard_get,
        clipboard_clear, G_OBJECT(state->view));
    if (!owned) wipe_copy(state);
    respond_bool(call, owned);
  } else if (g_str_equal(method, "clearIfOwn") ||
             g_str_equal(method, "clearClipboard")) {
    const gboolean owned =
        gtk_clipboard_get_owner(state->clipboard) == G_OBJECT(state->view);
    if (owned) gtk_clipboard_clear(state->clipboard);
    respond_bool(call, owned);
  } else if (g_str_equal(method, "clipboardKinds")) {
    gtk_clipboard_request_targets(state->clipboard, clipboard_targets,
                                   g_object_ref(call));
  } else if (g_str_equal(method, "revealFile") &&
             fl_value_get_type(args) == FL_VALUE_TYPE_STRING) {
    const gchar* path = fl_value_get_string(args);
    g_autofree gchar* uri = g_filename_to_uri(path, nullptr, nullptr);
    if (uri == nullptr || !g_path_is_absolute(path)) {
      respond_bool(call, FALSE);
      return;
    }
    auto* request = new RevealRequest{FL_METHOD_CALL(g_object_ref(call)),
                                      g_strdup(uri)};
    g_bus_get(G_BUS_TYPE_SESSION, nullptr, reveal_bus_ready, request);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

static void privacy_free(gpointer data) {
  auto* state = static_cast<PrivacyState*>(data);
  g_cancellable_cancel(state->cancel);
  g_signal_handlers_disconnect_by_data(state->settings, state);
  if (state->portal != nullptr) {
    g_signal_handlers_disconnect_by_data(state->portal, state);
  }
  if (gtk_clipboard_get_owner(state->clipboard) == G_OBJECT(state->view)) {
    gtk_clipboard_clear(state->clipboard);
  }
  fl_method_channel_set_method_call_handler(state->channel, nullptr, nullptr,
                                            nullptr);
  wipe_copy(state);
  g_clear_object(&state->portal);
  g_clear_object(&state->channel);
  g_clear_object(&state->cancel);
  delete state;
}

void intragram_privacy_attach(FlView* view) {
  auto* state = new PrivacyState{};
  state->view = view;
  state->portal_scheme = -1;
  state->cancel = g_cancellable_new();
  state->settings = gtk_widget_get_settings(GTK_WIDGET(view));
  state->clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  state->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "intragram/privacy", FL_METHOD_CODEC(codec));
  g_object_set_data_full(G_OBJECT(view), "intragram-privacy", state, privacy_free);
  fl_method_channel_set_method_call_handler(state->channel, method_call, state,
                                            nullptr);
  for (const gchar* name : {"notify::gtk-enable-animations",
                            "notify::gtk-theme-name",
                            "notify::gtk-application-prefer-dark-theme"}) {
    g_signal_connect(state->settings, name, G_CALLBACK(settings_changed), state);
  }
  g_signal_connect(view, "destroy", G_CALLBACK(+[](GtkWidget* widget, gpointer) {
    g_object_set_data(G_OBJECT(widget), "intragram-privacy", nullptr);
  }), nullptr);
  sync_settings(state);
  g_dbus_proxy_new_for_bus(G_BUS_TYPE_SESSION,
      static_cast<GDBusProxyFlags>(G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START |
                                  G_DBUS_PROXY_FLAGS_DO_NOT_LOAD_PROPERTIES),
      nullptr, "org.freedesktop.portal.Desktop",
      "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Settings",
      state->cancel, portal_ready, g_object_ref(view));
}
