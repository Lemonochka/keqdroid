#ifndef RUNNER_WINDOWS_APPS_LIST_H_
#define RUNNER_WINDOWS_APPS_LIST_H_

#include <flutter/standard_method_codec.h>

flutter::EncodableList ListWindowsApps(bool include_system);

/// Lazy icon load for a single exe/icon path (PNG base64).
std::string GetWindowsAppIconBase64(const std::wstring& icon_source);

#endif  // RUNNER_WINDOWS_APPS_LIST_H_
