#include "windows_tray.h"

#include "tunnel_channel_handler.h"
#include "window_placement.h"

namespace {

bool g_minimize_to_tray = true;
HWND g_tray_hwnd = nullptr;

// спрятано в трей, а не свёрнуто: кнопки на панели нет, и любая активация приходит извне
bool g_window_hidden_in_tray = false;

int g_first_show_command = 0;

void HideWindowToTray(HWND hwnd) {
  g_window_hidden_in_tray = true;
  ::ShowWindow(hwnd, SW_HIDE);
  // жизненный цикл Flutter отдаёт SW_HIDE как inactive, и в трее шла бы отрисовка 60 кадров
  KeqdroidNotifyWindowVisibility(false);
}

}  // namespace

void WindowsTrayInit(HWND hwnd) {
  g_tray_hwnd = hwnd;
}

void WindowsTraySetMinimizeToTray(bool enabled) {
  g_minimize_to_tray = enabled;
}

bool WindowsTrayGetMinimizeToTray() {
  return g_minimize_to_tray;
}

HWND WindowsTrayGetMainHwnd() {
  return g_tray_hwnd;
}

bool WindowsTrayActivateMainWindow() {
  if (g_tray_hwnd == nullptr || !::IsWindow(g_tray_hwnd)) {
    return false;
  }
  KeqdroidNotifyWindowVisibility(true);
  g_window_hidden_in_tray = false;
  if (g_first_show_command != 0) {
    ::ShowWindow(g_tray_hwnd, g_first_show_command);
    g_first_show_command = 0;
  } else if (::IsIconic(g_tray_hwnd)) {
    ::ShowWindow(g_tray_hwnd, SW_RESTORE);
  } else {
    ::ShowWindow(g_tray_hwnd, SW_SHOW);
  }
  ::SetForegroundWindow(g_tray_hwnd);
  return true;
}

void WindowsTrayStartHidden(int first_show_command) {
  g_window_hidden_in_tray = true;
  g_first_show_command = first_show_command;
}

bool WindowsTrayIsHiddenInTray() {
  return g_window_hidden_in_tray;
}

bool WindowsTrayRestoreMainWindow() {
  return WindowsTrayActivateMainWindow();
}

bool WindowsTrayToggleMainWindow() {
  if (g_tray_hwnd == nullptr || !::IsWindow(g_tray_hwnd)) {
    return false;
  }
  if (::IsWindowVisible(g_tray_hwnd) && !::IsIconic(g_tray_hwnd)) {
    KeqdroidSaveWindowPlacement(g_tray_hwnd);
    HideWindowToTray(g_tray_hwnd);
    return true;
  }
  return WindowsTrayActivateMainWindow();
}

void WindowsTrayExitApplication(HWND hwnd) {
  KeqdroidSaveWindowPlacement(hwnd);
  if (hwnd != nullptr && ::IsWindow(hwnd)) {
    ::DestroyWindow(hwnd);
  }
  ::PostQuitMessage(0);
}

void WindowsTrayDispose(HWND hwnd) {
  (void)hwnd;
  g_tray_hwnd = nullptr;
}

bool WindowsTrayHandleMessage(HWND hwnd,
                              UINT message,
                              WPARAM wparam,
                              LPARAM lparam,
                              LRESULT* result) {
  (void)lparam;

  if (message == WM_ACTIVATE) {
    if (LOWORD(wparam) == WA_INACTIVE) {
      return false;
    }

    // перехватываем только спрятанное в трей: у свёрнутого на панели есть кнопка, и съеденный restore
    // на Windows 10 ломал второе нажатие по ней. спрятанное активирует только второй экземпляр (ActivateExistingInstance)
    if (g_window_hidden_in_tray || !::IsWindowVisible(hwnd)) {
      WindowsTrayActivateMainWindow();
      if (result != nullptr) {
        *result = 0;
      }
      return true;
    }
    return false;
  }

  if (message == WM_SYSCOMMAND) {
    const WPARAM command = wparam & 0xFFF0;
    if (command == SC_RESTORE || command == SC_MAXIMIZE) {
      // то же правило, что у WM_ACTIVATE
      if (g_window_hidden_in_tray || !::IsWindowVisible(hwnd)) {
        WindowsTrayActivateMainWindow();
        if (result != nullptr) {
          *result = 0;
        }
        return true;
      }
    }
    return false;
  }

  if (message == WM_CLOSE) {
    KeqdroidSaveWindowPlacement(hwnd);
    if (g_minimize_to_tray) {
      HideWindowToTray(hwnd);
    } else {
      ::DestroyWindow(hwnd);
    }
    if (result != nullptr) {
      *result = 0;
    }
    return true;
  }

  return false;
}
