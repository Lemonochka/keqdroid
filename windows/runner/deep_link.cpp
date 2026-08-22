#include "deep_link.h"

#include <shellapi.h>

#include <cstring>

namespace {

// Tagged into WM_COPYDATA so a stray copy-data message from another
// application is never mistaken for a link.
constexpr ULONG_PTR kCopyDataId = 0x4B455144;  // 'KEQD'

// Schemes a subscription panel may put on its "add to client" button. Both are
// an external contract — they are typed into panel settings and cannot be
// renamed, see lib/utils/subscription_deep_link.dart.
const wchar_t* const kSchemes[] = {L"keqdroid", L"keqdis"};

std::string WideToUtf8(const std::wstring& text) {
  if (text.empty()) {
    return std::string();
  }
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, text.c_str(),
                                         static_cast<int>(text.size()), nullptr,
                                         0, nullptr, nullptr);
  if (size <= 0) {
    return std::string();
  }
  std::string out(static_cast<size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                        out.data(), size, nullptr, nullptr);
  return out;
}

std::wstring ExecutablePath() {
  wchar_t path[MAX_PATH] = {};
  const DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return std::wstring();
  }
  return std::wstring(path, length);
}

std::wstring ReadDefaultValue(const std::wstring& subkey) {
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, subkey.c_str(), 0, KEY_QUERY_VALUE,
                      &key) != ERROR_SUCCESS) {
    return std::wstring();
  }
  wchar_t buffer[1024] = {};
  DWORD size = sizeof(buffer) - sizeof(wchar_t);
  DWORD type = 0;
  const LSTATUS status =
      ::RegQueryValueExW(key, nullptr, nullptr, &type,
                         reinterpret_cast<LPBYTE>(buffer), &size);
  ::RegCloseKey(key);
  if (status != ERROR_SUCCESS || type != REG_SZ) {
    return std::wstring();
  }
  return std::wstring(buffer);
}

bool WriteValue(const std::wstring& subkey, const wchar_t* name,
                const std::wstring& value) {
  HKEY key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, subkey.c_str(), 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr, &key,
                        nullptr) != ERROR_SUCCESS) {
    return false;
  }
  const LSTATUS status = ::RegSetValueExW(
      key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  ::RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

void RegisterScheme(const wchar_t* scheme, const std::wstring& exe_path) {
  const std::wstring base = std::wstring(L"Software\\Classes\\") + scheme;
  const std::wstring command_key = base + L"\\shell\\open\\command";
  const std::wstring command = L"\"" + exe_path + L"\" \"%1\"";

  // Startup path: skip the writes when the registration already points here.
  if (ReadDefaultValue(command_key) == command) {
    return;
  }

  WriteValue(base, nullptr, std::wstring(L"URL:KeqDroid link"));
  // Presence of this (empty) value is what makes Windows treat the key as a
  // protocol handler rather than a file association.
  WriteValue(base, L"URL Protocol", std::wstring());
  WriteValue(base + L"\\DefaultIcon", nullptr, exe_path + L",0");
  WriteValue(command_key, nullptr, command);
}

}  // namespace

void KeqdroidRegisterUrlProtocols() {
  const std::wstring exe_path = ExecutablePath();
  if (exe_path.empty()) {
    return;
  }
  for (const wchar_t* scheme : kSchemes) {
    RegisterScheme(scheme, exe_path);
  }
}

std::string KeqdroidDeepLinkFromCommandLine() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::string();
  }
  std::string url;
  for (int i = 1; i < argc && url.empty(); ++i) {
    const std::wstring arg = argv[i];
    if (arg.rfind(L"-", 0) == 0) {
      continue;  // --autostart, --admin-restart
    }
    // Any scheme, not just ours: a vless:// link dropped onto the executable
    // imports exactly like the one shared into the app on Android. Dart is the
    // one that validates it.
    if (arg.find(L"://") == std::wstring::npos) {
      continue;
    }
    url = WideToUtf8(arg);
  }
  ::LocalFree(argv);
  return url;
}

bool KeqdroidForwardDeepLinkToRunningInstance(HWND target,
                                              const std::string& url) {
  if (target == nullptr || url.empty()) {
    return false;
  }
  COPYDATASTRUCT payload = {};
  payload.dwData = kCopyDataId;
  payload.cbData = static_cast<DWORD>(url.size() + 1);
  payload.lpData = const_cast<char*>(url.c_str());

  // SendMessage and not Post: the payload lives on our stack and this process
  // exits right after. The timeout keeps a wedged instance from hanging us.
  DWORD_PTR unused = 0;
  return ::SendMessageTimeoutW(target, WM_COPYDATA, 0,
                               reinterpret_cast<LPARAM>(&payload),
                               SMTO_ABORTIFHUNG, 5000, &unused) != 0;
}

void KeqdroidAllowDeepLinkMessages(HWND hwnd) {
  if (hwnd == nullptr) {
    return;
  }
  ::ChangeWindowMessageFilterEx(hwnd, WM_COPYDATA, MSGFLT_ALLOW, nullptr);
}

bool KeqdroidDeepLinkFromCopyData(LPARAM lparam, std::string* url) {
  const auto* payload = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
  if (payload == nullptr || payload->dwData != kCopyDataId ||
      payload->lpData == nullptr || payload->cbData == 0) {
    return false;
  }
  const char* bytes = static_cast<const char*>(payload->lpData);
  const size_t length = ::strnlen(bytes, payload->cbData);
  url->assign(bytes, length);
  return !url->empty();
}
