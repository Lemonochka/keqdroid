#include "windows_tun_service_client.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <aclapi.h>
#include <bcrypt.h>
#include <sddl.h>
#include <shellapi.h>

#include <algorithm>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "tunnel_channel_handler.h"

namespace {

constexpr wchar_t kServiceName[] = L"KeqdroidTun";
constexpr wchar_t kPipeName[] = L"\\\\.\\pipe\\keqdroid-tun";
constexpr uint32_t kMaxFrame = 64u << 20;

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;

using Result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>;

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  const int n = ::MultiByteToWideChar(CP_UTF8, 0, s.data(),
                                      static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(static_cast<size_t>(n), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                        out.data(), n);
  return out;
}

std::string WideToUtf8(const std::wstring& s) {
  if (s.empty()) return std::string();
  const int n = ::WideCharToMultiByte(CP_UTF8, 0, s.data(),
                                      static_cast<int>(s.size()), nullptr, 0,
                                      nullptr, nullptr);
  std::string out(static_cast<size_t>(n), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                        out.data(), n, nullptr, nullptr);
  return out;
}

std::wstring ExeDir() {
  wchar_t buf[MAX_PATH * 2] = {};
  const DWORD n = ::GetModuleFileNameW(nullptr, buf, MAX_PATH * 2);
  std::wstring path(buf, n);
  const size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? path : path.substr(0, slash);
}

std::string FileSha256(const std::wstring& path) {
  HANDLE f = ::CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (f == INVALID_HANDLE_VALUE) return std::string();
  BCRYPT_ALG_HANDLE alg = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  std::string out;
  if (BCRYPT_SUCCESS(::BCryptOpenAlgorithmProvider(
          &alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0)) &&
      BCRYPT_SUCCESS(::BCryptCreateHash(alg, &hash, nullptr, 0, nullptr, 0, 0))) {
    std::vector<uint8_t> buf(1 << 20);
    DWORD got = 0;
    bool ok = true;
    while (::ReadFile(f, buf.data(), static_cast<DWORD>(buf.size()), &got,
                      nullptr) &&
           got > 0) {
      if (!BCRYPT_SUCCESS(::BCryptHashData(hash, buf.data(), got, 0))) {
        ok = false;
        break;
      }
    }
    uint8_t digest[32] = {};
    if (ok && BCRYPT_SUCCESS(::BCryptFinishHash(hash, digest, sizeof(digest), 0))) {
      static const char kHex[] = "0123456789abcdef";
      for (const uint8_t b : digest) {
        out.push_back(kHex[b >> 4]);
        out.push_back(kHex[b & 15]);
      }
    }
  }
  if (hash) ::BCryptDestroyHash(hash);
  if (alg) ::BCryptCloseAlgorithmProvider(alg, 0);
  ::CloseHandle(f);
  return out;
}

std::wstring CurrentUserSid() {
  HANDLE token = nullptr;
  if (!::OpenProcessToken(::GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return std::wstring();
  }
  DWORD size = 0;
  ::GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  std::vector<uint8_t> buf(size);
  std::wstring out;
  if (size > 0 &&
      ::GetTokenInformation(token, TokenUser, buf.data(), size, &size)) {
    LPWSTR text = nullptr;
    if (::ConvertSidToStringSidW(
            reinterpret_cast<TOKEN_USER*>(buf.data())->User.Sid, &text)) {
      out = text;
      ::LocalFree(text);
    }
  }
  ::CloseHandle(token);
  return out;
}

class ClientPipe {
 public:
  ClientPipe() {
    read_event_ = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
    write_event_ = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
    cancel_event_ = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
  }
  ~ClientPipe() {
    Close();
    ::CloseHandle(read_event_);
    ::CloseHandle(write_event_);
    ::CloseHandle(cancel_event_);
  }

  // служба стоит с ручным запуском: поднимаем её сами, права на запуск у пользователя есть
  bool Open(std::string* error) {
    for (int attempt = 0; attempt < 50; ++attempt) {
      handle_ = ::CreateFileW(kPipeName, GENERIC_READ | GENERIC_WRITE, 0,
                              nullptr, OPEN_EXISTING, FILE_FLAG_OVERLAPPED,
                              nullptr);
      if (handle_ != INVALID_HANDLE_VALUE) {
        if (ServerIsPrivileged(handle_)) return true;
        ::CloseHandle(handle_);
        handle_ = INVALID_HANDLE_VALUE;
        *error = "the TUN service pipe is held by another program";
        return false;
      }
      const DWORD err = ::GetLastError();
      if (err == ERROR_PIPE_BUSY) {
        ::WaitNamedPipeW(kPipeName, 200);
        continue;
      }
      if (err == ERROR_FILE_NOT_FOUND && attempt == 0 && !StartServiceNow(error)) {
        return false;
      }
      ::Sleep(100);
    }
    *error = "the keqdroid TUN service does not answer";
    return false;
  }

  void Close() {
    std::lock_guard<std::mutex> lock(close_mutex_);
    if (handle_ != INVALID_HANDLE_VALUE) {
      ::SetEvent(cancel_event_);
      ::CancelIoEx(handle_, nullptr);
      ::CloseHandle(handle_);
      handle_ = INVALID_HANDLE_VALUE;
    }
  }

  bool Write(const std::string& frame) {
    std::lock_guard<std::mutex> lock(write_mutex_);
    const uint32_t len = static_cast<uint32_t>(frame.size());
    uint8_t header[4] = {static_cast<uint8_t>(len & 0xFF),
                         static_cast<uint8_t>((len >> 8) & 0xFF),
                         static_cast<uint8_t>((len >> 16) & 0xFF),
                         static_cast<uint8_t>((len >> 24) & 0xFF)};
    return Transfer(header, 4, true) &&
           Transfer(reinterpret_cast<uint8_t*>(const_cast<char*>(frame.data())),
                    len, true);
  }

  bool Read(std::string* frame) {
    uint8_t header[4] = {};
    if (!Transfer(header, 4, false)) return false;
    const uint32_t len = static_cast<uint32_t>(header[0]) |
                         (static_cast<uint32_t>(header[1]) << 8) |
                         (static_cast<uint32_t>(header[2]) << 16) |
                         (static_cast<uint32_t>(header[3]) << 24);
    if (len > kMaxFrame) return false;
    frame->assign(len, '\0');
    return len == 0 ||
           Transfer(reinterpret_cast<uint8_t*>(frame->data()), len, false);
  }

 private:
  // имя канала может занять и чужой процесс: конфиг с паролями сервера уходит только каналу SYSTEM или администраторов
  static bool ServerIsPrivileged(HANDLE pipe) {
    PSID owner = nullptr;
    PSECURITY_DESCRIPTOR sd = nullptr;
    if (::GetSecurityInfo(pipe, SE_KERNEL_OBJECT, OWNER_SECURITY_INFORMATION,
                          &owner, nullptr, nullptr, nullptr,
                          &sd) != ERROR_SUCCESS) {
      return false;
    }
    const bool ok = ::IsWellKnownSid(owner, WinLocalSystemSid) ||
                    ::IsWellKnownSid(owner, WinBuiltinAdministratorsSid);
    ::LocalFree(sd);
    return ok;
  }

  static bool StartServiceNow(std::string* error) {
    SC_HANDLE scm = ::OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
    if (!scm) {
      *error = "could not reach the service manager";
      return false;
    }
    SC_HANDLE service = ::OpenServiceW(scm, kServiceName, SERVICE_START);
    bool ok = false;
    if (!service) {
      *error = "the keqdroid TUN service is not installed";
    } else {
      ok = ::StartServiceW(service, 0, nullptr) ||
           ::GetLastError() == ERROR_SERVICE_ALREADY_RUNNING;
      if (!ok) *error = "could not start the keqdroid TUN service";
      ::CloseServiceHandle(service);
    }
    ::CloseServiceHandle(scm);
    return ok;
  }

  bool Transfer(uint8_t* buf, uint32_t size, bool write) {
    uint32_t done = 0;
    HANDLE event = write ? write_event_ : read_event_;
    while (done < size) {
      HANDLE h = handle_;
      if (h == INVALID_HANDLE_VALUE) return false;
      OVERLAPPED ov = {};
      ov.hEvent = event;
      ::ResetEvent(event);
      DWORD moved = 0;
      const BOOL immediate =
          write ? ::WriteFile(h, buf + done, size - done, &moved, &ov)
                : ::ReadFile(h, buf + done, size - done, &moved, &ov);
      if (!immediate) {
        if (::GetLastError() != ERROR_IO_PENDING) return false;
        HANDLE waits[2] = {event, cancel_event_};
        const DWORD w = ::WaitForMultipleObjects(2, waits, FALSE, INFINITE);
        if (w != WAIT_OBJECT_0) {
          ::CancelIoEx(h, &ov);
          ::GetOverlappedResult(h, &ov, &moved, TRUE);
          return false;
        }
        if (!::GetOverlappedResult(h, &ov, &moved, FALSE)) return false;
      }
      if (moved == 0) return false;
      done += moved;
    }
    return true;
  }

  HANDLE handle_ = INVALID_HANDLE_VALUE;
  HANDLE read_event_ = nullptr;
  HANDLE write_event_ = nullptr;
  HANDLE cancel_event_ = nullptr;
  std::mutex write_mutex_;
  std::mutex close_mutex_;
};

std::vector<std::string> SplitLines(const std::string& s) {
  std::vector<std::string> parts;
  size_t start = 0;
  while (true) {
    const size_t nl = s.find('\n', start);
    if (nl == std::string::npos) {
      parts.push_back(s.substr(start));
      return parts;
    }
    parts.push_back(s.substr(start, nl - start));
    start = nl + 1;
  }
}

// одна сессия ядра за раз, как у самой службы
std::mutex g_session_mutex;
std::shared_ptr<ClientPipe> g_session;

void Dispatch(const std::string& method, flutter::EncodableMap args) {
  KeqdroidPostToPlatformThread([method, args]() {
    if (g_channel) {
      g_channel->InvokeMethod(method,
                              std::make_unique<flutter::EncodableValue>(args));
    }
  });
}

void Reply(Result result, flutter::EncodableValue value) {
  KeqdroidPostToPlatformThread([result, value]() { result->Success(value); });
}

void ReplyError(Result result, const std::string& code,
                const std::string& message) {
  KeqdroidPostToPlatformThread(
      [result, code, message]() { result->Error(code, message); });
}

const std::string* StringArg(const flutter::EncodableMap& args,
                             const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) return nullptr;
  return std::get_if<std::string>(&it->second);
}

void Status(Result result) {
  std::thread([result]() {
    flutter::EncodableMap out;
    SC_HANDLE scm = ::OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
    SC_HANDLE service =
        scm ? ::OpenServiceW(scm, kServiceName, SERVICE_QUERY_STATUS) : nullptr;
    const bool installed = service != nullptr;
    if (service) ::CloseServiceHandle(service);
    if (scm) ::CloseServiceHandle(scm);
    out[flutter::EncodableValue("installed")] = flutter::EncodableValue(installed);
    bool trusted = false;
    if (installed) {
      ClientPipe pipe;
      std::string error;
      std::string frame;
      if (pipe.Open(&error) && pipe.Write("version") && pipe.Read(&frame)) {
        const auto parts = SplitLines(frame);
        if (parts.size() == 5 && parts[0] == "version") {
          const std::wstring dir = ExeDir();
          // ядра, которые приложение отдаст службе, она обязана узнать: иначе после обновления её надо переставить
          trusted = parts[1] == "1" &&
                    parts[2] == FileSha256(dir + L"\\xray.exe") &&
                    parts[3] == FileSha256(dir + L"\\mihomo.exe") &&
                    parts[4] == FileSha256(dir + L"\\wintun.dll");
        }
      } else if (!error.empty()) {
        out[flutter::EncodableValue("error")] = flutter::EncodableValue(error);
      }
    }
    out[flutter::EncodableValue("trusted")] = flutter::EncodableValue(trusted);
    Reply(result, flutter::EncodableValue(out));
  }).detach();
}

void Install(Result result) {
  std::thread([result]() {
    const std::wstring sid = CurrentUserSid();
    const std::wstring exe = ExeDir() + L"\\keqdroid-tun.exe";
    if (sid.empty() || ::GetFileAttributesW(exe.c_str()) == INVALID_FILE_ATTRIBUTES) {
      ReplyError(result, "NO_SERVICE_EXE", "keqdroid-tun.exe is missing next to the app");
      return;
    }
    // SID свой, а не того администратора, чей пароль введут в окне UAC: службой пользоваться этому пользователю
    const std::wstring params = L"install " + sid;
    SHELLEXECUTEINFOW info = {};
    info.cbSize = sizeof(info);
    info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC;
    // приложение, запущенное старой задачей планировщика, уже с правами: ставит службу без окна UAC
    info.lpVerb = KeqdroidProcessIsAdmin() ? L"open" : L"runas";
    info.lpFile = exe.c_str();
    info.lpParameters = params.c_str();
    info.nShow = SW_HIDE;
    if (!::ShellExecuteExW(&info)) {
      const DWORD err = ::GetLastError();
      flutter::EncodableMap out;
      out[flutter::EncodableValue("ok")] = flutter::EncodableValue(false);
      out[flutter::EncodableValue("cancelled")] =
          flutter::EncodableValue(err == ERROR_CANCELLED);
      Reply(result, flutter::EncodableValue(out));
      return;
    }
    DWORD code = 1;
    if (info.hProcess) {
      ::WaitForSingleObject(info.hProcess, 60000);
      ::GetExitCodeProcess(info.hProcess, &code);
      ::CloseHandle(info.hProcess);
    }
    flutter::EncodableMap out;
    out[flutter::EncodableValue("ok")] = flutter::EncodableValue(code == 0);
    out[flutter::EncodableValue("code")] =
        flutter::EncodableValue(static_cast<int>(code));
    Reply(result, flutter::EncodableValue(out));
  }).detach();
}

void StartCore(const flutter::EncodableMap& args, Result result) {
  const std::string* kind = StringArg(args, "kind");
  const std::string* config = StringArg(args, "config");
  const std::string* geo_dir = StringArg(args, "geoDir");
  if (!kind || !config) {
    result->Error("BAD_ARGS", "kind and config are required");
    return;
  }
  std::vector<std::string> adapters;
  const auto it = args.find(flutter::EncodableValue("adapterIds"));
  if (it != args.end()) {
    if (const auto* list = std::get_if<flutter::EncodableList>(&it->second)) {
      for (const auto& v : *list) {
        if (const auto* s = std::get_if<std::string>(&v)) adapters.push_back(*s);
      }
    }
  }
  const std::string start = "start\n" + *kind + "\n" + WideToUtf8(ExeDir()) +
                            "\n" + (geo_dir ? *geo_dir : std::string()) + "\n" +
                            *config;
  std::thread([result, start, adapters]() {
    auto pipe = std::make_shared<ClientPipe>();
    std::string error;
    if (!pipe->Open(&error)) {
      ReplyError(result, "SERVICE_UNAVAILABLE", error);
      return;
    }
    std::string frame;
    flutter::EncodableList removed;
    if (!adapters.empty()) {
      std::string request = "removeAdapters";
      for (const auto& id : adapters) request += "\n" + id;
      if (pipe->Write(request) && pipe->Read(&frame)) {
        const auto parts = SplitLines(frame);
        for (size_t i = 1; i < parts.size(); ++i) {
          removed.push_back(flutter::EncodableValue(parts[i]));
        }
      }
    }
    if (!pipe->Write(start) || !pipe->Read(&frame)) {
      ReplyError(result, "SERVICE_UNAVAILABLE",
                 "the keqdroid TUN service closed the connection");
      return;
    }
    const auto head = SplitLines(frame);
    if (head.empty() || head[0] != "ok" || head.size() < 2) {
      const size_t nl = frame.find('\n');
      ReplyError(result, "CORE_REFUSED",
                 nl == std::string::npos ? frame : frame.substr(nl + 1));
      return;
    }
    {
      std::lock_guard<std::mutex> lock(g_session_mutex);
      g_session = pipe;
    }
    flutter::EncodableMap out;
    out[flutter::EncodableValue("pid")] =
        flutter::EncodableValue(std::atoi(head[1].c_str()));
    out[flutter::EncodableValue("removedAdapters")] =
        flutter::EncodableValue(removed);
    Reply(result, flutter::EncodableValue(out));

    int exit_code = -1;
    while (pipe->Read(&frame)) {
      const size_t nl = frame.find('\n');
      const std::string kind_of = frame.substr(0, nl);
      const std::string body =
          nl == std::string::npos ? std::string() : frame.substr(nl + 1);
      if (kind_of == "out") {
        flutter::EncodableMap line;
        line[flutter::EncodableValue("line")] = flutter::EncodableValue(body);
        Dispatch("onOutput", line);
      } else if (kind_of == "exit") {
        exit_code = std::atoi(body.c_str());
        break;
      }
    }
    {
      std::lock_guard<std::mutex> lock(g_session_mutex);
      if (g_session == pipe) g_session.reset();
    }
    pipe->Close();
    flutter::EncodableMap done;
    done[flutter::EncodableValue("code")] = flutter::EncodableValue(exit_code);
    Dispatch("onExit", done);
  }).detach();
}

// мягко: служба закрывает ядру stdin, xray возвращает адаптер и маршруты сам; жёстко: рвём канал, и служба убивает ядро
void StopCore(bool graceful) {
  std::shared_ptr<ClientPipe> pipe;
  {
    std::lock_guard<std::mutex> lock(g_session_mutex);
    pipe = g_session;
  }
  if (!pipe) return;
  if (graceful) {
    std::thread([pipe]() { pipe->Write("stop"); }).detach();
  } else {
    pipe->Close();
  }
}

}  // namespace

void RegisterKeqdroidTunServiceChannel(flutter::FlutterEngine* engine) {
  if (engine == nullptr) return;
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "keqdroid/tun_service",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        Result shared(result.release());
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        const std::string& method = call.method_name();
        if (method == "status") {
          Status(shared);
        } else if (method == "install") {
          Install(shared);
        } else if (method == "startCore" && args) {
          StartCore(*args, shared);
        } else if (method == "stopCore") {
          bool graceful = true;
          if (args) {
            const auto it = args->find(flutter::EncodableValue("graceful"));
            if (it != args->end()) {
              if (const auto* b = std::get_if<bool>(&it->second)) graceful = *b;
            }
          }
          StopCore(graceful);
          shared->Success();
        } else {
          shared->NotImplemented();
        }
      });
}
