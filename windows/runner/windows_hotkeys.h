#ifndef RUNNER_WINDOWS_HOTKEYS_H_
#define RUNNER_WINDOWS_HOTKEYS_H_

#include <windows.h>

#include <string>
#include <vector>

// System-wide hotkeys via RegisterHotKey. The Dart side sends the bindings
// (action id + MOD_* mask + VK code) over the method channel; WM_HOTKEY is
// routed back to Dart as "onHotkeyPressed" with the action id.

struct KeqdroidHotkeySpec {
  std::string action;    // Dart-side action id, echoed back on WM_HOTKEY.
  UINT modifiers = 0;    // MOD_ALT | MOD_CONTROL | MOD_SHIFT | MOD_WIN.
  UINT virtual_key = 0;  // VK_* code.
};

// (Re)registers the given set of global hotkeys on |hwnd|; previously
// registered ones are unregistered first. Returns the actions that could NOT
// be registered (combo already taken by another application).
std::vector<std::string> KeqdroidApplyHotkeys(
    HWND hwnd, const std::vector<KeqdroidHotkeySpec>& specs);

// Resolves a WM_HOTKEY id back to its action. Empty string when unknown.
std::string KeqdroidHotkeyActionForId(int hotkey_id);

void KeqdroidUnregisterAllHotkeys(HWND hwnd);

#endif  // RUNNER_WINDOWS_HOTKEYS_H_
