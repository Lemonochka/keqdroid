#include "portal_request.h"

namespace keqdroid_portal {

namespace {

// Registry сверяет id с именем ярлыка, ярлык у пакетов и AppImage keqdroid.desktop
constexpr char kAppId[] = "keqdroid";

GDBusConnection* g_bus = nullptr;
bool g_bus_tried = false;
guint g_token_counter = 0;

// путь Request по спецификации: подписаться на Response надо до вызова, иначе ответ может прийти раньше
std::string RequestPath(const std::string& token) {
  std::string sender = g_dbus_connection_get_unique_name(g_bus) + 1;
  for (auto& c : sender) {
    if (c == '.') c = '_';
  }
  return std::string(kPath) + "/request/" + sender + "/" + token;
}

struct Pending {
  guint subscription = 0;
  bool answered = false;
  bool call_done = false;
  Done done;
};

void Release(Pending* pending) {
  if (pending->answered && pending->call_done) delete pending;
}

void OnResponse(GDBusConnection* connection, const gchar*, const gchar*,
                const gchar*, const gchar*, GVariant* parameters,
                gpointer user_data) {
  auto* pending = static_cast<Pending*>(user_data);
  if (pending->answered) return;
  pending->answered = true;
  g_dbus_connection_signal_unsubscribe(connection, pending->subscription);
  guint response = 2;
  g_autoptr(GVariant) results = nullptr;
  g_variant_get(parameters, "(u@a{sv})", &response, &results);
  Done done = pending->done;
  Release(pending);
  done(response, results);
}

void OnCallFinished(GObject* source, GAsyncResult* result,
                    gpointer user_data) {
  auto* pending = static_cast<Pending*>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(source), result, &error);
  pending->call_done = true;
  if (reply == nullptr && !pending->answered) {
    g_warning("Portal call failed (%s)", error->message);
    pending->answered = true;
    g_dbus_connection_signal_unsubscribe(g_bus, pending->subscription);
    Done done = pending->done;
    Release(pending);
    done(2, nullptr);
    return;
  }
  Release(pending);
}

}  // namespace

GVariant* EmptyVardict() {
  return g_variant_new_array(G_VARIANT_TYPE("{sv}"), nullptr, 0);
}

GDBusConnection* Bus() {
  if (g_bus_tried) return g_bus;
  g_bus_tried = true;
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* address =
      g_dbus_address_get_for_bus_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (address == nullptr) return nullptr;
  g_bus = g_dbus_connection_new_for_address_sync(
      address,
      static_cast<GDBusConnectionFlags>(
          G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
          G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
      nullptr, nullptr, &error);
  if (g_bus == nullptr) {
    g_warning("Portal: no session bus (%s)", error->message);
    return nullptr;
  }
  // портал до 1.19 Registry не знает, тогда id берётся из cgroup запуска
  g_autoptr(GError) register_error = nullptr;
  g_autoptr(GVariant) registered = g_dbus_connection_call_sync(
      g_bus, kBus, kPath, "org.freedesktop.host.portal.Registry", "Register",
      g_variant_new("(s@a{sv})", kAppId, EmptyVardict()), nullptr,
      G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, &register_error);
  if (registered == nullptr) {
    g_message("Portal: registry unavailable (%s)", register_error->message);
  }
  return g_bus;
}

bool HasInterface(const char* interface_name) {
  GDBusConnection* bus = Bus();
  if (bus == nullptr) return false;
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) version = g_dbus_connection_call_sync(
      bus, kBus, kPath, "org.freedesktop.DBus.Properties", "Get",
      g_variant_new("(ss)", interface_name, "version"), G_VARIANT_TYPE("(v)"),
      G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, &error);
  if (version == nullptr) {
    g_message("Portal has no %s (%s)", interface_name, error->message);
    return false;
  }
  return true;
}

std::string NextToken() {
  return "keqdroid" + std::to_string(++g_token_counter);
}

void Call(const char* interface_name, const char* method, GVariant* parameters,
          const std::string& token, Done done) {
  GDBusConnection* bus = Bus();
  if (bus == nullptr) {
    g_variant_unref(g_variant_ref_sink(parameters));
    done(2, nullptr);
    return;
  }
  auto* pending = new Pending();
  pending->done = std::move(done);
  // как в libportal: Response приходит адресно, правило совпадения на шине не нужно
  pending->subscription = g_dbus_connection_signal_subscribe(
      bus, kBus, "org.freedesktop.portal.Request", "Response",
      RequestPath(token).c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE,
      OnResponse, pending, nullptr);
  g_dbus_connection_call(bus, kBus, kPath, interface_name, method, parameters,
                         G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, -1,
                         nullptr, OnCallFinished, pending);
}

}  // namespace keqdroid_portal
