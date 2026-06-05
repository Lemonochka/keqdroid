#ifndef RUNNER_WINDOWS_TRAY_H_
#define RUNNER_WINDOWS_TRAY_H_

#include <windows.h>

// System tray: hide on WM_CLOSE, restore from icon / menu.
void WindowsTrayInit(HWND hwnd);
void WindowsTrayDispose(HWND hwnd);
bool WindowsTrayHandleMessage(HWND hwnd,
                              UINT message,
                              WPARAM wparam,
                              LPARAM lparam,
                              LRESULT* result);

#endif  // RUNNER_WINDOWS_TRAY_H_
