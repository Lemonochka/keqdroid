#include "window_placement.h"

namespace {

constexpr wchar_t kRegistryKey[] = L"Software\\KeqDroid";
constexpr wchar_t kPlacementValue[] = L"MainWindowPlacement";

// меньше этого запись битая, такого размера пользователь окну не тянул
constexpr int kMinSavedWidth = 400;
constexpr int kMinSavedHeight = 300;

bool LoadSavedPlacement(WINDOWPLACEMENT* out) {
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kRegistryKey, 0, KEY_QUERY_VALUE,
                      &key) != ERROR_SUCCESS) {
    return false;
  }

  WINDOWPLACEMENT wp = {};
  DWORD type = 0;
  DWORD size = sizeof(wp);
  const LSTATUS status = ::RegQueryValueExW(
      key, kPlacementValue, nullptr, &type, reinterpret_cast<BYTE*>(&wp),
      &size);
  ::RegCloseKey(key);

  if (status != ERROR_SUCCESS || type != REG_BINARY || size != sizeof(wp)) {
    return false;
  }
  wp.length = sizeof(WINDOWPLACEMENT);

  const int width = wp.rcNormalPosition.right - wp.rcNormalPosition.left;
  const int height = wp.rcNormalPosition.bottom - wp.rcNormalPosition.top;
  if (width < kMinSavedWidth || height < kMinSavedHeight) {
    return false;
  }

  // мониторы могли смениться (ноутбук без дока): запись, не касающаяся ни одного, даёт окно по центру, а не за экраном
  if (::MonitorFromRect(&wp.rcNormalPosition, MONITOR_DEFAULTTONULL) ==
      nullptr) {
    return false;
  }

  *out = wp;
  return true;
}

}  // namespace

bool KeqdroidRestoreWindowPlacement(HWND hwnd, bool* out_maximized) {
  if (out_maximized != nullptr) {
    *out_maximized = false;
  }
  if (hwnd == nullptr) {
    return false;
  }

  WINDOWPLACEMENT wp = {};
  if (!LoadSavedPlacement(&wp)) {
    return false;
  }

  const bool maximized = wp.showCmd == SW_SHOWMAXIMIZED;
  if (out_maximized != nullptr) {
    *out_maximized = maximized;
  }

  // окно скрыто до первого кадра, поэтому только границы
  wp.showCmd = SW_HIDE;
  if (maximized) {
    wp.flags |= WPF_RESTORETOMAXIMIZED;
  }
  return ::SetWindowPlacement(hwnd, &wp) != FALSE;
}

void KeqdroidSaveWindowPlacement(HWND hwnd) {
  if (hwnd == nullptr || !::IsWindow(hwnd)) {
    return;
  }

  WINDOWPLACEMENT wp = {sizeof(WINDOWPLACEMENT)};
  if (!::GetWindowPlacement(hwnd, &wp)) {
    return;
  }
  if (wp.showCmd == SW_SHOWMINIMIZED) {
    return;
  }

  const int width = wp.rcNormalPosition.right - wp.rcNormalPosition.left;
  const int height = wp.rcNormalPosition.bottom - wp.rcNormalPosition.top;
  if (width < kMinSavedWidth || height < kMinSavedHeight) {
    return;
  }

  // спрятанное в трей отдаёт SW_HIDE, храним то, с чем открываться
  const bool maximized =
      wp.showCmd == SW_SHOWMAXIMIZED ||
      (wp.showCmd == SW_HIDE && (wp.flags & WPF_RESTORETOMAXIMIZED) != 0);
  wp.showCmd = maximized ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL;

  HKEY key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, kRegistryKey, 0, nullptr, 0,
                        KEY_SET_VALUE, nullptr, &key, nullptr) !=
      ERROR_SUCCESS) {
    return;
  }
  ::RegSetValueExW(key, kPlacementValue, 0, REG_BINARY,
                   reinterpret_cast<const BYTE*>(&wp),
                   static_cast<DWORD>(sizeof(wp)));
  ::RegCloseKey(key);
}
