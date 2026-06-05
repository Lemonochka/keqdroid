#include "tunnel_channel_handler.h"
#include "proxy_debug_log.h"
#include "single_instance.h"
#include "windows_apps_list.h"
#include "windows_core_lifecycle.h"
#include "windows_traffic_stats.h"
#include "windows_tray.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <shellapi.h>
#include <windows.h>
#include <wininet.h>
#include <winhttp.h>

#include <cstdio>
#include <functional>
#include <memory>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <vector>

#ifndef INTERNET_OPTION_PROXY_SETTINGS_CHANGED
#define INTERNET_OPTION_PROXY_SETTINGS_CHANGED 95
#endif

#ifndef INTERNET_OPTION_PER_CONNECTION_OPTION
#define INTERNET_OPTION_PER_CONNECTION_OPTION 75
#endif

#ifndef WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY
#define WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY 4
#endif

namespace {

constexpr char kChannel[] = "keqdis_vpn_channel";

static const wchar_t kProxyBypass[] = L"127.0.0.1;<local>;::1;localhost";
// WinINet per-connection API rejects some bypass tokens (e.g. "<local>") with 0x57.
static const wchar_t kPerConnBypass[] = L"localhost;127.0.0.1;::1";

static const wchar_t kInternetSettingsKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";
static const wchar_t kConnectionsKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings\\Connections";

std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) {
    return std::string();
  }
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                         static_cast<int>(wide.size()), nullptr, 0,
                                         nullptr, nullptr);
  if (size <= 0) {
    return std::string();
  }
  std::string utf8(static_cast<size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()),
                        utf8.data(), size, nullptr, nullptr);
  return utf8;
}

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int size = ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                         static_cast<int>(utf8.size()), nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                        wide.data(), size);
  return wide;
}

void NotifyProxySettingsChanged() {
  InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
  InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
  InternetSetOptionW(nullptr, INTERNET_OPTION_PROXY_SETTINGS_CHANGED, nullptr, 0);

  // Chromium / WinINET read HKCU Internet Settings after this broadcast.
  SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                      reinterpret_cast<LPARAM>(const_cast<wchar_t*>(L"InternetSettings")),
                      SMTO_ABORTIFHUNG, 5000, nullptr);
  SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                      reinterpret_cast<LPARAM>(const_cast<wchar_t*>(L"ProxyEnable")),
                      SMTO_ABORTIFHUNG, 5000, nullptr);
}

DWORD GetLastProxyError() {
  return ::GetLastError();
}

bool ReadRegistryProxy(bool* enabled, std::wstring* server);

const char* LstatusName(LSTATUS status) {
  switch (status) {
    case ERROR_SUCCESS:
      return "ERROR_SUCCESS";
    case ERROR_ACCESS_DENIED:
      return "ERROR_ACCESS_DENIED";
    case ERROR_FILE_NOT_FOUND:
      return "ERROR_FILE_NOT_FOUND";
    default:
      return "LSTATUS";
  }
}

void LogConnectionSettingsSnapshot(const char* tag) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet "
                    L"Settings\\Connections",
                    0, KEY_QUERY_VALUE, &key) != ERROR_SUCCESS) {
    ProxyDebugLog("[%s] Connections key: open failed err=0x%08lX", tag,
                  static_cast<unsigned long>(GetLastProxyError()));
    return;
  }

  DWORD type = 0;
  DWORD size = 0;
  if (RegQueryValueExW(key, L"DefaultConnectionSettings", nullptr, &type, nullptr,
                       &size) != ERROR_SUCCESS ||
      type != REG_BINARY) {
    ProxyDebugLog("[%s] DefaultConnectionSettings: missing or not REG_BINARY", tag);
    RegCloseKey(key);
    return;
  }

  std::vector<BYTE> buffer(size);
  if (RegQueryValueExW(key, L"DefaultConnectionSettings", nullptr, &type, buffer.data(),
                       &size) != ERROR_SUCCESS) {
    ProxyDebugLog("[%s] DefaultConnectionSettings: read failed", tag);
    RegCloseKey(key);
    return;
  }

  const unsigned flags_byte = buffer.size() > 8 ? buffer[8] : 0;
  ProxyDebugLog("[%s] DefaultConnectionSettings size=%lu flags_byte=0x%02X", tag,
                static_cast<unsigned long>(buffer.size()), flags_byte);

  if (buffer.size() > 12) {
    const DWORD proxy_len = buffer[12] | (buffer[13] << 8) | (buffer[14] << 16) |
                            (buffer[15] << 24);
    if (proxy_len > 0 && 16 + proxy_len <= buffer.size()) {
      std::string embedded(reinterpret_cast<const char*>(&buffer[16]), proxy_len);
      ProxyDebugLog("[%s] embedded proxy_server=\"%s\"", tag, embedded.c_str());
    }
  }

  RegCloseKey(key);
}

void AppendLe32(std::vector<BYTE>& out, DWORD value) {
  out.push_back(static_cast<BYTE>(value & 0xFF));
  out.push_back(static_cast<BYTE>((value >> 8) & 0xFF));
  out.push_back(static_cast<BYTE>((value >> 16) & 0xFF));
  out.push_back(static_cast<BYTE>((value >> 24) & 0xFF));
}

std::string WideToAscii(const std::wstring& wide) {
  if (wide.empty()) {
    return std::string();
  }
  const int size =
      ::WideCharToMultiByte(CP_ACP, 0, wide.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) {
    return std::string();
  }
  std::string ascii(static_cast<size_t>(size - 1), '\0');
  ::WideCharToMultiByte(CP_ACP, 0, wide.c_str(), -1, ascii.data(), size, nullptr, nullptr);
  return ascii;
}

void AppendAsciiField(std::vector<BYTE>& buf, const std::string& ascii) {
  AppendLe32(buf, static_cast<DWORD>(ascii.size()));
  buf.insert(buf.end(), ascii.begin(), ascii.end());
}

DWORD ReadConnectionSettingsCounter(HKEY connections_key) {
  DWORD counter = 1;
  DWORD type = 0;
  DWORD size = 0;
  if (RegQueryValueExW(connections_key, L"DefaultConnectionSettings", nullptr, &type,
                       nullptr, &size) != ERROR_SUCCESS ||
      type != REG_BINARY || size < 8) {
    return counter;
  }

  std::vector<BYTE> existing(size);
  if (RegQueryValueExW(connections_key, L"DefaultConnectionSettings", nullptr, &type,
                       existing.data(), &size) != ERROR_SUCCESS) {
    return counter;
  }

  counter = static_cast<DWORD>(existing[4]) | (static_cast<DWORD>(existing[5]) << 8) |
            (static_cast<DWORD>(existing[6]) << 16) |
            (static_cast<DWORD>(existing[7]) << 24);
  return counter + 1;
}

bool WriteConnectionSettingsBlob(bool enabled,
                                 const std::wstring& proxy_server,
                                 const std::wstring& bypass_wide) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kConnectionsKey, 0, KEY_READ | KEY_SET_VALUE,
                    &key) != ERROR_SUCCESS) {
    ProxyDebugLog("WriteConnectionSettingsBlob open failed err=0x%08lX",
                  static_cast<unsigned long>(GetLastProxyError()));
    return false;
  }

  const DWORD counter = ReadConnectionSettingsCounter(key);
  std::vector<BYTE> buf;
  AppendLe32(buf, 0x46);
  AppendLe32(buf, counter);

  if (!enabled) {
    AppendLe32(buf, PROXY_TYPE_DIRECT);
    AppendLe32(buf, 0);
    AppendLe32(buf, 0);
    AppendLe32(buf, 0);
    AppendLe32(buf, 0);
    buf.insert(buf.end(), 31, 0);
  } else {
    const std::string proxy_ascii = WideToAscii(proxy_server);
    const std::string bypass_ascii = WideToAscii(bypass_wide);
    AppendLe32(buf, PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY);
    AppendAsciiField(buf, proxy_ascii);
    AppendAsciiField(buf, bypass_ascii);
    AppendLe32(buf, 0);
    AppendLe32(buf, 0);
    buf.insert(buf.end(), 31, 0);
  }

  const LSTATUS default_status = RegSetValueExW(
      key, L"DefaultConnectionSettings", 0, REG_BINARY, buf.data(),
      static_cast<DWORD>(buf.size()));
  const LSTATUS legacy_status = RegSetValueExW(
      key, L"SavedLegacySettings", 0, REG_BINARY, buf.data(),
      static_cast<DWORD>(buf.size()));
  RegCloseKey(key);

  ProxyDebugLog(
      "WriteConnectionSettingsBlob enabled=%d size=%zu counter=%lu default=%s legacy=%s "
      "proxy_ascii=\"%s\"",
      enabled ? 1 : 0, buf.size(), static_cast<unsigned long>(counter),
      LstatusName(default_status), LstatusName(legacy_status),
      enabled ? WideToAscii(proxy_server).c_str() : "");

  return default_status == ERROR_SUCCESS && legacy_status == ERROR_SUCCESS;
}

void LogProxyPolicySnapshot() {
  DWORD per_user = 1;
  DWORD size = sizeof(per_user);
  HKEY lm = nullptr;
  if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, kInternetSettingsKey, 0, KEY_QUERY_VALUE,
                    &lm) == ERROR_SUCCESS) {
  if (RegQueryValueExW(lm, L"ProxySettingsPerUser", nullptr, nullptr,
                       reinterpret_cast<BYTE*>(&per_user), &size) != ERROR_SUCCESS) {
      per_user = 1;
    }
    RegCloseKey(lm);
  }
  ProxyDebugLog("ProxySettingsPerUser(HKLM)=%lu (0=machine proxy, 1=per-user)",
                static_cast<unsigned long>(per_user));
}

void LogRegistryProxySnapshot(const char* tag) {
  bool enabled = false;
  std::wstring server;
  ReadRegistryProxy(&enabled, &server);

  DWORD auto_detect = 0;
  DWORD auto_detect_size = sizeof(auto_detect);
  HKEY key = nullptr;
  wchar_t pac[512] = {};
  DWORD pac_size = sizeof(pac);

  if (RegOpenKeyExW(HKEY_CURRENT_USER, kInternetSettingsKey, 0, KEY_QUERY_VALUE, &key) ==
      ERROR_SUCCESS) {
    RegQueryValueExW(key, L"AutoDetect", nullptr, nullptr,
                     reinterpret_cast<BYTE*>(&auto_detect), &auto_detect_size);
    RegQueryValueExW(key, L"AutoConfigURL", nullptr, nullptr,
                     reinterpret_cast<BYTE*>(pac), &pac_size);
    RegCloseKey(key);
  }

  ProxyDebugLog(
      "[%s] HKCU ProxyEnable=%d ProxyServer=\"%s\" AutoDetect=%lu AutoConfigURL=\"%s\"",
      tag, enabled ? 1 : 0, WideToUtf8(server).c_str(),
      static_cast<unsigned long>(auto_detect), WideToUtf8(pac).c_str());
}

// Windows Settings and WinINet read DefaultConnectionSettings (REG_BINARY), not
// ProxyServer alone. INTERNET_OPTION_PER_CONNECTION_OPTION rebuilds that blob.
bool SetPerConnectionProxy(bool enabled,
                           const std::wstring& proxy_server,
                           const std::wstring& bypass,
                           DWORD* out_error) {
  if (out_error != nullptr) {
    *out_error = 0;
  }

  ProxyDebugLog(
      "SetPerConnectionProxy enabled=%d server=\"%s\" bypass=\"%s\"",
      enabled ? 1 : 0, WideToUtf8(proxy_server).c_str(), WideToUtf8(bypass).c_str());

  INTERNET_PER_CONN_OPTIONW options[5] = {};
  DWORD option_count = 0;

  const DWORD proxy_flags =
      enabled ? (PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY) : PROXY_TYPE_DIRECT;

  options[option_count].dwOption = INTERNET_PER_CONN_FLAGS;
  options[option_count].Value.dwValue = proxy_flags;
  option_count++;

  if (enabled) {
    if (proxy_server.empty()) {
      if (out_error != nullptr) {
        *out_error = ERROR_INVALID_PARAMETER;
      }
      return false;
    }

    options[option_count].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
    options[option_count].Value.pszValue =
        const_cast<wchar_t*>(proxy_server.c_str());
    option_count++;

    options[option_count].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
    options[option_count].Value.pszValue = const_cast<wchar_t*>(bypass.c_str());
    option_count++;
  }

  INTERNET_PER_CONN_OPTION_LISTW list = {};
  list.dwSize = sizeof(INTERNET_PER_CONN_OPTION_LISTW);
  list.pszConnection = nullptr;
  list.dwOptionCount = option_count;
  list.dwOptionError = 0;
  list.pOptions = options;

  // WinINet may reject per-connection updates until the module is initialized.
  HINTERNET session = InternetOpenW(L"KeqdisProxy", INTERNET_OPEN_TYPE_PRECONFIG,
                                    nullptr, nullptr, 0);
  if (session == nullptr) {
    if (out_error != nullptr) {
      *out_error = GetLastProxyError();
    }
    ProxyDebugLog("SetPerConnectionProxy InternetOpenW failed err=0x%08lX",
                  static_cast<unsigned long>(GetLastProxyError()));
    return false;
  }

  BOOL ok = InternetSetOptionW(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list,
                               sizeof(list));
  DWORD err_global = ok ? 0 : GetLastProxyError();
  if (!ok) {
    ok = InternetSetOptionW(session, INTERNET_OPTION_PER_CONNECTION_OPTION, &list,
                            sizeof(list));
  }
  const DWORD err_session = ok ? 0 : GetLastProxyError();

  InternetCloseHandle(session);

  if (!ok && out_error != nullptr) {
    *out_error = err_session != 0 ? err_session : err_global;
  }

  ProxyDebugLog(
      "SetPerConnectionProxy result=%d global_err=0x%08lX session_err=0x%08lX "
      "option_count=%lu flags=0x%lX",
      ok ? 1 : 0, static_cast<unsigned long>(err_global),
      static_cast<unsigned long>(err_session),
      static_cast<unsigned long>(option_count),
      static_cast<unsigned long>(options[0].Value.dwValue));

  return ok != FALSE;
}

// Simple host:port — Settings UI and DefaultConnectionSettings expect this format.
bool SetRegistryBrowserProxy(const std::wstring& proxy_server) {
  ProxyDebugLog("SetRegistryBrowserProxy server=\"%s\"",
                WideToUtf8(proxy_server).c_str());

  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kInternetSettingsKey, 0, KEY_SET_VALUE, &key) !=
      ERROR_SUCCESS) {
    ProxyDebugLog("SetRegistryBrowserProxy RegOpenKeyEx failed err=0x%08lX",
                  static_cast<unsigned long>(GetLastProxyError()));
    return false;
  }

  const DWORD enable = 1;
  const DWORD auto_detect = 0;
  const LSTATUS enable_status =
      RegSetValueExW(key, L"ProxyEnable", 0, REG_DWORD,
                      reinterpret_cast<const BYTE*>(&enable), sizeof(enable));
  RegSetValueExW(key, L"AutoDetect", 0, REG_DWORD,
                 reinterpret_cast<const BYTE*>(&auto_detect), sizeof(auto_detect));

  const wchar_t empty = L'\0';
  RegSetValueExW(key, L"AutoConfigURL", 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(&empty), sizeof(wchar_t));

  const LSTATUS server_status = RegSetValueExW(
      key, L"ProxyServer", 0, REG_SZ,
      reinterpret_cast<const BYTE*>(proxy_server.c_str()),
      static_cast<DWORD>((proxy_server.size() + 1) * sizeof(wchar_t)));

  const LSTATUS override_status =
      RegSetValueExW(key, L"ProxyOverride", 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(kProxyBypass),
                     static_cast<DWORD>((wcslen(kProxyBypass) + 1) * sizeof(wchar_t)));

  RegCloseKey(key);
  const bool ok = enable_status == ERROR_SUCCESS && server_status == ERROR_SUCCESS &&
                  override_status == ERROR_SUCCESS;
  ProxyDebugLog(
      "SetRegistryBrowserProxy result=%d enable=%s server=%s override=%s",
      ok ? 1 : 0, LstatusName(enable_status), LstatusName(server_status),
      LstatusName(override_status));
  return ok;
}

bool SetRegistryInternetProxy(bool enabled,
                              const std::wstring& registry_proxy_server) {
  ProxyDebugLog("SetRegistryInternetProxy enabled=%d server=\"%s\"",
                enabled ? 1 : 0, WideToUtf8(registry_proxy_server).c_str());

  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kInternetSettingsKey, 0, KEY_SET_VALUE, &key) !=
      ERROR_SUCCESS) {
    ProxyDebugLog("SetRegistryInternetProxy RegOpenKeyEx failed err=0x%08lX",
                  static_cast<unsigned long>(GetLastProxyError()));
    return false;
  }

  const DWORD enable = enabled ? 1 : 0;
  const LSTATUS enable_status =
      RegSetValueExW(key, L"ProxyEnable", 0, REG_DWORD,
                     reinterpret_cast<const BYTE*>(&enable), sizeof(enable));

  const DWORD migrate = 1;
  RegSetValueExW(key, L"MigrateProxy", 0, REG_DWORD,
                 reinterpret_cast<const BYTE*>(&migrate), sizeof(migrate));

  LSTATUS server_status = ERROR_SUCCESS;
  LSTATUS override_status = ERROR_SUCCESS;
  LSTATUS pac_clear_status = ERROR_SUCCESS;

  const wchar_t empty = L'\0';
  pac_clear_status =
      RegSetValueExW(key, L"AutoConfigURL", 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(&empty), sizeof(wchar_t));

  if (enabled) {
    server_status =
        RegSetValueExW(key, L"ProxyServer", 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(registry_proxy_server.c_str()),
                       static_cast<DWORD>((registry_proxy_server.size() + 1) *
                                          sizeof(wchar_t)));
    override_status =
        RegSetValueExW(key, L"ProxyOverride", 0, REG_SZ,
                      reinterpret_cast<const BYTE*>(kProxyBypass),
                      static_cast<DWORD>((wcslen(kProxyBypass) + 1) * sizeof(wchar_t)));
  } else {
    server_status =
        RegSetValueExW(key, L"ProxyServer", 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(&empty), sizeof(wchar_t));
    override_status =
        RegSetValueExW(key, L"ProxyOverride", 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(&empty), sizeof(wchar_t));
  }

  RegCloseKey(key);

  const bool ok = enable_status == ERROR_SUCCESS && server_status == ERROR_SUCCESS &&
                  override_status == ERROR_SUCCESS && pac_clear_status == ERROR_SUCCESS;
  ProxyDebugLog(
      "SetRegistryInternetProxy result=%d enable=%s server=%s override=%s pac=%s",
      ok ? 1 : 0, LstatusName(enable_status), LstatusName(server_status),
      LstatusName(override_status), LstatusName(pac_clear_status));
  return ok;
}

bool SetWinHttpProxy(bool enabled, const std::wstring& winhttp_proxy) {
  WINHTTP_PROXY_INFO proxy_info = {};
  if (enabled && !winhttp_proxy.empty()) {
    proxy_info.dwAccessType = WINHTTP_ACCESS_TYPE_NAMED_PROXY;
    proxy_info.lpszProxy = const_cast<wchar_t*>(winhttp_proxy.c_str());
    proxy_info.lpszProxyBypass = const_cast<wchar_t*>(kProxyBypass);
  } else {
    proxy_info.dwAccessType = WINHTTP_ACCESS_TYPE_NO_PROXY;
    proxy_info.lpszProxy = nullptr;
    proxy_info.lpszProxyBypass = nullptr;
  }
  const BOOL ok = WinHttpSetDefaultProxyConfiguration(&proxy_info);
  ProxyDebugLog("SetWinHttpProxy enabled=%d proxy=\"%s\" result=%d err=0x%08lX",
                enabled ? 1 : 0, WideToUtf8(winhttp_proxy).c_str(), ok ? 1 : 0,
                static_cast<unsigned long>(ok ? 0 : GetLastProxyError()));
  return ok != FALSE;
}

void ImportWinHttpFromIe() {
  STARTUPINFOW si = {};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESHOWWINDOW;
  si.wShowWindow = SW_HIDE;

  PROCESS_INFORMATION pi = {};
  wchar_t cmdline[] = L"netsh.exe winhttp import proxy source=ie";

  if (CreateProcessW(nullptr, cmdline, nullptr, nullptr, FALSE, CREATE_NO_WINDOW,
                    nullptr, nullptr, &si, &pi)) {
    WaitForSingleObject(pi.hProcess, 10000);
    DWORD exit_code = 1;
    GetExitCodeProcess(pi.hProcess, &exit_code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    ProxyDebugLog("ImportWinHttpFromIe exit_code=%lu",
                  static_cast<unsigned long>(exit_code));
  } else {
    ProxyDebugLog("ImportWinHttpFromIe CreateProcess failed err=0x%08lX",
                  static_cast<unsigned long>(GetLastProxyError()));
  }
}

struct ProxyApplyResult {
  bool success = false;
  bool per_connection = false;
  bool connection_blob = false;
  bool registry = false;
  DWORD wininet_error = 0;
  int wininet_probe_http_status = 0;
  int winhttp_probe_http_status = 0;
};

int ProbeHttpViaWinInetPreconfig() {
  HINTERNET internet = InternetOpenW(L"KeqdisProxyProbe", INTERNET_OPEN_TYPE_PRECONFIG,
                                     nullptr, nullptr, 0);
  if (internet == nullptr) {
    ProxyDebugLog("ProbeWinInet: InternetOpen failed err=0x%08lX",
                  static_cast<unsigned long>(GetLastProxyError()));
    return -static_cast<int>(GetLastProxyError());
  }

  HINTERNET url = InternetOpenUrlW(
      internet, L"http://connectivitycheck.gstatic.com/generate_204", nullptr, 0,
      INTERNET_FLAG_RELOAD | INTERNET_FLAG_NO_CACHE_WRITE | INTERNET_FLAG_NO_UI, 0);
  if (url == nullptr) {
    const DWORD err = GetLastProxyError();
    ProxyDebugLog("ProbeWinInet: InternetOpenUrl failed err=0x%08lX",
                  static_cast<unsigned long>(err));
    InternetCloseHandle(internet);
    return -static_cast<int>(err);
  }

  DWORD status = 0;
  DWORD status_size = sizeof(status);
  if (!HttpQueryInfoW(url, HTTP_QUERY_STATUS_CODE | HTTP_QUERY_FLAG_NUMBER, &status,
                      &status_size, nullptr)) {
    status = 0;
  }

  InternetCloseHandle(url);
  InternetCloseHandle(internet);
  ProxyDebugLog("ProbeWinInet: HTTP status=%lu", static_cast<unsigned long>(status));
  return static_cast<int>(status);
}

int ProbeHttpViaWinHttpSystemProxy() {
  HINTERNET session = WinHttpOpen(L"KeqdisProxyProbe/1.0",
                                  WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                                  WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (session == nullptr) {
    session = WinHttpOpen(L"KeqdisProxyProbe/1.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                          WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  }
  if (session == nullptr) {
    ProxyDebugLog("ProbeWinHttp: WinHttpOpen failed err=0x%08lX",
                  static_cast<unsigned long>(GetLastProxyError()));
    return -static_cast<int>(GetLastProxyError());
  }

  HINTERNET connect = WinHttpConnect(session, L"connectivitycheck.gstatic.com",
                                     INTERNET_DEFAULT_HTTP_PORT, 0);
  if (connect == nullptr) {
    const DWORD err = GetLastProxyError();
    ProxyDebugLog("ProbeWinHttp: WinHttpConnect failed err=0x%08lX",
                  static_cast<unsigned long>(err));
    WinHttpCloseHandle(session);
    return -static_cast<int>(err);
  }

  HINTERNET request =
      WinHttpOpenRequest(connect, L"GET", L"/generate_204", nullptr, WINHTTP_NO_REFERER,
                         WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
  if (request == nullptr) {
    const DWORD err = GetLastProxyError();
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    return -static_cast<int>(err);
  }

  BOOL sent = WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                                 WINHTTP_NO_REQUEST_DATA, 0, 0, 0);
  if (!sent || !WinHttpReceiveResponse(request, nullptr)) {
    const DWORD err = GetLastProxyError();
    ProxyDebugLog("ProbeWinHttp: request failed err=0x%08lX",
                  static_cast<unsigned long>(err));
    WinHttpCloseHandle(request);
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    return -static_cast<int>(err);
  }

  DWORD status = 0;
  DWORD status_size = sizeof(status);
  WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                      WINHTTP_HEADER_NAME_BY_INDEX, &status, &status_size,
                      WINHTTP_NO_HEADER_INDEX);

  WinHttpCloseHandle(request);
  WinHttpCloseHandle(connect);
  WinHttpCloseHandle(session);
  ProxyDebugLog("ProbeWinHttp: HTTP status=%lu", static_cast<unsigned long>(status));
  return static_cast<int>(status);
}

ProxyApplyResult ApplySystemProxy(bool enabled,
                                  const std::wstring& settings_ui_proxy,
                                  const std::wstring& browser_proxy,
                                  const std::wstring& winhttp_proxy,
                                  bool run_probes = false) {
  ProxyApplyResult result;
  DWORD wininet_error = 0;

  ProxyDebugLog(
      "======== ApplySystemProxy BEGIN enabled=%d ui=\"%s\" browser=\"%s\" "
      "winhttp=\"%s\" log_file=%s ========",
      enabled ? 1 : 0, WideToUtf8(settings_ui_proxy).c_str(),
      WideToUtf8(browser_proxy).c_str(), WideToUtf8(winhttp_proxy).c_str(),
      ProxyDebugGetLogFilePathUtf8().c_str());
  LogProxyPolicySnapshot();
  LogRegistryProxySnapshot("before");
  LogConnectionSettingsSnapshot("before");

  if (enabled) {
    result.registry = SetRegistryBrowserProxy(settings_ui_proxy);
    if (!result.registry) {
      result.registry = SetRegistryInternetProxy(true, settings_ui_proxy);
    }
  } else {
    result.registry = SetRegistryInternetProxy(false, L"");
  }

  result.connection_blob =
      WriteConnectionSettingsBlob(enabled, settings_ui_proxy, kProxyBypass);

  result.per_connection = SetPerConnectionProxy(
      enabled, settings_ui_proxy, kPerConnBypass, &wininet_error);
  if (enabled && !result.per_connection) {
    ProxyDebugLog("ApplySystemProxy per_conn retry with registry bypass list");
    result.per_connection =
        SetPerConnectionProxy(enabled, settings_ui_proxy, kProxyBypass, &wininet_error);
  }
  result.wininet_error = wininet_error;

  SetWinHttpProxy(enabled, settings_ui_proxy);

  if (enabled) {
    ImportWinHttpFromIe();
  }

  NotifyProxySettingsChanged();

  LogRegistryProxySnapshot("after");
  LogConnectionSettingsSnapshot("after");

  if (enabled && run_probes) {
    result.wininet_probe_http_status = ProbeHttpViaWinInetPreconfig();
    result.winhttp_probe_http_status = ProbeHttpViaWinHttpSystemProxy();
    result.success = result.registry && result.connection_blob;
  } else if (enabled) {
    result.success = result.registry && result.connection_blob;
  } else {
    result.success = result.registry || result.connection_blob || result.per_connection;
  }

  ProxyDebugLog(
      "======== ApplySystemProxy END success=%d registry=%d blob=%d per_conn=%d "
      "wininet_err=0x%08lX wininet_probe=%d winhttp_probe=%d ========",
      result.success ? 1 : 0, result.registry ? 1 : 0, result.connection_blob ? 1 : 0,
      result.per_connection ? 1 : 0, static_cast<unsigned long>(result.wininet_error),
      result.wininet_probe_http_status, result.winhttp_probe_http_status);

  return result;
}

bool ReadRegistryProxy(bool* enabled, std::wstring* server) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kInternetSettingsKey, 0, KEY_QUERY_VALUE,
                    &key) != ERROR_SUCCESS) {
    return false;
  }

  DWORD enable = 0;
  DWORD enable_size = sizeof(enable);
  if (RegQueryValueExW(key, L"ProxyEnable", nullptr, nullptr,
                       reinterpret_cast<BYTE*>(&enable), &enable_size) == ERROR_SUCCESS) {
    *enabled = enable != 0;
  }

  wchar_t buffer[512] = {};
  DWORD buffer_size = sizeof(buffer);
  if (RegQueryValueExW(key, L"ProxyServer", nullptr, nullptr,
                       reinterpret_cast<BYTE*>(buffer), &buffer_size) == ERROR_SUCCESS) {
    *server = buffer;
  }

  RegCloseKey(key);
  return true;
}

bool IsProcessElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }
  TOKEN_ELEVATION elevation = {};
  DWORD size = sizeof(elevation);
  const BOOL ok =
      GetTokenInformation(token, TokenElevation, &elevation, sizeof(elevation), &size);
  CloseHandle(token);
  return ok && elevation.TokenIsElevated;
}

bool SetLaunchAtStartupEnabled(bool enable) {
  const wchar_t kRunKey[] =
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
  const wchar_t kValueName[] = L"KeqDroid";

  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0,
                      KEY_SET_VALUE | KEY_QUERY_VALUE,
                      &key) != ERROR_SUCCESS) {
    return false;
  }

  if (!enable) {
    ::RegDeleteValueW(key, kValueName);
    ::RegCloseKey(key);
    return true;
  }

  wchar_t exe_path[MAX_PATH] = {};
  const DWORD path_len = ::GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  if (path_len == 0 || path_len >= MAX_PATH) {
    ::RegCloseKey(key);
    return false;
  }

  std::wstring command = L"\"";
  command += exe_path;
  command += L"\" --autostart";
  const LSTATUS status = ::RegSetValueExW(
      key, kValueName, 0, REG_SZ,
      reinterpret_cast<const BYTE*>(command.c_str()),
      static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  ::RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

bool IsLaunchAtStartupEnabled() {
  const wchar_t kRunKey[] =
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
  const wchar_t kValueName[] = L"KeqDroid";

  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_QUERY_VALUE,
                      &key) != ERROR_SUCCESS) {
    return false;
  }

  wchar_t buffer[1024] = {};
  DWORD buffer_size = sizeof(buffer);
  DWORD type = 0;
  const LSTATUS status = ::RegQueryValueExW(
      key, kValueName, nullptr, &type,
      reinterpret_cast<LPBYTE>(buffer), &buffer_size);
  ::RegCloseKey(key);
  return status == ERROR_SUCCESS && type == REG_SZ;
}

bool RestartAsAdministrator() {
  wchar_t exe_path[MAX_PATH] = {};
  if (::GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) {
    return false;
  }

  std::wstring exe_dir = exe_path;
  const auto slash = exe_dir.find_last_of(L"\\/");
  if (slash != std::wstring::npos) {
    exe_dir.resize(slash);
  }

  std::wstring params;
  bool has_admin_restart = false;
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv != nullptr) {
    for (int i = 1; i < argc; ++i) {
      if (_wcsicmp(argv[i], L"--admin-restart") == 0) {
        has_admin_restart = true;
        continue;
      }
      if (!params.empty()) {
        params += L' ';
      }
      params += L'"';
      params += argv[i];
      params += L'"';
    }
    ::LocalFree(argv);
  }
  if (!has_admin_restart) {
    if (!params.empty()) {
      params += L' ';
    }
    params += L"--admin-restart";
  }

  // Let the elevated process acquire the single-instance mutex immediately.
  RunnerReleaseSingleInstanceMutex();

  SHELLEXECUTEINFOW exec_info = {};
  exec_info.cbSize = sizeof(exec_info);
  exec_info.fMask = SEE_MASK_NOASYNC;
  exec_info.lpVerb = L"runas";
  exec_info.lpFile = exe_path;
  exec_info.lpParameters = params.empty() ? L"--admin-restart" : params.c_str();
  exec_info.lpDirectory = exe_dir.c_str();
  exec_info.nShow = SW_SHOWDEFAULT;

  if (!::ShellExecuteExW(&exec_info)) {
    return false;
  }
  return exec_info.hInstApp > reinterpret_cast<HINSTANCE>(32);
}

// ───────── Platform-thread task marshaling ─────────
// Heavy proxy operations (registry writes, WinINET broadcasts, `netsh winhttp
// import`) block whichever thread runs them — sometimes for several seconds.
// They must NOT run on the Flutter platform thread, which is also the UI thread
// on Windows, or the whole window freezes. We run them on a worker std::thread
// and marshal the MethodResult completion back to the platform thread through a
// message-only window pumped by the main Win32 message loop.
constexpr UINT kRunOnPlatformThreadMsg = WM_APP + 0x71;

std::mutex g_task_mutex;
std::queue<std::function<void()>> g_task_queue;
HWND g_marshal_window = nullptr;

void DrainPlatformThreadTasks() {
  for (;;) {
    std::function<void()> task;
    {
      std::lock_guard<std::mutex> lock(g_task_mutex);
      if (g_task_queue.empty()) break;
      task = std::move(g_task_queue.front());
      g_task_queue.pop();
    }
    if (task) task();
  }
}

LRESULT CALLBACK MarshalWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                LPARAM lparam) {
  if (msg == kRunOnPlatformThreadMsg) {
    DrainPlatformThreadTasks();
    return 0;
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

// Must be called once on the platform thread (during channel registration).
void EnsureMarshalWindow() {
  if (g_marshal_window != nullptr) return;
  WNDCLASSW wc = {};
  wc.lpfnWndProc = MarshalWndProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = L"KeqdisProxyMarshalWindow";
  RegisterClassW(&wc);
  g_marshal_window =
      CreateWindowExW(0, wc.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                      nullptr, wc.hInstance, nullptr);
}

// Thread-safe: enqueue a callback to run on the platform thread.
void PostToPlatformThread(std::function<void()> task) {
  {
    std::lock_guard<std::mutex> lock(g_task_mutex);
    g_task_queue.push(std::move(task));
  }
  if (g_marshal_window != nullptr) {
    PostMessageW(g_marshal_window, kRunOnPlatformThreadMsg, 0, 0);
  }
}

}  // namespace

void RegisterKeqdisTunnelChannel(flutter::FlutterEngine* engine) {
  if (engine == nullptr) {
    return;
  }

  KeqdisInitCoreProcessGuard();

  // Created on the platform thread so worker threads can marshal results back.
  EnsureMarshalWindow();

  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), kChannel,
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "appendProxyDebugLog") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
            auto it = args->find(flutter::EncodableValue("message"));
            if (it != args->end()) {
              const auto& msg = std::get<std::string>(it->second);
              ProxyDebugLog("%s", msg.c_str());
            }
          }
          result->Success();
          return;
        }

        if (call.method_name() == "getProxyDebugLogs") {
          int max_lines = 400;
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
            auto it = args->find(flutter::EncodableValue("maxLines"));
            if (it != args->end()) {
              max_lines = static_cast<int>(std::get<int32_t>(it->second));
            }
          }
          result->Success(flutter::EncodableValue(
              ProxyDebugGetLogs(static_cast<std::size_t>(max_lines))));
          return;
        }

        if (call.method_name() == "getProxyDebugLogPath") {
          result->Success(
              flutter::EncodableValue(ProxyDebugGetLogFilePathUtf8()));
          return;
        }

        if (call.method_name() == "clearProxyDebugLogs") {
          ProxyDebugClear();
          result->Success();
          return;
        }

        if (call.method_name() == "setSystemProxy") {
          ProxyDebugLog("--- setSystemProxy called from Dart ---");

          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (!args) {
            result->Error("INVALID_ARGS", "Expected map arguments");
            return;
          }
          bool enabled = false;
          auto enabled_it = args->find(flutter::EncodableValue("enabled"));
          if (enabled_it != args->end()) {
            enabled = std::get<bool>(enabled_it->second);
          }

          std::string host = "127.0.0.1";
          auto host_it = args->find(flutter::EncodableValue("host"));
          if (host_it != args->end()) {
            host = std::get<std::string>(host_it->second);
          }

          int socks_port = 2080;
          auto port_it = args->find(flutter::EncodableValue("socksPort"));
          if (port_it != args->end()) {
            socks_port = static_cast<int>(std::get<int32_t>(port_it->second));
          }

          int http_port = socks_port;
          auto http_it = args->find(flutter::EncodableValue("httpPort"));
          if (http_it != args->end()) {
            http_port = static_cast<int>(std::get<int32_t>(http_it->second));
          }

          bool run_probes = false;
          auto probe_it = args->find(flutter::EncodableValue("probe"));
          if (probe_it != args->end()) {
            run_probes = std::get<bool>(probe_it->second);
          }

          std::wstring settings_ui_proxy;
          std::wstring browser_proxy;
          std::wstring winhttp_proxy;
          if (enabled) {
            const std::string proxy_utf8 =
                host + ":" + std::to_string(http_port);
            settings_ui_proxy = Utf8ToWide(proxy_utf8);
            browser_proxy = settings_ui_proxy;
            winhttp_proxy = settings_ui_proxy;
          }

          ProxyDebugLog(
              "setSystemProxy args enabled=%d host=%s socks=%d http=%d "
              "(SOCKS is not written to system proxy)",
              enabled ? 1 : 0, host.c_str(), socks_port, http_port);

          // ApplySystemProxy blocks for seconds (netsh, WinINET broadcasts).
          // Run it off the platform thread so the UI never freezes; the result
          // is completed back on the platform thread via PostToPlatformThread.
          std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>
              shared_result(result.release());

          std::thread([enabled, run_probes, settings_ui_proxy, browser_proxy,
                       winhttp_proxy, shared_result]() {
            const ProxyApplyResult apply = ApplySystemProxy(
                enabled, settings_ui_proxy, browser_proxy, winhttp_proxy,
                run_probes);

            bool applied = false;
            std::wstring applied_server;
            if (apply.success) {
              ReadRegistryProxy(&applied, &applied_server);
            }

            PostToPlatformThread([apply, applied, applied_server,
                                  shared_result]() {
              if (!apply.success) {
                char message[512];
                snprintf(
                    message, sizeof(message),
                    "Failed to set system proxy (registry=%d blob=%d "
                    "per_conn=%d wininet_err=0x%08lX). Log: %s",
                    apply.registry ? 1 : 0, apply.connection_blob ? 1 : 0,
                    apply.per_connection ? 1 : 0,
                    static_cast<unsigned long>(apply.wininet_error),
                    ProxyDebugGetLogFilePathUtf8().c_str());
                flutter::EncodableMap details;
                details[flutter::EncodableValue("logFile")] =
                    flutter::EncodableValue(ProxyDebugGetLogFilePathUtf8());
                details[flutter::EncodableValue("logs")] =
                    flutter::EncodableValue(ProxyDebugGetLogs(120));
                details[flutter::EncodableValue("registryOk")] =
                    flutter::EncodableValue(apply.registry);
                details[flutter::EncodableValue("connectionBlobOk")] =
                    flutter::EncodableValue(apply.connection_blob);
                details[flutter::EncodableValue("perConnectionOk")] =
                    flutter::EncodableValue(apply.per_connection);
                details[flutter::EncodableValue("wininetError")] =
                    flutter::EncodableValue(
                        static_cast<int32_t>(apply.wininet_error));
                shared_result->Error("PROXY_FAILED", message,
                                     flutter::EncodableValue(details));
                return;
              }

              flutter::EncodableMap response;
              response[flutter::EncodableValue("registryEnabled")] =
                  flutter::EncodableValue(applied);
              response[flutter::EncodableValue("registryServer")] =
                  flutter::EncodableValue(WideToUtf8(applied_server));
              response[flutter::EncodableValue("logFile")] =
                  flutter::EncodableValue(ProxyDebugGetLogFilePathUtf8());
              response[flutter::EncodableValue("logs")] =
                  flutter::EncodableValue(ProxyDebugGetLogs(80));
              response[flutter::EncodableValue("winInetProbeStatus")] =
                  flutter::EncodableValue(apply.wininet_probe_http_status);
              response[flutter::EncodableValue("winHttpProbeStatus")] =
                  flutter::EncodableValue(apply.winhttp_probe_http_status);
              shared_result->Success(flutter::EncodableValue(response));
            });
          }).detach();
          return;
        }

        if (call.method_name() == "testSystemProxyHttp") {
          flutter::EncodableMap response;
          response[flutter::EncodableValue("winInet")] =
              flutter::EncodableValue(ProbeHttpViaWinInetPreconfig());
          response[flutter::EncodableValue("winHttp")] =
              flutter::EncodableValue(ProbeHttpViaWinHttpSystemProxy());
          result->Success(flutter::EncodableValue(response));
          return;
        }

        if (call.method_name() == "getSystemProxy") {
          bool enabled = false;
          std::wstring server;
          ReadRegistryProxy(&enabled, &server);
          flutter::EncodableMap response;
          response[flutter::EncodableValue("enabled")] =
              flutter::EncodableValue(enabled);
          response[flutter::EncodableValue("server")] =
              flutter::EncodableValue(WideToUtf8(server));
          result->Success(flutter::EncodableValue(response));
          return;
        }

        if (call.method_name() == "requestTunnelPermission") {
          result->Success(flutter::EncodableValue(IsProcessElevated()));
          return;
        }

        if (call.method_name() == "setMinimizeToTray") {
          bool enabled = true;
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
            auto it = args->find(flutter::EncodableValue("enabled"));
            if (it != args->end()) {
              enabled = std::get<bool>(it->second);
            }
          }
          WindowsTraySetMinimizeToTray(enabled);
          result->Success();
          return;
        }

        if (call.method_name() == "getMinimizeToTray") {
          result->Success(
              flutter::EncodableValue(WindowsTrayGetMinimizeToTray()));
          return;
        }

        if (call.method_name() == "setLaunchAtStartup") {
          bool enabled = false;
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
            auto it = args->find(flutter::EncodableValue("enabled"));
            if (it != args->end()) {
              enabled = std::get<bool>(it->second);
            }
          }
          if (!SetLaunchAtStartupEnabled(enabled)) {
            result->Error("AUTOSTART_FAILED",
                          "Failed to update Windows startup registry");
            return;
          }
          result->Success();
          return;
        }

        if (call.method_name() == "isLaunchAtStartup") {
          result->Success(
              flutter::EncodableValue(IsLaunchAtStartupEnabled()));
          return;
        }

        if (call.method_name() == "restartAsAdministrator") {
          if (!RestartAsAdministrator()) {
            result->Error("ELEVATION_FAILED",
                          "Failed to restart as administrator");
            return;
          }
          result->Success();
          PostToPlatformThread([]() { ::PostQuitMessage(0); });
          return;
        }

        if (call.method_name() == "initCoreProcessGuard") {
          KeqdisInitCoreProcessGuard();
          result->Success();
          return;
        }

        if (call.method_name() == "attachCoreProcess") {
          int32_t pid = 0;
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
            auto it = args->find(flutter::EncodableValue("pid"));
            if (it != args->end()) {
              pid = static_cast<int32_t>(std::get<int32_t>(it->second));
            }
          }
          KeqdisAttachCoreProcess(static_cast<DWORD>(pid));
          result->Success();
          return;
        }

        if (call.method_name() == "registerSessionCoreProcesses") {
          int32_t xray_pid = 0;
          int32_t singbox_pid = 0;
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
            auto xray_it = args->find(flutter::EncodableValue("xrayPid"));
            if (xray_it != args->end()) {
              xray_pid = static_cast<int32_t>(std::get<int32_t>(xray_it->second));
            }
            auto sing_it = args->find(flutter::EncodableValue("singboxPid"));
            if (sing_it != args->end()) {
              singbox_pid = static_cast<int32_t>(std::get<int32_t>(sing_it->second));
            }
          }
          KeqdisRegisterSessionCoreProcesses(static_cast<DWORD>(xray_pid),
                                             static_cast<DWORD>(singbox_pid));
          result->Success();
          return;
        }

        if (call.method_name() == "clearSessionCoreProcesses") {
          KeqdisClearSessionCoreProcesses();
          result->Success();
          return;
        }

        if (call.method_name() == "listProcesses") {
          bool include_system = false;
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
            auto it = args->find(flutter::EncodableValue("includeSystem"));
            if (it != args->end()) {
              include_system = std::get<bool>(it->second);
            }
          }
          result->Success(flutter::EncodableValue(ListWindowsApps(include_system)));
          return;
        }

        if (call.method_name() == "getAppIcon") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (!args) {
            result->Error("INVALID_ARGS", "Expected map arguments");
            return;
          }
          std::string path_utf8;
          auto path_it = args->find(flutter::EncodableValue("path"));
          if (path_it != args->end()) {
            path_utf8 = std::get<std::string>(path_it->second);
          }
          if (path_utf8.empty()) {
            result->Success(flutter::EncodableValue(std::string()));
            return;
          }
          const std::string icon = GetWindowsAppIconBase64(Utf8ToWide(path_utf8));
          result->Success(flutter::EncodableValue(icon));
          return;
        }

        if (call.method_name() == "getLaunchAction") {
          result->Success(flutter::EncodableValue());
          return;
        }

        if (call.method_name() == "clearLaunchAction") {
          result->Success();
          return;
        }

        if (call.method_name() == "getAndroidId") {
          result->Success(flutter::EncodableValue(std::string("")));
          return;
        }

        if (call.method_name() == "getDeviceModel") {
          result->Success(
              flutter::EncodableValue(std::string("Windows PC")));
          return;
        }

        if (call.method_name() == "getTrafficStats") {
          uint64_t in_octets = 0;
          uint64_t out_octets = 0;
          const bool ok = ReadSessionTrafficCounters(&in_octets, &out_octets);
          flutter::EncodableMap response;
          response[flutter::EncodableValue("ok")] =
              flutter::EncodableValue(ok);
          response[flutter::EncodableValue("inOctets")] =
              flutter::EncodableValue(static_cast<int64_t>(in_octets));
          response[flutter::EncodableValue("outOctets")] =
              flutter::EncodableValue(static_cast<int64_t>(out_octets));
          result->Success(flutter::EncodableValue(response));
          return;
        }

        if (call.method_name() == "getStatus") {
          flutter::EncodableMap status;
          status[flutter::EncodableValue("status")] =
              flutter::EncodableValue(std::string("disconnected"));
          result->Success(flutter::EncodableValue(status));
          return;
        }

        if (call.method_name() == "stopVpn") {
          // Disabling the proxy also broadcasts WM_SETTINGCHANGE (up to 10s),
          // so run it off the platform thread to keep the UI responsive.
          std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>
              shared_result(result.release());
          std::thread([shared_result]() {
            ApplySystemProxy(false, L"", L"", L"");
            PostToPlatformThread(
                [shared_result]() { shared_result->Success(); });
          }).detach();
          return;
        }

        result->NotImplemented();
      });

  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      s_channel;
  s_channel = std::move(channel);
}
