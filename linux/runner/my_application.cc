#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  gboolean first_frame_seen;
  guint startup_watchdog_id;
};

// Запас на самый медленный честный старт.
constexpr guint kStartupWatchdogSeconds = 20;

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Окно показывается только по первому кадру (см. first_frame_cb). Если кадра
// нет — например, старт упал до runApp, — остаётся живой процесс без окна и без
// трея: иконку трея заводит Dart, которого нет. Снять такое можно только через
// kill, а понять причину нельзя вовсе.
static gboolean startup_watchdog_cb(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->startup_watchdog_id = 0;
  if (self->first_frame_seen || !GTK_IS_WINDOW(self->window)) {
    return G_SOURCE_REMOVE;
  }

  gtk_widget_show(GTK_WIDGET(self->window));
  // Каталог тот же, что вычисляет path_provider: он спрашивает у GLib id
  // приложения, а это и есть APPLICATION_ID.
  g_autofree gchar* dir =
      g_build_filename(g_get_user_data_dir(), APPLICATION_ID, nullptr);
  g_autofree gchar* text = g_strdup_printf(
      "keqdroid запустился, но не смог показать интерфейс.\n\n"
      "Закройте это окно и пришлите файл app.log из каталога\n"
      "%s — по нему видно, что сломалось.",
      dir);
  // Формат отдельным аргументом: с текстом вместо формата сборка падает там,
  // где -Wformat-security включён ошибкой (а это почти все дистрибутивы).
  GtkWidget* dialog =
      gtk_message_dialog_new(self->window, GTK_DIALOG_MODAL, GTK_MESSAGE_ERROR,
                             GTK_BUTTONS_CLOSE, "%s", text);
  gtk_dialog_run(GTK_DIALOG(dialog));
  gtk_widget_destroy(dialog);
  return G_SOURCE_REMOVE;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  self->first_frame_seen = TRUE;
  if (self->startup_watchdog_id != 0) {
    g_source_remove(self->startup_watchdog_id);
    self->startup_watchdog_id = 0;
  }
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
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "keqdroid");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "keqdroid");
  }

  // Match the Windows runner: 920x720, centered on screen (the GTK default of
  // 1280x720 placed at the WM origin looked oversized and corner-anchored).
  gtk_window_set_default_size(window, 920, 720);
  gtk_window_set_position(window, GTK_WIN_POS_CENTER);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
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

  self->window = window;
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
