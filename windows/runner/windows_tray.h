#ifndef RUNNER_WINDOWS_TRAY_H_
#define RUNNER_WINDOWS_TRAY_H_

#include <windows.h>

// Окно и трей: скрытие по WM_CLOSE, возврат на экран, выход.
//
// Саму иконку в трее и её меню держит tray_manager на стороне Dart
// (lib/services/windows_tray_menu.dart) — здесь только окно.
void WindowsTrayInit(HWND hwnd);
void WindowsTrayDispose(HWND hwnd);
void WindowsTraySetMinimizeToTray(bool enabled);
bool WindowsTrayGetMinimizeToTray();
HWND WindowsTrayGetMainHwnd();
bool WindowsTrayActivateMainWindow();
bool WindowsTrayRestoreMainWindow();
// Hotkey "show/hide window": visible window hides to tray, hidden restores.
bool WindowsTrayToggleMainWindow();
void WindowsTrayExitApplication(HWND hwnd);
bool WindowsTrayHandleMessage(HWND hwnd,
                              UINT message,
                              WPARAM wparam,
                              LPARAM lparam,
                              LRESULT* result);

#endif  // RUNNER_WINDOWS_TRAY_H_
