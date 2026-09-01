#include "windows_tray.h"

#include "tunnel_channel_handler.h"
#include "window_placement.h"

namespace {

bool g_minimize_to_tray = true;
HWND g_tray_hwnd = nullptr;

// Окно спрятано в трей (SW_HIDE), а не свёрнуто в панель задач. Разница важна:
// у спрятанного нет кнопки на панели, и любая его активация приходит извне.
bool g_window_hidden_in_tray = false;

void HideWindowToTray(HWND hwnd) {
  g_window_hidden_in_tray = true;
  ::ShowWindow(hwnd, SW_HIDE);
  // Tell Dart the window is off screen so it stops the wave animation and the
  // traffic-stats polling — the Flutter lifecycle reports SW_HIDE only as
  // `inactive`, so it would otherwise keep rendering at 60fps in the tray.
  KeqdisNotifyWindowVisibility(false);
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
  // Window is coming back on screen — resume the animation / stats polling.
  KeqdisNotifyWindowVisibility(true);
  g_window_hidden_in_tray = false;
  if (::IsIconic(g_tray_hwnd)) {
    ::ShowWindow(g_tray_hwnd, SW_RESTORE);
  } else {
    ::ShowWindow(g_tray_hwnd, SW_SHOW);
  }
  ::SetForegroundWindow(g_tray_hwnd);
  return true;
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
  // Last chance to persist the bounds (covers un-maximize via titlebar button
  // followed by tray exit).
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

    // Only take over activation when the window is fully hidden in the tray —
    // in that state there is no taskbar button, so this can't be a taskbar
    // click. A normally minimized window (iconic but still shown in the taskbar)
    // must keep the OS-native taskbar toggle: swallowing its restore here left
    // Windows 10 unable to minimize on the second taskbar click (Win11 tolerated
    // it). IsWindowVisible() is FALSE only for SW_HIDE'd (tray) windows; iconic
    // windows keep WS_VISIBLE, so they now fall through to the default handler.
    //
    // Кто активирует спрятанное окно: второй экземпляр приложения
    // (ActivateExistingInstance в main.cpp) — и только он. Превратить его
    // кросс-процессный SetForegroundWindow в полноценный возврат (сказать Dart,
    // что окно снова на экране, снять g_window_hidden_in_tray) может лишь сам
    // получатель, поэтому ветка тут и живёт. Обратная сторона — любая другая
    // активация читается как просьба пользователя, и нативному коду брать это
    // окно ради Win32-API нельзя (см. docs/PITFALLS.md).
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
      // Same rule as WM_ACTIVATE: only intervene for a tray-hidden window.
      // Leave a taskbar-minimized (iconic) window to DefWindowProc so the
      // native restore/minimize taskbar toggle keeps working on Windows 10.
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
