#ifndef RUNNER_WINDOWS_TRAY_H_
#define RUNNER_WINDOWS_TRAY_H_

#include <windows.h>

// System tray: hide on WM_CLOSE, restore from icon / menu.
void WindowsTrayInit(HWND hwnd);
void WindowsTrayDispose(HWND hwnd);
void WindowsTraySetMinimizeToTray(bool enabled);
bool WindowsTrayGetMinimizeToTray();
HWND WindowsTrayGetMainHwnd();
bool WindowsTrayActivateMainWindow();
bool WindowsTrayRestoreMainWindow();
void WindowsTrayShowMenuPopup(HWND hwnd,
                              int anchor_x,
                              int anchor_y,
                              int width,
                              int height,
                              bool dark_theme);
void WindowsTrayHideMenuPopup(HWND hwnd, bool activate_main);
void WindowsTrayResizeMenuPopup(HWND hwnd, int width, int height);
void WindowsTrayExitApplication(HWND hwnd);
bool WindowsTrayHandleMessage(HWND hwnd,
                              UINT message,
                              WPARAM wparam,
                              LPARAM lparam,
                              LRESULT* result);

#endif  // RUNNER_WINDOWS_TRAY_H_
