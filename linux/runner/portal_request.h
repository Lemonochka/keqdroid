#ifndef RUNNER_PORTAL_REQUEST_H_
#define RUNNER_PORTAL_REQUEST_H_

#include <gio/gio.h>

#include <functional>
#include <string>

namespace keqdroid_portal {

constexpr char kBus[] = "org.freedesktop.portal.Desktop";
constexpr char kPath[] = "/org/freedesktop/portal/desktop";

// своё соединение: Registry.Register обязан идти раньше любого вызова портала, а общее соединение GTK мог уже занять
GDBusConnection* Bus();

bool HasInterface(const char* interface_name);

std::string NextToken();

GVariant* EmptyVardict();

// response 0 успех, 1 отказ пользователя, 2 прочее; results может быть nullptr
using Done = std::function<void(guint response, GVariant* results)>;

// handle_token в options вызова обязан совпадать с token
void Call(const char* interface_name, const char* method, GVariant* parameters,
          const std::string& token, Done done);

}  // namespace keqdroid_portal

#endif  // RUNNER_PORTAL_REQUEST_H_
