#include "windows_apps_list.h"

#include <windows.h>
#include <tlhelp32.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <psapi.h>
#include <gdiplus.h>

#include <algorithm>
#include <map>
#include <set>
#include <string>
#include <vector>

#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "psapi.lib")

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

struct AppEntry {
  std::wstring exe_name;
  std::wstring display_name;
  std::wstring install_path;
  bool is_system = false;
  bool is_running = false;
  std::string icon_base64;
};

ULONG_PTR g_gdiplus_token = 0;

void EnsureGdiplus() {
  if (g_gdiplus_token != 0) return;
  Gdiplus::GdiplusStartupInput input;
  Gdiplus::GdiplusStartup(&g_gdiplus_token, &input, nullptr);
}

std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                       static_cast<int>(wide.size()), nullptr, 0,
                                       nullptr, nullptr);
  if (size <= 0) return {};
  std::string utf8(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()),
                      utf8.data(), size, nullptr, nullptr);
  return utf8;
}

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                       static_cast<int>(utf8.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring wide(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                      wide.data(), size);
  return wide;
}

std::wstring ToLower(std::wstring s) {
  std::transform(s.begin(), s.end(), s.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
  return s;
}

std::wstring BaseName(const std::wstring& path) {
  const wchar_t* name = PathFindFileNameW(path.c_str());
  return name ? std::wstring(name) : path;
}

std::string Base64Encode(const unsigned char* data, size_t len) {
  static const char kTable[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string out;
  out.reserve(((len + 2) / 3) * 4);
  for (size_t i = 0; i < len; i += 3) {
    const unsigned int b0 = data[i];
    const unsigned int b1 = (i + 1 < len) ? data[i + 1] : 0;
    const unsigned int b2 = (i + 2 < len) ? data[i + 2] : 0;
    const unsigned int n = (b0 << 16) | (b1 << 8) | b2;
    out.push_back(kTable[(n >> 18) & 63]);
    out.push_back(kTable[(n >> 12) & 63]);
    out.push_back((i + 1 < len) ? kTable[(n >> 6) & 63] : '=');
    out.push_back((i + 2 < len) ? kTable[n & 63] : '=');
  }
  return out;
}

int GetEncoderClsid(const WCHAR* format, CLSID* pClsid) {
  UINT num = 0;
  UINT size = 0;
  Gdiplus::GetImageEncodersSize(&num, &size);
  if (size == 0) return -1;
  std::vector<BYTE> buffer(size);
  auto* codecs = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
  Gdiplus::GetImageEncoders(num, size, codecs);
  for (UINT i = 0; i < num; ++i) {
    if (wcscmp(codecs[i].MimeType, format) == 0) {
      *pClsid = codecs[i].Clsid;
      return static_cast<int>(i);
    }
  }
  return -1;
}

std::string IconFileToBase64Png(const std::wstring& icon_source) {
  if (icon_source.empty()) return {};
  EnsureGdiplus();

  std::wstring path = icon_source;
  int index = 0;
  const size_t comma = path.find(L',');
  if (comma != std::wstring::npos) {
    index = _wtoi(path.substr(comma + 1).c_str());
    path = path.substr(0, comma);
  }
  path.erase(std::remove(path.begin(), path.end(), L'"'), path.end());

  HICON hicon = nullptr;
  if (PathFileExistsW(path.c_str())) {
    hicon = ExtractIconW(nullptr, path.c_str(), index);
    // ExtractIconW returns (HICON)1 when the file exists but has no icon at index.
    if (hicon == reinterpret_cast<HICON>(1)) {
      hicon = nullptr;
    }
    if (!hicon) {
      SHFILEINFOW sfi = {};
      if (SHGetFileInfoW(path.c_str(), 0, &sfi, sizeof(sfi),
                         SHGFI_ICON | SHGFI_LARGEICON)) {
        hicon = sfi.hIcon;
      }
    }
  }
  if (!hicon) return {};

  std::unique_ptr<Gdiplus::Bitmap> bmp(Gdiplus::Bitmap::FromHICON(hicon));
  DestroyIcon(hicon);
  if (!bmp || bmp->GetLastStatus() != Gdiplus::Ok) return {};

  CLSID png_clsid{};
  if (GetEncoderClsid(L"image/png", &png_clsid) < 0) return {};

  IStream* stream = nullptr;
  if (CreateStreamOnHGlobal(nullptr, TRUE, &stream) != S_OK) return {};
  const Gdiplus::Status st = bmp->Save(stream, &png_clsid, nullptr);
  if (st != Gdiplus::Ok) {
    stream->Release();
    return {};
  }

  STATSTG stat{};
  stream->Stat(&stat, STATFLAG_NONAME);
  const ULONG size = stat.cbSize.LowPart;
  std::vector<unsigned char> bytes(size);
  LARGE_INTEGER zero{};
  stream->Seek(zero, STREAM_SEEK_SET, nullptr);
  ULONG read = 0;
  stream->Read(bytes.data(), size, &read);
  stream->Release();
  if (read == 0) return {};
  return Base64Encode(bytes.data(), read);
}

bool IsUnderWindowsDir(const std::wstring& path_lower) {
  return path_lower.find(L"\\windows\\") != std::wstring::npos ||
         path_lower.find(L"\\windowsapps\\") != std::wstring::npos ||
         path_lower.find(L"\\winnt\\") != std::wstring::npos;
}

bool ShouldSkipExe(const std::wstring& exe_lower, const std::wstring& path_lower) {
  static const wchar_t* kSkip[] = {
      L"svchost.exe", L"csrss.exe", L"smss.exe", L"lsass.exe", L"services.exe",
      L"dwm.exe", L"conhost.exe", L"dllhost.exe", L"runtimebroker.exe",
      L"searchhost.exe", L"sihost.exe", L"ctfmon.exe", L"fontdrvhost.exe",
      L"wininit.exe", L"winlogon.exe", L"audiodg.exe", L"spoolsv.exe",
      L"taskhostw.exe", L"shellexperiencehost.exe", L"applicationframehost.exe",
      L"system", L"registry", L"idle", L"secure system", L"memory compression",
      L"searchindexer.exe", L"wmiprvse.exe", L"msmpeng.exe", L"ngentask.exe",
      L"aggregatorhost.exe", L"securityhealthservice.exe",
  };
  for (const auto* name : kSkip) {
    if (exe_lower == name) return true;
  }
  if (exe_lower.find(L"directx") != std::wstring::npos) return true;
  if (exe_lower.find(L"vc_redist") != std::wstring::npos) return true;
  if (exe_lower.find(L"setup") != std::wstring::npos &&
      path_lower.find(L"\\installer\\") != std::wstring::npos) {
    return true;
  }
  if (!path_lower.empty() && IsUnderWindowsDir(path_lower)) return true;
  return false;
}

bool IsSystemPath(const std::wstring& path_lower) {
  return IsUnderWindowsDir(path_lower) ||
         path_lower.find(L"\\program files\\windows") != std::wstring::npos ||
         path_lower.find(L"\\program files (x86)\\windows") != std::wstring::npos;
}

std::wstring RegQueryString(HKEY key, const wchar_t* value_name) {
  DWORD type = 0;
  DWORD size = 0;
  if (RegQueryValueExW(key, value_name, nullptr, &type, nullptr, &size) !=
          ERROR_SUCCESS ||
      (type != REG_SZ && type != REG_EXPAND_SZ) || size < 2) {
    return {};
  }
  std::vector<wchar_t> buf(size / sizeof(wchar_t) + 1, L'\0');
  if (RegQueryValueExW(key, value_name, nullptr, &type,
                       reinterpret_cast<LPBYTE>(buf.data()), &size) !=
      ERROR_SUCCESS) {
    return {};
  }
  return std::wstring(buf.data());
}

DWORD RegQueryDword(HKEY key, const wchar_t* value_name, DWORD fallback) {
  DWORD type = 0;
  DWORD data = 0;
  DWORD size = sizeof(data);
  if (RegQueryValueExW(key, value_name, nullptr, &type,
                       reinterpret_cast<LPBYTE>(&data), &size) != ERROR_SUCCESS ||
      type != REG_DWORD) {
    return fallback;
  }
  return data;
}

void UpsertApp(std::map<std::wstring, AppEntry>& apps, AppEntry entry) {
  const std::wstring key = ToLower(entry.exe_name);
  if (key.empty()) return;
  auto it = apps.find(key);
  if (it == apps.end()) {
    apps.emplace(key, std::move(entry));
    return;
  }
  AppEntry& existing = it->second;
  if (entry.is_running) existing.is_running = true;
  if (!entry.display_name.empty() && existing.display_name.size() < entry.display_name.size()) {
    existing.display_name = entry.display_name;
  }
  if (!entry.install_path.empty() && existing.install_path.empty()) {
    existing.install_path = entry.install_path;
  }
  if (entry.icon_base64.size() > existing.icon_base64.size()) {
    existing.icon_base64 = std::move(entry.icon_base64);
  }
  existing.is_system = existing.is_system || entry.is_system;
}

void CollectRunning(std::map<std::wstring, AppEntry>& apps, bool include_system) {
  HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snap == INVALID_HANDLE_VALUE) return;

  PROCESSENTRY32W pe{};
  pe.dwSize = sizeof(pe);
  if (Process32FirstW(snap, &pe)) {
    do {
      if (pe.th32ProcessID <= 4) continue;
      HANDLE proc =
          OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pe.th32ProcessID);
      if (!proc) continue;

      wchar_t path_buf[MAX_PATH * 4] = {};
      DWORD path_len = static_cast<DWORD>(std::size(path_buf));
      std::wstring full_path;
      if (QueryFullProcessImageNameW(proc, 0, path_buf, &path_len)) {
        full_path.assign(path_buf, path_len);
      }
      CloseHandle(proc);

      if (full_path.empty()) continue;
      const std::wstring exe = BaseName(full_path);
      const std::wstring exe_lower = ToLower(exe);
      const std::wstring path_lower = ToLower(full_path);
      if (ShouldSkipExe(exe_lower, path_lower)) continue;

      const bool is_sys = IsSystemPath(path_lower);
      if (is_sys && !include_system) continue;

      AppEntry entry;
      entry.exe_name = exe;
      entry.display_name = pe.szExeFile;
      entry.install_path = full_path;
      entry.is_system = is_sys;
      entry.is_running = true;
      UpsertApp(apps, std::move(entry));
    } while (Process32NextW(snap, &pe));
  }
  CloseHandle(snap);
}

void CollectFromUninstallKey(HKEY root,
                             const std::wstring& subkey,
                             std::map<std::wstring, AppEntry>& apps,
                             bool include_system) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(root, subkey.c_str(), 0, KEY_READ, &key) != ERROR_SUCCESS) {
    return;
  }

  DWORD index = 0;
  wchar_t sub_name[256];
  DWORD sub_len = 256;
  while (RegEnumKeyExW(key, index++, sub_name, &sub_len, nullptr, nullptr, nullptr,
                       nullptr) == ERROR_SUCCESS) {
    HKEY app_key = nullptr;
    if (RegOpenKeyExW(key, sub_name, 0, KEY_READ, &app_key) == ERROR_SUCCESS) {
      if (RegQueryDword(app_key, L"SystemComponent", 0) == 1 ||
          RegQueryDword(app_key, L"NoDisplay", 0) == 1) {
        RegCloseKey(app_key);
        sub_len = 256;
        continue;
      }

      const std::wstring display_name = RegQueryString(app_key, L"DisplayName");
      std::wstring icon = RegQueryString(app_key, L"DisplayIcon");
      std::wstring install = RegQueryString(app_key, L"InstallLocation");
      if (display_name.empty()) {
        RegCloseKey(app_key);
        sub_len = 256;
        continue;
      }

      std::wstring exe_path;
      if (!icon.empty()) {
        std::wstring icon_path = icon;
        const size_t comma = icon_path.find(L',');
        if (comma != std::wstring::npos) {
          icon_path = icon_path.substr(0, comma);
        }
        icon_path.erase(std::remove(icon_path.begin(), icon_path.end(), L'"'),
                        icon_path.end());
        if (icon_path.size() > 4 &&
            ToLower(icon_path.substr(icon_path.size() - 4)) == L".exe") {
          exe_path = icon_path;
        }
      }
      if (exe_path.empty() && !install.empty()) {
        // Heuristic: first DisplayIcon often points to uninstaller; keep install path.
        exe_path = install;
      }

      if (!exe_path.empty() && exe_path.find(L".exe") == std::wstring::npos &&
          exe_path.find(L".EXE") == std::wstring::npos) {
        RegCloseKey(app_key);
        sub_len = 256;
        continue;
      }

      std::wstring exe_name;
      if (exe_path.find(L".exe") != std::wstring::npos ||
          exe_path.find(L".EXE") != std::wstring::npos) {
        exe_name = BaseName(exe_path);
      } else {
        RegCloseKey(app_key);
        sub_len = 256;
        continue;
      }

      const std::wstring exe_lower = ToLower(exe_name);
      const std::wstring path_lower = ToLower(exe_path);
      if (ShouldSkipExe(exe_lower, path_lower)) {
        RegCloseKey(app_key);
        sub_len = 256;
        continue;
      }

      const bool is_sys = IsSystemPath(path_lower);
      if (is_sys && !include_system) {
        RegCloseKey(app_key);
        sub_len = 256;
        continue;
      }

      AppEntry entry;
      entry.exe_name = exe_name;
      entry.display_name = display_name;
      entry.install_path = exe_path;
      entry.is_system = is_sys;
      UpsertApp(apps, std::move(entry));
      RegCloseKey(app_key);
    }
    sub_len = 256;
  }
  RegCloseKey(key);
}

EncodableMap ToEncodable(const AppEntry& e) {
  EncodableMap m;
  m[EncodableValue("packageName")] = EncodableValue(WideToUtf8(e.exe_name));
  m[EncodableValue("appName")] = EncodableValue(WideToUtf8(e.display_name));
  m[EncodableValue("isSystem")] = EncodableValue(e.is_system);
  m[EncodableValue("isRunning")] = EncodableValue(e.is_running);
  if (!e.install_path.empty()) {
    m[EncodableValue("installPath")] = EncodableValue(WideToUtf8(e.install_path));
  }
  if (!e.icon_base64.empty()) {
    m[EncodableValue("iconBase64")] = EncodableValue(e.icon_base64);
  }
  return m;
}

}  // namespace

flutter::EncodableList ListWindowsApps(bool include_system) {
  EnsureGdiplus();
  std::map<std::wstring, AppEntry> apps;
  CollectRunning(apps, include_system);

  const std::wstring uninstall =
      L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall";
  CollectFromUninstallKey(HKEY_LOCAL_MACHINE, uninstall, apps, include_system);
  CollectFromUninstallKey(HKEY_CURRENT_USER, uninstall, apps, include_system);
  CollectFromUninstallKey(HKEY_LOCAL_MACHINE,
                          L"SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
                          apps, include_system);

  std::vector<AppEntry> sorted;
  sorted.reserve(apps.size());
  for (auto& kv : apps) {
    sorted.push_back(std::move(kv.second));
  }

  std::sort(sorted.begin(), sorted.end(), [](const AppEntry& a, const AppEntry& b) {
    if (a.is_running != b.is_running) return a.is_running > b.is_running;
    return a.display_name < b.display_name;
  });

  if (sorted.size() > 600) {
    sorted.resize(600);
  }

  flutter::EncodableList out;
  out.reserve(sorted.size());
  for (const auto& e : sorted) {
    out.emplace_back(ToEncodable(e));
  }
  return out;
}

std::string GetWindowsAppIconBase64(const std::wstring& icon_source) {
  return IconFileToBase64Png(icon_source);
}
