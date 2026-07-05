#ifndef RUNNER_WINDOW_PLACEMENT_H_
#define RUNNER_WINDOW_PLACEMENT_H_

#include <windows.h>

// Persists the main window bounds (position + size + maximized state) in
// HKCU so the app reopens where the user left it, including autostart runs.
//
// Saving is guarded against the tray popup: the popup reuses the main HWND
// with WS_POPUP styling and ~288px width, so any window without WS_CAPTION
// is never persisted.

// Applies the saved placement to |hwnd| (which must still be hidden).
// Returns true when a valid placement was applied; |out_maximized| is set to
// true when the window should be shown maximized.
bool KeqdroidRestoreWindowPlacement(HWND hwnd, bool* out_maximized);

// Saves the current placement of |hwnd| to the registry. No-ops for popup
// styled (tray menu) and minimized windows.
void KeqdroidSaveWindowPlacement(HWND hwnd);

#endif  // RUNNER_WINDOW_PLACEMENT_H_
