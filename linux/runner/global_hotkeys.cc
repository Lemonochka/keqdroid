#include "global_hotkeys.h"

#include <gio/gio.h>
#include <gtk/gtk.h>

#include "portal_request.h"
#ifdef GDK_WINDOWING_X11
#include <X11/XKBlib.h>
#include <X11/Xlib.h>
#include <gdk/gdkx.h>
#endif

#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace {

constexpr char kChannel[] = "keqdroid/linux_hotkeys";

constexpr char kShortcutsIface[] = "org.freedesktop.portal.GlobalShortcuts";

// MOD_* как у RegisterHotKey: Dart шлёт одни и те же биты обеим платформам
constexpr unsigned kModAlt = 1;
constexpr unsigned kModControl = 2;
constexpr unsigned kModShift = 4;
constexpr unsigned kModWin = 8;

struct Spec {
  std::string action;
  int evdev_code = 0;
  unsigned modifiers = 0;
  std::string portal_id;
  std::string trigger;
  std::string description;
};

enum class Backend { kUnknown, kNone, kX11, kPortal };

FlMethodChannel* g_channel = nullptr;
Backend g_backend = Backend::kUnknown;

void NotifyPressed(const std::string& action) {
  if (g_channel == nullptr || action.empty()) return;
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "action", fl_value_new_string(action.c_str()));
  fl_method_channel_invoke_method(g_channel, "onHotkeyPressed", args, nullptr,
                                  nullptr, nullptr);
}

FlValue* StringList(const std::vector<std::string>& items) {
  FlValue* list = fl_value_new_list();
  for (const auto& item : items) {
    fl_value_append_take(list, fl_value_new_string(item.c_str()));
  }
  return list;
}

void RespondList(FlMethodCall* call, const std::vector<std::string>& items) {
  g_autoptr(FlValue) list = StringList(items);
  fl_method_call_respond_success(call, list, nullptr);
}

std::vector<std::string> AllActions(const std::vector<Spec>& specs) {
  std::vector<std::string> out;
  for (const auto& spec : specs) out.push_back(spec.action);
  return out;
}

#ifdef GDK_WINDOWING_X11

// под Wayland с GDK_BACKEND=x11 корень XWayland видит клавиши, только пока в фокусе окно X11
bool WaylandSession() {
  const gchar* type = g_getenv("XDG_SESSION_TYPE");
  if (type != nullptr && g_ascii_strcasecmp(type, "wayland") == 0) return true;
  return g_getenv("WAYLAND_DISPLAY") != nullptr;
}

struct Grab {
  std::string action;
  int keycode;
  unsigned mods;
  bool down;
};

std::vector<Grab> g_grabs;
bool g_filter_installed = false;

// NumLock и CapsLock попадают в state, без вариаций с ними сочетание при включённом NumLock не ловится
constexpr unsigned kLockVariants[] = {0, LockMask, Mod2Mask, LockMask | Mod2Mask};
constexpr unsigned kRelevantMods = ShiftMask | ControlMask | Mod1Mask | Mod4Mask;

unsigned X11Mods(unsigned mods) {
  return ((mods & kModAlt) ? Mod1Mask : 0) |
         ((mods & kModControl) ? ControlMask : 0) |
         ((mods & kModShift) ? ShiftMask : 0) |
         ((mods & kModWin) ? Mod4Mask : 0);
}

GdkFilterReturn X11Filter(GdkXEvent* gdk_xevent, GdkEvent*, gpointer) {
  XEvent* event = static_cast<XEvent*>(gdk_xevent);
  if (event->type != KeyPress && event->type != KeyRelease) {
    return GDK_FILTER_CONTINUE;
  }
  const int keycode = static_cast<int>(event->xkey.keycode);
  bool ours = false;
  for (auto& grab : g_grabs) {
    if (grab.keycode != keycode) continue;
    if (event->type == KeyRelease) {
      // модификатор могли отпустить раньше клавиши, поэтому отпускание без сверки state
      if (grab.down) ours = true;
      grab.down = false;
      continue;
    }
    if (grab.mods != (event->xkey.state & kRelevantMods)) continue;
    ours = true;
    // повтор при удержании: без этого переключатели мигали бы вкл-выкл, как на Windows без MOD_NOREPEAT
    if (grab.down) continue;
    grab.down = true;
    NotifyPressed(grab.action);
  }
  return ours ? GDK_FILTER_REMOVE : GDK_FILTER_CONTINUE;
}

void X11UngrabAll() {
  GdkDisplay* display = gdk_display_get_default();
  if (!GDK_IS_X11_DISPLAY(display)) return;
  Display* xdisplay = GDK_DISPLAY_XDISPLAY(display);
  const Window root = DefaultRootWindow(xdisplay);
  gdk_x11_display_error_trap_push(display);
  for (const auto& grab : g_grabs) {
    for (unsigned lock : kLockVariants) {
      XUngrabKey(xdisplay, grab.keycode, grab.mods | lock, root);
    }
  }
  XSync(xdisplay, False);
  gdk_x11_display_error_trap_pop_ignored(display);
  g_grabs.clear();
}

std::vector<std::string> X11Apply(const std::vector<Spec>& specs) {
  X11UngrabAll();
  GdkDisplay* display = gdk_display_get_default();
  Display* xdisplay = GDK_DISPLAY_XDISPLAY(display);
  const Window root = DefaultRootWindow(xdisplay);

  if (!g_filter_installed) {
    // отпускание приходит только при включённом detectable autorepeat, иначе повтор неотличим от нового нажатия
    XkbSetDetectableAutoRepeat(xdisplay, True, nullptr);
    gdk_window_add_filter(gdk_get_default_root_window(), X11Filter, nullptr);
    g_filter_installed = true;
  }

  std::vector<std::string> failed;
  for (const auto& spec : specs) {
    if (spec.evdev_code <= 0) {
      failed.push_back(spec.action);
      continue;
    }
    // код клавиши X11 = код evdev + 8 у драйверов evdev и libinput
    const int keycode = spec.evdev_code + 8;
    const unsigned mods = X11Mods(spec.modifiers);
    gdk_x11_display_error_trap_push(display);
    for (unsigned lock : kLockVariants) {
      XGrabKey(xdisplay, keycode, mods | lock, root, False, GrabModeAsync,
               GrabModeAsync);
    }
    XSync(xdisplay, False);
    if (gdk_x11_display_error_trap_pop(display) != 0) {
      // BadAccess: сочетание держит другой клиент; свои вариации снимаем, иначе сработало бы только при NumLock
      gdk_x11_display_error_trap_push(display);
      for (unsigned lock : kLockVariants) {
        XUngrabKey(xdisplay, keycode, mods | lock, root);
      }
      XSync(xdisplay, False);
      gdk_x11_display_error_trap_pop_ignored(display);
      failed.push_back(spec.action);
      continue;
    }
    g_grabs.push_back({spec.action, keycode, mods, false});
  }
  return failed;
}

bool X11Available() {
  return GDK_IS_X11_DISPLAY(gdk_display_get_default()) && !WaylandSession();
}

#else

std::vector<std::string> X11Apply(const std::vector<Spec>& specs) {
  return AllActions(specs);
}

bool X11Available() { return false; }

#endif  // GDK_WINDOWING_X11

std::string g_session;
std::map<std::string, std::string> g_portal_actions;
guint g_activated_subscription = 0;

bool g_portal_busy = false;
FlMethodCall* g_portal_call = nullptr;
std::vector<Spec> g_portal_specs;
bool g_queued = false;
FlMethodCall* g_queued_call = nullptr;
std::vector<Spec> g_queued_specs;

void OnActivated(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                 const gchar*, GVariant* parameters, gpointer) {
  const gchar* session = nullptr;
  const gchar* shortcut_id = nullptr;
  g_variant_get(parameters, "(&o&sta{sv})", &session, &shortcut_id, nullptr,
                nullptr);
  if (session == nullptr || g_session != session) return;
  auto it = g_portal_actions.find(shortcut_id);
  if (it != g_portal_actions.end()) NotifyPressed(it->second);
}

void PortalStartNext();

void PortalFinish(const std::vector<std::string>& failed) {
  if (g_portal_call != nullptr) {
    RespondList(g_portal_call, failed);
    g_object_unref(g_portal_call);
    g_portal_call = nullptr;
  }
  g_portal_busy = false;
  PortalStartNext();
}

void OnBound(guint response, GVariant* results) {
  std::vector<std::string> failed;
  std::map<std::string, bool> bound;
  if (response == 0 && results != nullptr) {
    g_autoptr(GVariant) shortcuts =
        g_variant_lookup_value(results, "shortcuts", G_VARIANT_TYPE("a(sa{sv})"));
    if (shortcuts != nullptr) {
      GVariantIter iter;
      g_variant_iter_init(&iter, shortcuts);
      const gchar* id = nullptr;
      GVariant* props = nullptr;
      while (g_variant_iter_next(&iter, "(&s@a{sv})", &id, &props)) {
        const gchar* trigger = nullptr;
        if (g_variant_lookup(props, "trigger_description", "&s", &trigger)) {
          g_message("Global shortcuts: %s bound to %s", id, trigger);
        }
        bound[id] = true;
        g_variant_unref(props);
      }
    }
  } else {
    g_message("Global shortcuts: portal declined the shortcuts (response %u)",
              response);
  }
  for (const auto& spec : g_portal_specs) {
    if (!bound.count(spec.portal_id)) failed.push_back(spec.action);
  }
  PortalFinish(failed);
}

void BindCurrent() {
  GVariantBuilder shortcuts;
  g_variant_builder_init(&shortcuts, G_VARIANT_TYPE("a(sa{sv})"));
  for (const auto& spec : g_portal_specs) {
    GVariantBuilder props;
    g_variant_builder_init(&props, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add(&props, "{sv}", "description",
                          g_variant_new_string(spec.description.c_str()));
    if (!spec.trigger.empty()) {
      g_variant_builder_add(&props, "{sv}", "preferred_trigger",
                            g_variant_new_string(spec.trigger.c_str()));
    }
    g_variant_builder_add(&shortcuts, "(sa{sv})", spec.portal_id.c_str(),
                          &props);
  }
  const std::string token = keqdroid_portal::NextToken();
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  keqdroid_portal::Call(kShortcutsIface, "BindShortcuts",
                  g_variant_new("(oa(sa{sv})sa{sv})", g_session.c_str(),
                                &shortcuts, "", &options),
                  token, OnBound);
}

void OnSessionCreated(guint response, GVariant* results) {
  const gchar* session = nullptr;
  if (response != 0 || results == nullptr ||
      !g_variant_lookup(results, "session_handle", "&s", &session)) {
    g_warning("Global shortcuts: could not create a portal session");
    PortalFinish(AllActions(g_portal_specs));
    return;
  }
  g_session = session;
  BindCurrent();
}

void CloseSession() {
  if (g_session.empty()) return;
  g_dbus_connection_call(keqdroid_portal::Bus(), keqdroid_portal::kBus, g_session.c_str(),
                         "org.freedesktop.portal.Session", "Close", nullptr,
                         nullptr, G_DBUS_CALL_FLAGS_NONE, -1, nullptr, nullptr,
                         nullptr);
  g_session.clear();
}

// привязать сочетания сессии можно один раз, поэтому новый набор = новая сессия
void PortalRun() {
  g_portal_busy = true;
  CloseSession();
  g_portal_actions.clear();
  for (const auto& spec : g_portal_specs) {
    g_portal_actions[spec.portal_id] = spec.action;
  }
  if (g_portal_specs.empty()) {
    PortalFinish({});
    return;
  }
  if (g_activated_subscription == 0) {
    g_activated_subscription = g_dbus_connection_signal_subscribe(
        keqdroid_portal::Bus(), keqdroid_portal::kBus, kShortcutsIface, "Activated", keqdroid_portal::kPath, nullptr,
        G_DBUS_SIGNAL_FLAGS_NONE, OnActivated, nullptr, nullptr);
  }
  const std::string token = keqdroid_portal::NextToken();
  const std::string session_token = keqdroid_portal::NextToken();
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  g_variant_builder_add(&options, "{sv}", "session_handle_token",
                        g_variant_new_string(session_token.c_str()));
  keqdroid_portal::Call(kShortcutsIface, "CreateSession", g_variant_new("(a{sv})", &options), token,
                  OnSessionCreated);
}

void PortalStartNext() {
  if (g_portal_busy || !g_queued) return;
  g_queued = false;
  g_portal_call = g_queued_call;
  g_queued_call = nullptr;
  g_portal_specs = std::move(g_queued_specs);
  g_queued_specs.clear();
  PortalRun();
}

// окно портала ждёт пользователя, а настройки могут смениться ещё раз, поэтому держим только последний набор
void PortalApply(FlMethodCall* call, std::vector<Spec> specs) {
  if (g_queued_call != nullptr) {
    RespondList(g_queued_call, {});
    g_object_unref(g_queued_call);
  }
  g_queued = true;
  g_queued_call = FL_METHOD_CALL(g_object_ref(call));
  g_queued_specs = std::move(specs);
  PortalStartNext();
}

Backend DetectBackend() {
  if (g_backend != Backend::kUnknown) return g_backend;
  if (X11Available()) {
    g_backend = Backend::kX11;
  } else if (keqdroid_portal::HasInterface(kShortcutsIface)) {
    g_backend = Backend::kPortal;
  } else {
    g_backend = Backend::kNone;
  }
  return g_backend;
}

const char* BackendName(Backend backend) {
  switch (backend) {
    case Backend::kX11:
      return "x11";
    case Backend::kPortal:
      return "portal";
    default:
      return "none";
  }
}

std::string StringField(FlValue* map, const char* key) {
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return std::string();
  }
  return fl_value_get_string(value);
}

int64_t IntField(FlValue* map, const char* key) {
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return 0;
  }
  return fl_value_get_int(value);
}

std::vector<Spec> ParseSpecs(FlValue* args) {
  std::vector<Spec> specs;
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_LIST) {
    return specs;
  }
  for (size_t i = 0; i < fl_value_get_length(args); ++i) {
    FlValue* item = fl_value_get_list_value(args, i);
    if (fl_value_get_type(item) != FL_VALUE_TYPE_MAP) continue;
    Spec spec;
    spec.action = StringField(item, "action");
    if (spec.action.empty()) continue;
    spec.evdev_code = static_cast<int>(IntField(item, "evdevCode"));
    spec.modifiers = static_cast<unsigned>(IntField(item, "modifiers"));
    spec.portal_id = StringField(item, "portalId");
    spec.trigger = StringField(item, "trigger");
    spec.description = StringField(item, "description");
    if (spec.portal_id.empty()) spec.portal_id = spec.action;
    if (spec.description.empty()) spec.description = spec.action;
    specs.push_back(std::move(spec));
  }
  return specs;
}

void HandleMethodCall(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* name = fl_method_call_get_name(call);
  if (g_strcmp0(name, "getBackend") == 0) {
    g_autoptr(FlValue) result = fl_value_new_string(BackendName(DetectBackend()));
    fl_method_call_respond_success(call, result, nullptr);
    return;
  }
  if (g_strcmp0(name, "setGlobalHotkeys") == 0) {
    std::vector<Spec> specs = ParseSpecs(fl_method_call_get_args(call));
    switch (DetectBackend()) {
      case Backend::kX11:
        RespondList(call, X11Apply(specs));
        return;
      case Backend::kPortal:
        PortalApply(call, std::move(specs));
        return;
      default:
        RespondList(call, AllActions(specs));
        return;
    }
  }
  fl_method_call_respond_not_implemented(call, nullptr);
}

}  // namespace

void keqdroid_global_hotkeys_register(FlBinaryMessenger* messenger) {
  if (g_channel != nullptr) return;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_channel =
      fl_method_channel_new(messenger, kChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_channel, HandleMethodCall,
                                            nullptr, nullptr);
}
