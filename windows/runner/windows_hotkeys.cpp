#include "windows_hotkeys.h"

namespace {

// Arbitrary base away from other apps' common low ids; ids stay process-local.
constexpr int kHotkeyIdBase = 0xBE00;

std::vector<std::string> g_registered_actions;

}  // namespace

void KeqdroidUnregisterAllHotkeys(HWND hwnd) {
  for (size_t i = 0; i < g_registered_actions.size(); ++i) {
    ::UnregisterHotKey(hwnd, kHotkeyIdBase + static_cast<int>(i));
  }
  g_registered_actions.clear();
}

std::vector<std::string> KeqdroidApplyHotkeys(
    HWND hwnd, const std::vector<KeqdroidHotkeySpec>& specs) {
  std::vector<std::string> failed;
  if (hwnd == nullptr) {
    for (const auto& spec : specs) {
      failed.push_back(spec.action);
    }
    return failed;
  }

  KeqdroidUnregisterAllHotkeys(hwnd);

  for (const auto& spec : specs) {
    if (spec.virtual_key == 0) {
      continue;
    }
    const int id = kHotkeyIdBase + static_cast<int>(g_registered_actions.size());
    // MOD_NOREPEAT: держим клавишу — срабатывает один раз, а не как автоповтор
    // (иначе toggle-действия мгновенно включались-выключались).
    if (::RegisterHotKey(hwnd, id, spec.modifiers | MOD_NOREPEAT,
                         spec.virtual_key)) {
      g_registered_actions.push_back(spec.action);
    } else {
      failed.push_back(spec.action);
    }
  }
  return failed;
}

std::string KeqdroidHotkeyActionForId(int hotkey_id) {
  const int index = hotkey_id - kHotkeyIdBase;
  if (index < 0 ||
      index >= static_cast<int>(g_registered_actions.size())) {
    return std::string();
  }
  return g_registered_actions[static_cast<size_t>(index)];
}
