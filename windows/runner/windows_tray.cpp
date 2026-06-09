#include "windows_tray.h"

#include "resource.h"
#include "tunnel_channel_handler.h"

#include <dwmapi.h>
#include <shellapi.h>
#include <strsafe.h>

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif

#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif

namespace {

constexpr UINT kTrayCallbackMessage = WM_APP + 42;
constexpr UINT kTrayDismissClickMessage = WM_APP + 43;
constexpr UINT kTrayIconId = 1;

// NOTIFYICON_VERSION_4: LOWORD(lparam) is NIN_*; HIWORD is icon id.
#ifndef NIN_SELECT
#define NIN_SELECT 0
#endif
#ifndef NIN_OPEN
#define NIN_OPEN 2
#endif
#ifndef NIN_CONTEXTOPEN
#define NIN_CONTEXTOPEN 3
#endif
#ifndef NIN_CONTEXTSELECT
#define NIN_CONTEXTSELECT 4
#endif
constexpr int kPopupCornerRadiusLogical = 10;

NOTIFYICONDATAW g_tray = {};
bool g_tray_added = false;
bool g_tray_version_4 = false;
HWND g_tray_hwnd = nullptr;
bool g_minimize_to_tray = true;

struct TrayPopupState {
  bool active = false;
  bool was_visible = false;
  bool was_maximized = false;
  RECT restored_bounds = {};
  LONG style = 0;
  LONG ex_style = 0;
};

TrayPopupState g_popup;
HHOOK g_popup_mouse_hook = nullptr;
bool g_window_hidden_in_tray = false;
DWORD g_popup_ignore_clicks_until_tick = 0;

int PopupCornerRadiusPx(HWND hwnd) {
  const UINT dpi = ::GetDpiForWindow(hwnd);
  if (dpi == 0) {
    return kPopupCornerRadiusLogical;
  }
  return ::MulDiv(kPopupCornerRadiusLogical, static_cast<int>(dpi), 96);
}

void ApplyPopupRoundedCorners(HWND hwnd, int width, int height) {
  if (hwnd == nullptr || width <= 0 || height <= 0) {
    return;
  }

  const int radius = PopupCornerRadiusPx(hwnd);
  const int diameter = radius * 2;
  HRGN region =
      ::CreateRoundRectRgn(0, 0, width + 1, height + 1, diameter, diameter);
  if (region != nullptr) {
    ::SetWindowRgn(hwnd, region, TRUE);
  }

  const DWORD round_corners = DWMWCP_ROUND;
  ::DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &round_corners,
                          sizeof(round_corners));
}

void ClearPopupRoundedCorners(HWND hwnd) {
  if (hwnd == nullptr) {
    return;
  }
  ::SetWindowRgn(hwnd, nullptr, TRUE);
  const DWORD default_corners = 0;
  ::DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &default_corners,
                          sizeof(default_corners));
}

LRESULT CALLBACK TrayPopupMouseHookProc(int code,
                                        WPARAM wparam,
                                        LPARAM lparam);

void RemovePopupMouseHook() {
  if (g_popup_mouse_hook != nullptr) {
    ::UnhookWindowsHookEx(g_popup_mouse_hook);
    g_popup_mouse_hook = nullptr;
  }
}

void InstallPopupMouseHook() {
  RemovePopupMouseHook();
  g_popup_mouse_hook = ::SetWindowsHookExW(
      WH_MOUSE_LL, TrayPopupMouseHookProc, ::GetModuleHandleW(nullptr), 0);
}

LRESULT CALLBACK TrayPopupMouseHookProc(int code,
                                        WPARAM wparam,
                                        LPARAM lparam) {
  if (code >= 0 && g_popup.active && g_tray_hwnd != nullptr) {
    // Ignore the opening right-click (tray icon is outside popup bounds).
    if (::GetTickCount() < g_popup_ignore_clicks_until_tick) {
      return ::CallNextHookEx(g_popup_mouse_hook, code, wparam, lparam);
    }
    if (wparam == WM_LBUTTONDOWN || wparam == WM_MBUTTONDOWN) {
      const auto* info = reinterpret_cast<MSLLHOOKSTRUCT*>(lparam);
      if (info != nullptr) {
        RECT rect = {};
        if (::GetWindowRect(g_tray_hwnd, &rect) != FALSE) {
          const POINT pt = {info->pt.x, info->pt.y};
          if (!::PtInRect(&rect, pt)) {
            ::PostMessageW(g_tray_hwnd, kTrayDismissClickMessage, 0, 0);
          }
        }
      }
    }
  }
  return ::CallNextHookEx(g_popup_mouse_hook, code, wparam, lparam);
}

void DismissTrayMenuPopup(HWND hwnd, bool notify_dart) {
  if (!g_popup.active || hwnd == nullptr) {
    return;
  }
  if (notify_dart) {
    KeqdisNotifyTrayMenuClosedImmediate();
  }
  WindowsTrayHideMenuPopup(hwnd, false);
}

void ApplyWindowDarkMode(HWND hwnd, bool dark_theme) {
  if (hwnd == nullptr) {
    return;
  }
  BOOL enable_dark_mode = dark_theme ? TRUE : FALSE;
  ::DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &enable_dark_mode,
                          sizeof(enable_dark_mode));
}

void EnsureTrayIcon() {
  if (g_tray_added || g_tray_hwnd == nullptr) {
    return;
  }

  g_tray = {};
  g_tray.cbSize = sizeof(NOTIFYICONDATAW);
  g_tray.hWnd = g_tray_hwnd;
  g_tray.uID = kTrayIconId;
  g_tray.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  g_tray.uCallbackMessage = kTrayCallbackMessage;
  g_tray.hIcon = ::LoadIconW(::GetModuleHandleW(nullptr),
                             MAKEINTRESOURCEW(IDI_APP_ICON));
  if (g_tray.hIcon == nullptr) {
    g_tray.hIcon = ::LoadIconW(nullptr, IDI_APPLICATION);
  }
  StringCchCopyW(g_tray.szTip, ARRAYSIZE(g_tray.szTip), L"KeqDroid");

  if (::Shell_NotifyIconW(NIM_ADD, &g_tray)) {
    g_tray_added = true;
    NOTIFYICONDATAW version_data = g_tray;
    version_data.uVersion = NOTIFYICON_VERSION_4;
    g_tray_version_4 =
        ::Shell_NotifyIconW(NIM_SETVERSION, &version_data) != FALSE;
  }
}

void RemoveTrayIcon() {
  if (!g_tray_added) {
    return;
  }
  ::Shell_NotifyIconW(NIM_DELETE, &g_tray);
  g_tray_added = false;
  g_tray_version_4 = false;
}

void HideWindowToTray(HWND hwnd) {
  EnsureTrayIcon();
  g_window_hidden_in_tray = true;
  ::ShowWindow(hwnd, SW_HIDE);
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
  KeqdisNotifyTrayMenuClosedImmediate();
  g_window_hidden_in_tray = false;
  if (g_popup.active) {
    WindowsTrayHideMenuPopup(g_tray_hwnd, true);
    ::SetForegroundWindow(g_tray_hwnd);
    return true;
  }
  if (::IsIconic(g_tray_hwnd)) {
    ::ShowWindow(g_tray_hwnd, SW_RESTORE);
  } else if (!::IsWindowVisible(g_tray_hwnd)) {
    ::ShowWindow(g_tray_hwnd, SW_SHOW);
  } else {
    ::ShowWindow(g_tray_hwnd, SW_SHOW);
  }
  ::SetForegroundWindow(g_tray_hwnd);
  return true;
}

bool WindowsTrayRestoreMainWindow() {
  return WindowsTrayActivateMainWindow();
}

void WindowsTrayShowMenuPopup(HWND hwnd,
                              int anchor_x,
                              int anchor_y,
                              int width,
                              int height,
                              bool dark_theme) {
  if (hwnd == nullptr || width <= 0 || height <= 0) {
    return;
  }

  if (!g_popup.active) {
    g_popup = {};
    g_popup.was_visible = ::IsWindowVisible(hwnd) != FALSE;
    WINDOWPLACEMENT placement = {sizeof(WINDOWPLACEMENT)};
    if (::GetWindowPlacement(hwnd, &placement)) {
      g_popup.was_maximized = placement.showCmd == SW_SHOWMAXIMIZED;
    }
    ::GetWindowRect(hwnd, &g_popup.restored_bounds);
    g_popup.style = ::GetWindowLongW(hwnd, GWL_STYLE);
    g_popup.ex_style = ::GetWindowLongW(hwnd, GWL_EXSTYLE);
  }

  const LONG popup_style = WS_POPUP;
  const LONG popup_ex_style =
      (g_popup.ex_style | WS_EX_TOOLWINDOW | WS_EX_TOPMOST) & ~WS_EX_APPWINDOW;
  ::SetWindowLongW(hwnd, GWL_STYLE, popup_style);
  ::SetWindowLongW(hwnd, GWL_EXSTYLE, popup_ex_style);

  int x = anchor_x - width;
  int y = anchor_y - height;
  if (x < 0) {
    x = 0;
  }
  if (y < 0) {
    y = 0;
  }

  ApplyWindowDarkMode(hwnd, dark_theme);
  g_popup.active = true;
  g_popup_ignore_clicks_until_tick = ::GetTickCount() + 400;
  ::SetWindowPos(hwnd, HWND_TOPMOST, x, y, width, height,
                 SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  ApplyPopupRoundedCorners(hwnd, width, height);
  InstallPopupMouseHook();
  ::SetForegroundWindow(hwnd);
}

void WindowsTrayResizeMenuPopup(HWND hwnd, int width, int height) {
  if (!g_popup.active || hwnd == nullptr || width <= 0 || height <= 0) {
    return;
  }
  RECT rect = {};
  ::GetWindowRect(hwnd, &rect);
  const int x = rect.left;
  const int bottom = rect.bottom;
  int top = bottom - height;
  if (top < 0) {
    top = 0;
  }
  ::SetWindowPos(hwnd, HWND_TOPMOST, x, top, width, height,
                 SWP_NOACTIVATE | SWP_FRAMECHANGED);
  ApplyPopupRoundedCorners(hwnd, width, height);
}

void WindowsTrayHideMenuPopup(HWND hwnd, bool activate_main) {
  if (!g_popup.active || hwnd == nullptr) {
    return;
  }

  RemovePopupMouseHook();
  ClearPopupRoundedCorners(hwnd);

  // Hide while still a popup to avoid flashing a full-size window.
  ::ShowWindow(hwnd, SW_HIDE);

  ::SetWindowLongW(hwnd, GWL_STYLE, g_popup.style);
  ::SetWindowLongW(hwnd, GWL_EXSTYLE, g_popup.ex_style);

  const int width = g_popup.restored_bounds.right - g_popup.restored_bounds.left;
  const int height =
      g_popup.restored_bounds.bottom - g_popup.restored_bounds.top;
  ::SetWindowPos(hwnd, nullptr, g_popup.restored_bounds.left,
                 g_popup.restored_bounds.top, width, height,
                 SWP_NOZORDER | SWP_FRAMECHANGED | SWP_NOACTIVATE);

  if (activate_main) {
    g_window_hidden_in_tray = false;
    if (g_popup.was_maximized) {
      ::ShowWindow(hwnd, SW_MAXIMIZE);
    } else {
      ::ShowWindow(hwnd, SW_SHOW);
    }
  } else {
    const bool show_restored =
        g_popup.was_visible && !g_window_hidden_in_tray;
    if (show_restored) {
      if (g_popup.was_maximized) {
        ::ShowWindow(hwnd, SW_MAXIMIZE);
      } else {
        ::ShowWindow(hwnd, SW_SHOW);
      }
    } else {
      ::ShowWindow(hwnd, SW_HIDE);
      EnsureTrayIcon();
    }
  }

  g_popup.active = false;
  g_popup_ignore_clicks_until_tick = 0;
}

void WindowsTrayExitApplication(HWND hwnd) {
  if (g_popup.active) {
    WindowsTrayHideMenuPopup(hwnd, false);
  }
  RemoveTrayIcon();
  if (hwnd != nullptr && ::IsWindow(hwnd)) {
    ::DestroyWindow(hwnd);
  }
  ::PostQuitMessage(0);
}

void WindowsTrayDispose(HWND hwnd) {
  (void)hwnd;
  RemovePopupMouseHook();
  RemoveTrayIcon();
  g_tray_hwnd = nullptr;
  g_tray_version_4 = false;
  g_popup = {};
}

bool WindowsTrayHandleMessage(HWND hwnd,
                              UINT message,
                              WPARAM wparam,
                              LPARAM lparam,
                              LRESULT* result) {
  if (message == kTrayDismissClickMessage && g_popup.active) {
    DismissTrayMenuPopup(hwnd, true);
    if (result != nullptr) {
      *result = 0;
    }
    return true;
  }

  if (message == WM_ACTIVATE) {
    const WORD state = LOWORD(wparam);
    if (state == WA_INACTIVE) {
      if (g_popup.active) {
        if (::GetTickCount() >= g_popup_ignore_clicks_until_tick) {
          DismissTrayMenuPopup(hwnd, true);
        }
        if (result != nullptr) {
          *result = 0;
        }
        return true;
      }
      return false;
    }

    if (g_popup.active) {
      return false;
    }

    if (g_window_hidden_in_tray || ::IsIconic(hwnd) ||
        !::IsWindowVisible(hwnd)) {
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
      if (g_popup.active || g_window_hidden_in_tray || ::IsIconic(hwnd) ||
          !::IsWindowVisible(hwnd)) {
        WindowsTrayActivateMainWindow();
        if (result != nullptr) {
          *result = 0;
        }
        return true;
      }
    }
    return false;
  }

  if (message == kTrayCallbackMessage) {
    const UINT notification = LOWORD(lparam);
    const UINT event = static_cast<UINT>(lparam);

    const bool activate_main =
        notification == NIN_SELECT || notification == NIN_OPEN ||
        notification == WM_LBUTTONUP || notification == WM_LBUTTONDBLCLK ||
        event == WM_LBUTTONUP || event == WM_LBUTTONDBLCLK;

    const bool open_tray_menu =
        notification == NIN_CONTEXTOPEN ||
        notification == NIN_CONTEXTSELECT ||
        notification == WM_RBUTTONUP || notification == WM_CONTEXTMENU ||
        event == WM_RBUTTONUP || event == WM_CONTEXTMENU;

    if (activate_main) {
      WindowsTrayActivateMainWindow();
      if (result != nullptr) {
        *result = 0;
      }
      return true;
    }
    if (open_tray_menu) {
      KeqdisRequestTrayMenu();
      if (result != nullptr) {
        *result = 0;
      }
      return true;
    }
    return false;
  }

  if (message == WM_CLOSE) {
    if (g_popup.active) {
      KeqdisNotifyTrayMenuClosedImmediate();
      WindowsTrayHideMenuPopup(hwnd, false);
      if (result != nullptr) {
        *result = 0;
      }
      return true;
    }
    if (g_minimize_to_tray) {
      HideWindowToTray(hwnd);
    } else {
      RemoveTrayIcon();
      ::DestroyWindow(hwnd);
    }
    if (result != nullptr) {
      *result = 0;
    }
    return true;
  }

  return false;
}
