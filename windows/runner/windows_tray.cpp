#include "windows_tray.h"

#include "resource.h"

#include <shellapi.h>
#include <strsafe.h>

namespace {

constexpr UINT kTrayCallbackMessage = WM_APP + 42;
constexpr UINT kTrayIconId = 1;

constexpr UINT kCmdTrayShow = 40001;
constexpr UINT kCmdTrayExit = 40002;

NOTIFYICONDATAW g_tray = {};
bool g_tray_added = false;
HWND g_tray_hwnd = nullptr;
bool g_minimize_to_tray = true;

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
  }
}

void RemoveTrayIcon() {
  if (!g_tray_added) {
    return;
  }
  ::Shell_NotifyIconW(NIM_DELETE, &g_tray);
  g_tray_added = false;
}

void ShowTrayContextMenu(HWND hwnd) {
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  ::AppendMenuW(menu, MF_STRING, kCmdTrayShow, L"Show KeqDroid");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kCmdTrayExit, L"Exit");

  POINT cursor;
  ::GetCursorPos(&cursor);
  ::SetForegroundWindow(hwnd);

  const UINT flags = TPM_RIGHTALIGN | TPM_BOTTOMALIGN | TPM_RETURNCMD;
  const UINT cmd = ::TrackPopupMenu(menu, flags, cursor.x, cursor.y, 0, hwnd, nullptr);
  ::DestroyMenu(menu);

  if (cmd == kCmdTrayShow) {
    ::ShowWindow(hwnd, SW_SHOW);
    ::SetForegroundWindow(hwnd);
  } else if (cmd == kCmdTrayExit) {
    RemoveTrayIcon();
    ::DestroyWindow(hwnd);
    ::PostQuitMessage(0);
  }
}

void HideWindowToTray(HWND hwnd) {
  EnsureTrayIcon();
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

bool WindowsTrayActivateMainWindow() {
  if (g_tray_hwnd == nullptr || !::IsWindow(g_tray_hwnd)) {
    return false;
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

void WindowsTrayDispose(HWND hwnd) {
  (void)hwnd;
  RemoveTrayIcon();
  g_tray_hwnd = nullptr;
}

bool WindowsTrayHandleMessage(HWND hwnd,
                              UINT message,
                              WPARAM wparam,
                              LPARAM lparam,
                              LRESULT* result) {
  if (message == kTrayCallbackMessage) {
    const UINT event = static_cast<UINT>(lparam);
    if (event == WM_LBUTTONDBLCLK || event == NIN_SELECT) {
      ::ShowWindow(hwnd, SW_SHOW);
      ::SetForegroundWindow(hwnd);
      if (result != nullptr) {
        *result = 0;
      }
      return true;
    }
    if (event == WM_RBUTTONUP || event == WM_CONTEXTMENU) {
      ShowTrayContextMenu(hwnd);
      if (result != nullptr) {
        *result = 0;
      }
      return true;
    }
    return false;
  }

  if (message == WM_CLOSE) {
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

  if (message == WM_COMMAND) {
    const UINT cmd = LOWORD(wparam);
    if (cmd == kCmdTrayShow) {
      ::ShowWindow(hwnd, SW_SHOW);
      ::SetForegroundWindow(hwnd);
      if (result != nullptr) {
        *result = 0;
      }
      return true;
    }
    if (cmd == kCmdTrayExit) {
      RemoveTrayIcon();
      if (result != nullptr) {
        *result = 0;
      }
      ::DestroyWindow(hwnd);
      ::PostQuitMessage(0);
      return true;
    }
  }

  return false;
}
