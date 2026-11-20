#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "global_hotkeys.h"
#include "screen_capture.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  gboolean first_frame_seen;
  gboolean start_in_tray;
  guint startup_watchdog_id;
};

// с запасом на самый медленный честный старт
constexpr guint kStartupWatchdogSeconds = 20;

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// окно показывается по первому кадру; без кадра (старт упал до runApp) остаётся процесс без окна и трея, снять только kill
static gboolean startup_watchdog_cb(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->startup_watchdog_id = 0;
  if (self->first_frame_seen || !GTK_IS_WINDOW(self->window)) {
    return G_SOURCE_REMOVE;
  }

  gtk_widget_show(GTK_WIDGET(self->window));
  // тот же каталог, что у path_provider: он берёт id приложения у GLib
  g_autofree gchar* dir =
      g_build_filename(g_get_user_data_dir(), APPLICATION_ID, nullptr);
  g_autofree gchar* text = g_strdup_printf(
      "keqdroid запустился, но не смог показать интерфейс.\n\n"
      "Закройте это окно и пришлите файл app.log из каталога\n"
      "%s — по нему видно, что сломалось.",
      dir);
  // формат отдельным аргументом: с -Wformat-security, а он почти везде, иначе сборка падает
  GtkWidget* dialog =
      gtk_message_dialog_new(self->window, GTK_DIALOG_MODAL, GTK_MESSAGE_ERROR,
                             GTK_BUTTONS_CLOSE, "%s", text);
  gtk_dialog_run(GTK_DIALOG(dialog));
  gtk_widget_destroy(dialog);
  return G_SOURCE_REMOVE;
}

// иконка для X11: без неё WM рисует безликий значок. Wayland её не читает, там иконка от ярлыка (tool/package_linux.sh)
static void set_window_icon(GtkWindow* window) {
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe == nullptr) return;
  g_autofree gchar* dir = g_path_get_dirname(exe);
  g_autofree gchar* path = g_build_filename(
      dir, "data", "flutter_assets", "assets", "icon.png", nullptr);
  g_autoptr(GdkPixbuf) icon =
      gdk_pixbuf_new_from_file_at_size(path, 256, 256, nullptr);
  if (icon != nullptr) gtk_window_set_icon(window, icon);
}

// тайлинговые композиторы рисуют окна без заголовков, шапка GTK там лишняя; тот же список в LinuxBackgroundService.isTilingDesktop
static gboolean is_tiling_desktop() {
  const gchar* desktop = g_getenv("XDG_CURRENT_DESKTOP");
  if (desktop == nullptr) return FALSE;
  static const gchar* const kTiling[] = {"Hyprland", "sway", "niri", "river"};
  g_auto(GStrv) names = g_strsplit(desktop, ":", -1);
  for (gchar** name = names; *name != nullptr; name++) {
    for (const gchar* tiling : kTiling) {
      if (g_ascii_strcasecmp(*name, tiling) == 0) return TRUE;
    }
  }
  return FALSE;
}

// Без OpenGL окно чёрное, на программную отрисовку движок сам не переходит (setup_opengl в fl_view.cc).
// Так бывает с неполным драйвером NVIDIA, по RDP, в виртуалках. Заданная руками переменная важнее
static void use_software_rendering_without_gl(GtkWindow* window) {
  if (g_getenv("FLUTTER_LINUX_RENDERER") != nullptr) return;
  gtk_widget_realize(GTK_WIDGET(window));
  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkGLContext) context = gdk_window_create_gl_context(
      gtk_widget_get_window(GTK_WIDGET(window)), &error);
  if (context != nullptr && gdk_gl_context_realize(context, &error)) return;
  g_warning("OpenGL is unavailable (%s), using the software renderer",
            error != nullptr ? error->message : "unknown error");
  g_setenv("FLUTTER_LINUX_RENDERER", "software", TRUE);
}

// файл кладёт LinuxAutostart.setStartInTray: окно решается до первого кадра, а настройки Dart к нему ещё не прочитаны
static gboolean starts_in_tray(char** args) {
  if (args == nullptr || !g_strv_contains(args, "--autostart")) return FALSE;
  g_autofree gchar* path = g_build_filename(
      g_get_user_data_dir(), APPLICATION_ID, "autostart-in-tray", nullptr);
  return g_file_test(path, G_FILE_TEST_EXISTS);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  self->first_frame_seen = TRUE;
  if (self->startup_watchdog_id != 0) {
    g_source_remove(self->startup_watchdog_id);
    self->startup_watchdog_id = 0;
  }
  if (self->start_in_tray) return;
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (is_tiling_desktop()) {
    use_header_bar = FALSE;
    gtk_window_set_decorated(window, FALSE);
  }
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "keqdroid");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "keqdroid");
  }

  // как на Windows: 920x720 по центру, умолчание GTK 1280x720 в углу выглядело огромным
  gtk_window_set_default_size(window, 920, 720);
  gtk_window_set_position(window, GTK_WIN_POS_CENTER);
  set_window_icon(window);

  use_software_rendering_without_gl(window);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  // с октября 2025 Dart по умолчанию в потоке GTK и ждёт, пока тот выводит кадр: на стенде 3840x2400
  // 30 к/с с рывками до 58 мс вместо ровных 60; отдельный поток был умолчанием до flutter#176759
  fl_dart_project_set_ui_thread_policy(project,
                                       FL_UI_THREAD_POLICY_RUN_ON_SEPARATE_THREAD);
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  keqdroid_global_hotkeys_register(messenger);
  keqdroid_screen_capture_register(messenger);

  self->window = window;
  self->start_in_tray = starts_in_tray(self->dart_entrypoint_arguments);
  self->startup_watchdog_id =
      g_timeout_add_seconds(kStartupWatchdogSeconds, startup_watchdog_cb, self);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  if (self->startup_watchdog_id != 0) {
    g_source_remove(self->startup_watchdog_id);
    self->startup_watchdog_id = 0;
  }
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
