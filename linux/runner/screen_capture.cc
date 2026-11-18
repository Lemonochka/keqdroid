#include "screen_capture.h"

#include <gtk/gtk.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <cstdint>
#include <vector>

#include "portal_request.h"

namespace {

constexpr char kChannel[] = "keqdroid/linux_screen";
constexpr char kScreenshotIface[] = "org.freedesktop.portal.Screenshot";

FlMethodChannel* g_channel = nullptr;

#ifdef GDK_WINDOWING_X11
bool X11Capturable() {
  // под Wayland корень XWayland чёрный, там видны только окна X11
  const gchar* type = g_getenv("XDG_SESSION_TYPE");
  const bool wayland =
      (type != nullptr && g_ascii_strcasecmp(type, "wayland") == 0) ||
      g_getenv("WAYLAND_DISPLAY") != nullptr;
  return GDK_IS_X11_DISPLAY(gdk_display_get_default()) && !wayland;
}
#else
bool X11Capturable() { return false; }
#endif

const char* Backend() {
  if (X11Capturable()) return "x11";
  if (keqdroid_portal::HasInterface(kScreenshotIface)) return "portal";
  return "none";
}

void RespondCaptureError(FlMethodCall* call, const char* message) {
  fl_method_call_respond_error(call, "CAPTURE_FAILED", message, nullptr,
                               nullptr);
}

void CaptureX11(FlMethodCall* call) {
  GdkWindow* root = gdk_get_default_root_window();
  const int width = gdk_window_get_width(root);
  const int height = gdk_window_get_height(root);
  g_autoptr(GdkPixbuf) pixbuf =
      gdk_pixbuf_get_from_window(root, 0, 0, width, height);
  if (pixbuf == nullptr) {
    RespondCaptureError(call, "Could not read the X11 root window");
    return;
  }
  const int channels = gdk_pixbuf_get_n_channels(pixbuf);
  const int stride = gdk_pixbuf_get_rowstride(pixbuf);
  const int w = gdk_pixbuf_get_width(pixbuf);
  const int h = gdk_pixbuf_get_height(pixbuf);
  const guchar* pixels = gdk_pixbuf_read_pixels(pixbuf);
  std::vector<uint8_t> gray(static_cast<size_t>(w) * static_cast<size_t>(h));
  // как RGBLuminanceSource у zxing и grayFromRgba в Dart: (r + 2g + b) / 4
  for (int y = 0; y < h; ++y) {
    const guchar* row = pixels + static_cast<size_t>(y) * stride;
    for (int x = 0; x < w; ++x) {
      const guchar* p = row + static_cast<size_t>(x) * channels;
      gray[static_cast<size_t>(y) * w + x] =
          static_cast<uint8_t>((p[0] + 2 * p[1] + p[2]) >> 2);
    }
  }
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "width", fl_value_new_int(w));
  fl_value_set_string_take(result, "height", fl_value_new_int(h));
  fl_value_set_string_take(result, "gray",
                           fl_value_new_uint8_list(gray.data(), gray.size()));
  fl_method_call_respond_success(call, result, nullptr);
}

// interactive false: GNOME один раз спрашивает разрешение, дальше снимает молча
void CapturePortal(FlMethodCall* call) {
  FlMethodCall* pending = FL_METHOD_CALL(g_object_ref(call));
  const std::string token = keqdroid_portal::NextToken();
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  g_variant_builder_add(&options, "{sv}", "interactive",
                        g_variant_new_boolean(FALSE));
  keqdroid_portal::Call(
      kScreenshotIface, "Screenshot", g_variant_new("(sa{sv})", "", &options),
      token, [pending](guint response, GVariant* results) {
        const gchar* uri = nullptr;
        g_autofree gchar* path = nullptr;
        if (response == 0 && results != nullptr &&
            g_variant_lookup(results, "uri", "&s", &uri)) {
          path = g_filename_from_uri(uri, nullptr, nullptr);
        }
        if (path == nullptr) {
          fl_method_call_respond_error(
              pending, response == 1 ? "CAPTURE_DENIED" : "CAPTURE_FAILED",
              "The screenshot portal returned no picture", nullptr, nullptr);
        } else {
          g_autoptr(FlValue) result = fl_value_new_map();
          fl_value_set_string_take(result, "path", fl_value_new_string(path));
          fl_method_call_respond_success(pending, result, nullptr);
        }
        g_object_unref(pending);
      });
}

void HandleMethodCall(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* name = fl_method_call_get_name(call);
  if (g_strcmp0(name, "getBackend") == 0) {
    g_autoptr(FlValue) result = fl_value_new_string(Backend());
    fl_method_call_respond_success(call, result, nullptr);
    return;
  }
  if (g_strcmp0(name, "capture") == 0) {
    if (X11Capturable()) {
      CaptureX11(call);
    } else if (keqdroid_portal::HasInterface(kScreenshotIface)) {
      CapturePortal(call);
    } else {
      RespondCaptureError(call, "No way to capture the screen here");
    }
    return;
  }
  fl_method_call_respond_not_implemented(call, nullptr);
}

}  // namespace

void keqdroid_screen_capture_register(FlBinaryMessenger* messenger) {
  if (g_channel != nullptr) return;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_channel =
      fl_method_channel_new(messenger, kChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_channel, HandleMethodCall,
                                            nullptr, nullptr);
}
