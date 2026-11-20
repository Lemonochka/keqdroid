// keqdroid-tun.exe: служба SYSTEM, через которую приложение без прав администратора поднимает ядро в режиме TUN.
// модель как у FlClash services/helper и хелпера Linux: запускаются только ядра из сборки (sha256 вшиты при сборке),
// из своей копии в каталоге, куда пишут только SYSTEM и администраторы
#include <windows.h>

#include <aclapi.h>
#include <bcrypt.h>
#include <sddl.h>
#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "core_hashes.h"
#include "runner/windows_tun_adapters.h"
#include "config_check.h"

namespace {

constexpr wchar_t kServiceName[] = L"KeqdroidTun";
constexpr wchar_t kDisplayName[] = L"keqdroid TUN";
constexpr wchar_t kPipeName[] = L"\\\\.\\pipe\\keqdroid-tun";
constexpr wchar_t kParamsKey[] =
    L"SYSTEM\\CurrentControlSet\\Services\\KeqdroidTun\\Parameters";
constexpr DWORD kMaxFrame = 64u << 20;
constexpr uint64_t kMaxCoreBytes = 256ull << 20;
constexpr uint64_t kMaxGeoBytes = 256ull << 20;
// приложение сверяет это число и суммы ядер со своими и при расхождении просит обновить службу
constexpr int kProtocolVersion = 1;

// SYSTEM и администраторы, без наследования от Program Files: читать скопированное пользователь не должен
constexpr wchar_t kPrivateDirSddl[] = L"D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)";

// Обновлятор mihomo (POST /upgrade) переименовывает работающий exe и кладёт на его место скачанный. Ядру от имени
// SYSTEM в каталоге ядер нельзя создавать, переписывать и удалять: запрет стоит на SID SYSTEM, служба снимает его
// только на свою запись
constexpr wchar_t kLockedBinSddl[] =
    L"D:P(D;OICI;0x10046;;;SY)(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)";

SERVICE_STATUS_HANDLE g_status_handle = nullptr;
SERVICE_STATUS g_status = {};
HANDLE g_stop_event = nullptr;

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

std::wstring KnownFolder(REFKNOWNFOLDERID id, const wchar_t* fallback) {
  PWSTR path = nullptr;
  std::wstring out = fallback;
  if (SUCCEEDED(::SHGetKnownFolderPath(id, 0, nullptr, &path)) && path) {
    out = path;
  }
  ::CoTaskMemFree(path);
  return out;
}

std::wstring InstallDir() {
  return KnownFolder(FOLDERID_ProgramFiles, L"C:\\Program Files") +
         L"\\keqdroid TUN";
}

std::wstring RunDir() { return InstallDir() + L"\\run"; }

std::wstring ServiceExePath() { return InstallDir() + L"\\keqdroid-tun.exe"; }

std::wstring SelfPath() {
  std::wstring buf(MAX_PATH, L'\0');
  while (true) {
    const DWORD n = ::GetModuleFileNameW(nullptr, buf.data(),
                                         static_cast<DWORD>(buf.size()));
    if (n == 0) return std::wstring();
    if (n < buf.size()) {
      buf.resize(n);
      return buf;
    }
    buf.resize(buf.size() * 2);
  }
}

bool EnsurePrivateDir(const std::wstring& path) {
  PSECURITY_DESCRIPTOR sd = nullptr;
  if (!::ConvertStringSecurityDescriptorToSecurityDescriptorW(
          kPrivateDirSddl, SDDL_REVISION_1, &sd, nullptr)) {
    return false;
  }
  SECURITY_ATTRIBUTES sa = {sizeof(sa), sd, FALSE};
  bool ok = ::CreateDirectoryW(path.c_str(), &sa) != FALSE;
  if (!ok && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // каталог мог остаться от прошлой установки с чужими правами: ставим свои
    PACL dacl = nullptr;
    BOOL present = FALSE;
    BOOL defaulted = FALSE;
    ::GetSecurityDescriptorDacl(sd, &present, &dacl, &defaulted);
    ok = ::SetNamedSecurityInfoW(
             const_cast<wchar_t*>(path.c_str()), SE_FILE_OBJECT,
             DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
             nullptr, nullptr, dacl, nullptr) == ERROR_SUCCESS;
  }
  ::LocalFree(sd);
  return ok;
}

bool LockDir(const std::wstring& path) {
  PSECURITY_DESCRIPTOR sd = nullptr;
  if (!::ConvertStringSecurityDescriptorToSecurityDescriptorW(
          kLockedBinSddl, SDDL_REVISION_1, &sd, nullptr)) {
    return false;
  }
  PACL dacl = nullptr;
  BOOL present = FALSE;
  BOOL defaulted = FALSE;
  ::GetSecurityDescriptorDacl(sd, &present, &dacl, &defaulted);
  const bool ok =
      ::SetNamedSecurityInfoW(
          const_cast<wchar_t*>(path.c_str()), SE_FILE_OBJECT,
          DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
          nullptr, nullptr, dacl, nullptr) == ERROR_SUCCESS;
  ::LocalFree(sd);
  return ok;
}

std::string Sha256Hex(const uint8_t* data, size_t size) {
  BCRYPT_ALG_HANDLE alg = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  uint8_t digest[32] = {};
  std::string out;
  if (!BCRYPT_SUCCESS(::BCryptOpenAlgorithmProvider(
          &alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0))) {
    return out;
  }
  bool ok = BCRYPT_SUCCESS(
      ::BCryptCreateHash(alg, &hash, nullptr, 0, nullptr, 0, 0));
  size_t done = 0;
  while (ok && done < size) {
    const ULONG chunk =
        static_cast<ULONG>(std::min<size_t>(size - done, 1u << 30));
    ok = BCRYPT_SUCCESS(::BCryptHashData(
        hash, const_cast<PUCHAR>(data + done), chunk, 0));
    done += chunk;
  }
  ok = ok && BCRYPT_SUCCESS(::BCryptFinishHash(hash, digest, sizeof(digest), 0));
  if (hash) ::BCryptDestroyHash(hash);
  ::BCryptCloseAlgorithmProvider(alg, 0);
  if (!ok) return out;
  static const char kHex[] = "0123456789abcdef";
  for (const uint8_t b : digest) {
    out.push_back(kHex[b >> 4]);
    out.push_back(kHex[b & 15]);
  }
  return out;
}

bool ReadWholeFile(const std::wstring& path, std::vector<uint8_t>* out,
                   uint64_t limit) {
  HANDLE f = ::CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                           nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                           nullptr);
  if (f == INVALID_HANDLE_VALUE) return false;
  LARGE_INTEGER size = {};
  bool ok = ::GetFileSizeEx(f, &size) != FALSE && size.QuadPart >= 0 &&
            static_cast<uint64_t>(size.QuadPart) <= limit;
  if (ok) {
    out->resize(static_cast<size_t>(size.QuadPart));
    size_t done = 0;
    while (done < out->size()) {
      const DWORD chunk =
          static_cast<DWORD>(std::min<size_t>(out->size() - done, 1u << 20));
      DWORD got = 0;
      if (!::ReadFile(f, out->data() + done, chunk, &got, nullptr) ||
          got == 0) {
        ok = false;
        break;
      }
      done += got;
    }
  }
  ::CloseHandle(f);
  return ok;
}

bool WriteWholeFile(const std::wstring& path, const uint8_t* data,
                    size_t size) {
  HANDLE f = ::CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                           CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (f == INVALID_HANDLE_VALUE) return false;
  size_t done = 0;
  bool ok = true;
  while (done < size) {
    const DWORD chunk =
        static_cast<DWORD>(std::min<size_t>(size - done, 1u << 20));
    DWORD wrote = 0;
    if (!::WriteFile(f, data + done, chunk, &wrote, nullptr) || wrote == 0) {
      ok = false;
      break;
    }
    done += wrote;
  }
  ::CloseHandle(f);
  return ok;
}

// старый exe ядро держит открытым, пока работает: переписываем, только если байты другие
bool PlaceFile(const std::wstring& path, const std::vector<uint8_t>& bytes) {
  std::vector<uint8_t> current;
  if (ReadWholeFile(path, &current, kMaxCoreBytes) && current == bytes) {
    return true;
  }
  return WriteWholeFile(path, bytes.data(), bytes.size());
}

std::wstring AllowedUserSid() {
  wchar_t buf[256] = {};
  DWORD size = sizeof(buf) - sizeof(wchar_t);
  DWORD type = 0;
  if (::RegGetValueW(HKEY_LOCAL_MACHINE, kParamsKey, L"AllowedUser",
                     RRF_RT_REG_SZ, &type, buf, &size) != ERROR_SUCCESS) {
    return std::wstring();
  }
  return buf;
}

class Pipe {
 public:
  explicit Pipe(HANDLE h) : h_(h) {
    read_event_ = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
    write_event_ = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
  }
  ~Pipe() {
    if (read_event_) ::CloseHandle(read_event_);
    if (write_event_) ::CloseHandle(write_event_);
  }

  // false: клиент ушёл или служба останавливается
  bool Read(std::string* frame) {
    uint8_t header[4] = {};
    if (!ReadExact(header, 4)) return false;
    const DWORD len = static_cast<DWORD>(header[0]) |
                      (static_cast<DWORD>(header[1]) << 8) |
                      (static_cast<DWORD>(header[2]) << 16) |
                      (static_cast<DWORD>(header[3]) << 24);
    if (len > kMaxFrame) return false;
    frame->assign(len, '\0');
    return len == 0 || ReadExact(reinterpret_cast<uint8_t*>(frame->data()), len);
  }

  bool Write(const std::string& frame) {
    std::lock_guard<std::mutex> lock(write_mutex_);
    const DWORD len = static_cast<DWORD>(frame.size());
    uint8_t header[4] = {static_cast<uint8_t>(len & 0xFF),
                         static_cast<uint8_t>((len >> 8) & 0xFF),
                         static_cast<uint8_t>((len >> 16) & 0xFF),
                         static_cast<uint8_t>((len >> 24) & 0xFF)};
    return WriteExact(header, 4) &&
           WriteExact(reinterpret_cast<const uint8_t*>(frame.data()), len);
  }

 private:
  bool ReadExact(uint8_t* buf, DWORD size) {
    DWORD done = 0;
    while (done < size) {
      OVERLAPPED ov = {};
      ov.hEvent = read_event_;
      ::ResetEvent(read_event_);
      DWORD got = 0;
      if (!::ReadFile(h_, buf + done, size - done, &got, &ov)) {
        if (::GetLastError() != ERROR_IO_PENDING) return false;
        HANDLE waits[2] = {read_event_, g_stop_event};
        const DWORD w = ::WaitForMultipleObjects(2, waits, FALSE, INFINITE);
        if (w != WAIT_OBJECT_0) {
          ::CancelIoEx(h_, &ov);
          ::GetOverlappedResult(h_, &ov, &got, TRUE);
          return false;
        }
        if (!::GetOverlappedResult(h_, &ov, &got, FALSE)) return false;
      }
      if (got == 0) return false;
      done += got;
    }
    return true;
  }

  bool WriteExact(const uint8_t* buf, DWORD size) {
    DWORD done = 0;
    while (done < size) {
      OVERLAPPED ov = {};
      ov.hEvent = write_event_;
      ::ResetEvent(write_event_);
      DWORD wrote = 0;
      if (!::WriteFile(h_, buf + done, size - done, &wrote, &ov)) {
        if (::GetLastError() != ERROR_IO_PENDING) return false;
        if (!::GetOverlappedResult(h_, &ov, &wrote, TRUE)) return false;
      }
      if (wrote == 0) return false;
      done += wrote;
    }
    return true;
  }

  HANDLE h_;
  HANDLE read_event_ = nullptr;
  HANDLE write_event_ = nullptr;
  std::mutex write_mutex_;
};

std::vector<std::string> SplitLines(const std::string& s, size_t max_parts) {
  std::vector<std::string> parts;
  size_t start = 0;
  while (parts.size() + 1 < max_parts) {
    const size_t nl = s.find('\n', start);
    if (nl == std::string::npos) break;
    parts.push_back(s.substr(start, nl - start));
    start = nl + 1;
  }
  parts.push_back(s.substr(start));
  return parts;
}

struct CoreRun {
  HANDLE process = nullptr;
  HANDLE job = nullptr;
  HANDLE stdin_write = nullptr;
  std::thread output;
  std::thread waiter;
};

void ReleaseCore(CoreRun* run) {
  if (run->job) {
    ::TerminateJobObject(run->job, 1);
  }
  if (run->stdin_write) {
    ::CloseHandle(run->stdin_write);
    run->stdin_write = nullptr;
  }
  if (run->output.joinable()) run->output.join();
  if (run->waiter.joinable()) run->waiter.join();
  if (run->process) {
    ::CloseHandle(run->process);
    run->process = nullptr;
  }
  if (run->job) {
    ::CloseHandle(run->job);
    run->job = nullptr;
  }
}

// xray выходит сам по EOF на stdin (tool/patches/xray-desktop-stdin-stop.patch) и возвращает адаптер и маршруты,
// mihomo сигналов на Windows не слушает, его снимаем сразу
void StopCore(CoreRun* run, bool graceful) {
  if (run->process == nullptr) return;
  if (graceful && run->stdin_write) {
    ::CloseHandle(run->stdin_write);
    run->stdin_write = nullptr;
    if (::WaitForSingleObject(run->process, 5000) == WAIT_OBJECT_0) return;
  }
  ::TerminateJobObject(run->job, 1);
}

std::vector<wchar_t> CoreEnvironment(const std::wstring& home, bool xray) {
  std::wstring env;
  auto add = [&env](const std::wstring& line) {
    env += line;
    env.push_back(L'\0');
  };
  wchar_t sys_root[MAX_PATH] = {};
  ::GetEnvironmentVariableW(L"SystemRoot", sys_root, MAX_PATH);
  const std::wstring root = sys_root[0] ? sys_root : L"C:\\Windows";
  // окружение с нуля: SAFE_PATHS и SKIP_SAFE_PATH_CHECK у mihomo открыли бы ему пути вне дома
  add(L"SystemRoot=" + root);
  add(L"windir=" + root);
  add(L"PATH=" + root + L"\\System32;" + root);
  add(L"TEMP=" + home);
  add(L"TMP=" + home);
  if (xray) {
    add(L"XRAY_LOCATION_ASSET=" + home);
    add(L"KEQ_STOP_ON_STDIN_EOF=1");
  }
  env.push_back(L'\0');
  return std::vector<wchar_t>(env.begin(), env.end());
}

struct StartRequest {
  std::string kind;
  std::wstring app_dir;
  std::wstring geo_dir;
  std::string config;
};

bool ParseStart(const std::string& payload, StartRequest* req) {
  const auto parts = SplitLines(payload, 5);
  if (parts.size() != 5 || parts[0] != "start") return false;
  req->kind = parts[1];
  req->app_dir = Utf8ToWide(parts[2]);
  req->geo_dir = Utf8ToWide(parts[3]);
  req->config = parts[4];
  return (req->kind == "xray" || req->kind == "mihomo") &&
         !req->app_dir.empty();
}

std::string StartCore(HANDLE pipe_handle, Pipe* pipe, const StartRequest& req,
                      CoreRun* run) {
  const bool xray = req.kind == "xray";
  const wchar_t* core_name = xray ? L"xray.exe" : L"mihomo.exe";
  const char* want = xray ? KEQ_XRAY_SHA256 : KEQ_MIHOMO_SHA256;
  if (want[0] == '\0' || KEQ_WINTUN_SHA256[0] == '\0') {
    return "this service was built without the cores";
  }
  if (xray ? !XrayConfigIsSafe(req.config) : !MihomoConfigIsSafe(req.config)) {
    return "the config has sections the service does not run as SYSTEM: "
           "log files, env, geodata, api, scripts, webhooks, key files or "
           "system clock changes";
  }

  // файлы приложения читаем правами того, кто попросил: путь от него, и прочесть чужое ему не дадим
  std::vector<uint8_t> core;
  std::vector<uint8_t> wintun;
  std::vector<uint8_t> geoip;
  std::vector<uint8_t> geosite;
  if (!::ImpersonateNamedPipeClient(pipe_handle)) {
    return "could not act as the app user";
  }
  const bool read_core =
      ReadWholeFile(req.app_dir + L"\\" + core_name, &core, kMaxCoreBytes);
  const bool read_wintun =
      ReadWholeFile(req.app_dir + L"\\wintun.dll", &wintun, kMaxCoreBytes);
  const std::wstring geo = req.geo_dir.empty() ? req.app_dir : req.geo_dir;
  const bool read_geoip =
      ReadWholeFile(geo + L"\\geoip.dat", &geoip, kMaxGeoBytes);
  const bool read_geosite =
      ReadWholeFile(geo + L"\\geosite.dat", &geosite, kMaxGeoBytes);
  ::RevertToSelf();
  if (!read_core) return "could not read the core next to the app";
  if (!read_wintun) return "could not read wintun.dll next to the app";

  if (Sha256Hex(core.data(), core.size()) != want) {
    return "the core next to the app is not the one this service trusts, "
           "update the service";
  }
  if (Sha256Hex(wintun.data(), wintun.size()) != KEQ_WINTUN_SHA256) {
    return "wintun.dll next to the app is not the one this service trusts";
  }

  const std::wstring run_dir = RunDir();
  const std::wstring bin = run_dir + L"\\bin";
  const std::wstring home = run_dir + (xray ? L"\\xray" : L"\\mihomo");
  if (!EnsurePrivateDir(run_dir) || !EnsurePrivateDir(bin) ||
      !EnsurePrivateDir(home)) {
    return "could not prepare the service directory";
  }
  const std::wstring core_path = bin + L"\\" + core_name;
  if (!PlaceFile(core_path, core) ||
      !PlaceFile(bin + L"\\wintun.dll", wintun)) {
    return "could not place the core into the service directory";
  }
  if (!LockDir(bin)) return "could not lock the core directory";
  if (read_geoip) PlaceFile(home + L"\\geoip.dat", geoip);
  if (read_geosite) PlaceFile(home + L"\\geosite.dat", geosite);

  const std::wstring config_path =
      home + (xray ? L"\\session.json" : L"\\session.yaml");
  if (!WriteWholeFile(config_path,
                      reinterpret_cast<const uint8_t*>(req.config.data()),
                      req.config.size())) {
    return "could not write the core config";
  }

  SECURITY_ATTRIBUTES inherit = {sizeof(inherit), nullptr, TRUE};
  HANDLE out_read = nullptr;
  HANDLE out_write = nullptr;
  HANDLE in_read = nullptr;
  HANDLE in_write = nullptr;
  if (!::CreatePipe(&out_read, &out_write, &inherit, 0)) {
    return "could not create the output pipe";
  }
  if (!::CreatePipe(&in_read, &in_write, &inherit, 0)) {
    ::CloseHandle(out_read);
    ::CloseHandle(out_write);
    return "could not create the input pipe";
  }
  ::SetHandleInformation(out_read, HANDLE_FLAG_INHERIT, 0);
  ::SetHandleInformation(in_write, HANDLE_FLAG_INHERIT, 0);

  std::wstring cmd = L"\"" + core_path + L"\"";
  if (xray) {
    cmd += L" run -c \"" + config_path + L"\"";
  } else {
    cmd += L" -d \"" + home + L"\" -f \"" + config_path + L"\"";
  }
  std::vector<wchar_t> cmd_buf(cmd.begin(), cmd.end());
  cmd_buf.push_back(L'\0');
  std::vector<wchar_t> env = CoreEnvironment(home, xray);

  STARTUPINFOW si = {};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdInput = in_read;
  si.hStdOutput = out_write;
  si.hStdError = out_write;
  PROCESS_INFORMATION pi = {};
  // wintun.dll ядро грузит по имени, то есть из своего каталога
  const BOOL created = ::CreateProcessW(
      core_path.c_str(), cmd_buf.data(), nullptr, nullptr, TRUE,
      CREATE_NO_WINDOW | CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT,
      env.data(), bin.c_str(), &si, &pi);
  const DWORD create_error = created ? 0 : ::GetLastError();
  ::CloseHandle(out_write);
  ::CloseHandle(in_read);
  if (!created) {
    ::CloseHandle(out_read);
    ::CloseHandle(in_write);
    return "could not start the core (error " +
           std::to_string(create_error) + ")";
  }

  run->job = ::CreateJobObjectW(nullptr, nullptr);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!run->job ||
      !::SetInformationJobObject(run->job, JobObjectExtendedLimitInformation,
                                 &limits, sizeof(limits)) ||
      !::AssignProcessToJobObject(run->job, pi.hProcess)) {
    ::TerminateProcess(pi.hProcess, 1);
    ::CloseHandle(pi.hThread);
    ::CloseHandle(pi.hProcess);
    ::CloseHandle(out_read);
    ::CloseHandle(in_write);
    if (run->job) {
      ::CloseHandle(run->job);
      run->job = nullptr;
    }
    return "could not put the core into a job";
  }
  ::ResumeThread(pi.hThread);
  ::CloseHandle(pi.hThread);
  run->process = pi.hProcess;
  run->stdin_write = in_write;

  pipe->Write("ok\n" + std::to_string(pi.dwProcessId));

  run->output = std::thread([pipe, out_read]() {
    std::string pending;
    char buf[4096];
    DWORD got = 0;
    while (::ReadFile(out_read, buf, sizeof(buf), &got, nullptr) && got > 0) {
      pending.append(buf, got);
      size_t nl = 0;
      while ((nl = pending.find('\n')) != std::string::npos) {
        std::string line = pending.substr(0, nl);
        if (!line.empty() && line.back() == '\r') line.pop_back();
        pipe->Write("out\n" + line);
        pending.erase(0, nl + 1);
      }
    }
    if (!pending.empty()) pipe->Write("out\n" + pending);
    ::CloseHandle(out_read);
  });
  HANDLE process = pi.hProcess;
  run->waiter = std::thread([pipe, process]() {
    ::WaitForSingleObject(process, INFINITE);
    DWORD code = 1;
    ::GetExitCodeProcess(process, &code);
    pipe->Write("exit\n" + std::to_string(static_cast<int>(code)));
  });
  return std::string();
}

bool ClientIsAllowed(HANDLE pipe, PSID allowed) {
  ULONG pid = 0;
  if (!::GetNamedPipeClientProcessId(pipe, &pid)) return false;
  HANDLE process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return false;
  HANDLE token = nullptr;
  bool ok = false;
  if (::OpenProcessToken(process, TOKEN_QUERY, &token)) {
    DWORD size = 0;
    ::GetTokenInformation(token, TokenUser, nullptr, 0, &size);
    std::vector<uint8_t> buf(size);
    if (size > 0 && ::GetTokenInformation(token, TokenUser, buf.data(), size,
                                          &size)) {
      const auto* user = reinterpret_cast<TOKEN_USER*>(buf.data());
      ok = ::EqualSid(user->User.Sid, allowed) != FALSE;
    }
    ::CloseHandle(token);
  }
  ::CloseHandle(process);
  return ok;
}

std::vector<std::wstring> AdapterIds(const std::string& payload) {
  std::vector<std::wstring> ids;
  const auto parts = SplitLines(payload, 64);
  for (size_t i = 1; i < parts.size(); ++i) {
    // только адаптеры wintun: служба не удаляет по просьбе другие устройства
    if (parts[i].rfind("SWD\\Wintun\\{", 0) == 0) {
      ids.push_back(Utf8ToWide(parts[i]));
    }
  }
  return ids;
}

// ядро одно на всю службу, подключений может быть несколько: приложение спрашивает версию и при работающем ядре
std::atomic<bool> g_core_busy{false};
std::atomic<int> g_clients{0};

void ServeClient(HANDLE handle) {
  Pipe pipe(handle);
  bool owns_core = false;
  CoreRun run;
  std::string frame;
  while (pipe.Read(&frame)) {
    if (frame == "version") {
      pipe.Write("version\n" + std::to_string(kProtocolVersion) + "\n" +
                 KEQ_XRAY_SHA256 + "\n" + KEQ_MIHOMO_SHA256 + "\n" +
                 KEQ_WINTUN_SHA256);
    } else if (frame.rfind("removeAdapters", 0) == 0) {
      const auto removed = KeqdroidRemoveStaleWintunAdapters(AdapterIds(frame));
      std::string reply = "removed";
      for (const auto& id : removed) reply += "\n" + WideToUtf8(id);
      pipe.Write(reply);
    } else if (frame.rfind("start\n", 0) == 0) {
      StartRequest req;
      if (!ParseStart(frame, &req)) {
        pipe.Write("error\nbad start request");
      } else if (owns_core || g_core_busy.exchange(true)) {
        pipe.Write("error\nthe core is already running");
      } else {
        owns_core = true;
        const std::string error = StartCore(handle, &pipe, req, &run);
        if (!error.empty()) {
          pipe.Write("error\n" + error);
          ReleaseCore(&run);
          owns_core = false;
          g_core_busy = false;
        }
      }
    } else if (frame == "stop") {
      StopCore(&run, true);
    } else {
      pipe.Write("error\nunknown command");
    }
  }
  // приложение закрылось или упало, и ядро уходит вместе с ним, как было с job у приложения;
  // канал рвём до ожидания потоков, иначе поток вывода висел бы на записи в него
  StopCore(&run, false);
  ::DisconnectNamedPipe(handle);
  ReleaseCore(&run);
  if (owns_core) g_core_busy = false;
}

void PipeLoop() {
  const std::wstring sid_string = AllowedUserSid();
  PSID allowed = nullptr;
  if (sid_string.empty() ||
      !::ConvertStringSidToSidW(sid_string.c_str(), &allowed)) {
    return;
  }
  const std::wstring sddl =
      L"D:P(A;;GA;;;SY)(A;;GRGW;;;" + sid_string + L")";
  PSECURITY_DESCRIPTOR sd = nullptr;
  if (!::ConvertStringSecurityDescriptorToSecurityDescriptorW(
          sddl.c_str(), SDDL_REVISION_1, &sd, nullptr)) {
    ::LocalFree(allowed);
    return;
  }
  SECURITY_ATTRIBUTES sa = {sizeof(sa), sd, FALSE};
  HANDLE connect_event = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
  bool first = true;
  while (::WaitForSingleObject(g_stop_event, 0) != WAIT_OBJECT_0) {
    HANDLE pipe = ::CreateNamedPipeW(
        kPipeName,
        PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED |
            (first ? FILE_FLAG_FIRST_PIPE_INSTANCE : 0),
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT |
            PIPE_REJECT_REMOTE_CLIENTS,
        PIPE_UNLIMITED_INSTANCES, 1 << 16, 1 << 16, 0, &sa);
    if (pipe == INVALID_HANDLE_VALUE) {
      if (::WaitForSingleObject(g_stop_event, 1000) == WAIT_OBJECT_0) break;
      continue;
    }
    first = false;
    OVERLAPPED ov = {};
    ov.hEvent = connect_event;
    ::ResetEvent(connect_event);
    bool connected = ::ConnectNamedPipe(pipe, &ov) != FALSE;
    if (!connected) {
      const DWORD err = ::GetLastError();
      if (err == ERROR_PIPE_CONNECTED) {
        connected = true;
      } else if (err == ERROR_IO_PENDING) {
        HANDLE waits[2] = {connect_event, g_stop_event};
        const DWORD w = ::WaitForMultipleObjects(2, waits, FALSE, INFINITE);
        if (w == WAIT_OBJECT_0) {
          DWORD ignored = 0;
          connected = ::GetOverlappedResult(pipe, &ov, &ignored, FALSE) != FALSE;
        } else {
          ::CancelIoEx(pipe, &ov);
        }
      }
    }
    if (connected && ClientIsAllowed(pipe, allowed)) {
      ++g_clients;
      std::thread([pipe]() {
        ServeClient(pipe);
        ::DisconnectNamedPipe(pipe);
        ::CloseHandle(pipe);
        --g_clients;
      }).detach();
    } else {
      ::DisconnectNamedPipe(pipe);
      ::CloseHandle(pipe);
    }
  }
  // клиенты видят остановку в чтении и снимают свои ядра сами
  for (int i = 0; i < 100 && g_clients > 0; ++i) ::Sleep(100);
  ::CloseHandle(connect_event);
  ::LocalFree(sd);
  ::LocalFree(allowed);
}

void ReportStatus(DWORD state, DWORD exit_code = NO_ERROR) {
  g_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  g_status.dwCurrentState = state;
  g_status.dwWin32ExitCode = exit_code;
  g_status.dwControlsAccepted =
      state == SERVICE_RUNNING ? SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN
                               : 0;
  g_status.dwWaitHint = state == SERVICE_RUNNING ? 0 : 10000;
  ::SetServiceStatus(g_status_handle, &g_status);
}

DWORD WINAPI ControlHandler(DWORD control, DWORD, LPVOID, LPVOID) {
  if (control == SERVICE_CONTROL_STOP || control == SERVICE_CONTROL_SHUTDOWN) {
    ReportStatus(SERVICE_STOP_PENDING);
    ::SetEvent(g_stop_event);
    return NO_ERROR;
  }
  return control == SERVICE_CONTROL_INTERROGATE ? NO_ERROR
                                                : ERROR_CALL_NOT_IMPLEMENTED;
}

void WINAPI ServiceMain(DWORD, LPWSTR*) {
  g_status_handle =
      ::RegisterServiceCtrlHandlerExW(kServiceName, ControlHandler, nullptr);
  if (!g_status_handle) return;
  g_stop_event = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
  ReportStatus(SERVICE_RUNNING);
  PipeLoop();
  ReportStatus(SERVICE_STOPPED);
}

// пользователь запускает и спрашивает, но не останавливает и не меняет: это могут только администраторы
std::wstring ServiceSddl(const std::wstring& sid) {
  return L"D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)"
         L"(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWRPLOCRRC;;;" +
         sid + L")";
}

bool StopService(SC_HANDLE service) {
  SERVICE_STATUS status = {};
  if (!::QueryServiceStatus(service, &status)) return false;
  if (status.dwCurrentState == SERVICE_STOPPED) return true;
  ::ControlService(service, SERVICE_CONTROL_STOP, &status);
  for (int i = 0; i < 100; ++i) {
    if (::QueryServiceStatus(service, &status) &&
        status.dwCurrentState == SERVICE_STOPPED) {
      return true;
    }
    ::Sleep(100);
  }
  return false;
}

int Install(const std::wstring& sid) {
  PSID check = nullptr;
  if (!::ConvertStringSidToSidW(sid.c_str(), &check)) return 2;
  ::LocalFree(check);

  SC_HANDLE scm = ::OpenSCManagerW(nullptr, nullptr, SC_MANAGER_ALL_ACCESS);
  if (!scm) return 3;
  SC_HANDLE existing = ::OpenServiceW(scm, kServiceName, SERVICE_ALL_ACCESS);
  if (existing) {
    StopService(existing);
  }

  const std::wstring dir = InstallDir();
  ::CreateDirectoryW(dir.c_str(), nullptr);
  const std::wstring target = ServiceExePath();
  const std::wstring self = SelfPath();
  bool copied = _wcsicmp(self.c_str(), target.c_str()) == 0;
  // процесс остановленной службы отпускает exe не сразу
  for (int i = 0; !copied && i < 25; ++i) {
    copied = ::CopyFileW(self.c_str(), target.c_str(), FALSE) != FALSE;
    if (!copied) ::Sleep(200);
  }
  if (!copied) {
    if (existing) ::CloseServiceHandle(existing);
    ::CloseServiceHandle(scm);
    return 4;
  }
  EnsurePrivateDir(RunDir());

  const std::wstring bin_path = L"\"" + target + L"\" --service";
  SC_HANDLE service = existing;
  if (service) {
    ::ChangeServiceConfigW(service, SERVICE_WIN32_OWN_PROCESS,
                           SERVICE_DEMAND_START, SERVICE_ERROR_NORMAL,
                           bin_path.c_str(), nullptr, nullptr, nullptr,
                           nullptr, nullptr, kDisplayName);
  } else {
    service = ::CreateServiceW(scm, kServiceName, kDisplayName,
                               SERVICE_ALL_ACCESS, SERVICE_WIN32_OWN_PROCESS,
                               SERVICE_DEMAND_START, SERVICE_ERROR_NORMAL,
                               bin_path.c_str(), nullptr, nullptr, nullptr,
                               nullptr, nullptr);
  }
  if (!service) {
    ::CloseServiceHandle(scm);
    return 5;
  }
  SERVICE_DESCRIPTIONW description = {
      const_cast<wchar_t*>(L"Runs the keqdroid core in TUN mode for the user "
                           L"who installed it.")};
  ::ChangeServiceConfig2W(service, SERVICE_CONFIG_DESCRIPTION, &description);

  PSECURITY_DESCRIPTOR sd = nullptr;
  if (::ConvertStringSecurityDescriptorToSecurityDescriptorW(
          ServiceSddl(sid).c_str(), SDDL_REVISION_1, &sd, nullptr)) {
    ::SetServiceObjectSecurity(service, DACL_SECURITY_INFORMATION, sd);
    ::LocalFree(sd);
  }

  HKEY key = nullptr;
  int result = 0;
  if (::RegCreateKeyExW(HKEY_LOCAL_MACHINE, kParamsKey, 0, nullptr, 0,
                        KEY_SET_VALUE, nullptr, &key,
                        nullptr) == ERROR_SUCCESS) {
    ::RegSetValueExW(key, L"AllowedUser", 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(sid.c_str()),
                     static_cast<DWORD>((sid.size() + 1) * sizeof(wchar_t)));
    ::RegCloseKey(key);
  } else {
    result = 6;
  }
  if (result == 0 && !::StartServiceW(service, 0, nullptr) &&
      ::GetLastError() != ERROR_SERVICE_ALREADY_RUNNING) {
    result = 7;
  }
  ::CloseServiceHandle(service);
  ::CloseServiceHandle(scm);
  return result;
}

// установщик при обновлении приложения: служба уже стоит, новая копия exe несёт суммы новых ядер
int Update() {
  const std::wstring sid = AllowedUserSid();
  if (sid.empty()) return 0;
  return Install(sid);
}

void RemoveTree(const std::wstring& dir) {
  WIN32_FIND_DATAW data = {};
  HANDLE find = ::FindFirstFileW((dir + L"\\*").c_str(), &data);
  if (find != INVALID_HANDLE_VALUE) {
    do {
      const std::wstring name = data.cFileName;
      if (name == L"." || name == L"..") continue;
      const std::wstring path = dir + L"\\" + name;
      if (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) {
        ::RemoveDirectoryW(path.c_str());
        ::DeleteFileW(path.c_str());
      } else if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
        RemoveTree(path);
      } else {
        ::DeleteFileW(path.c_str());
      }
    } while (::FindNextFileW(find, &data));
    ::FindClose(find);
  }
  ::RemoveDirectoryW(dir.c_str());
}

int Uninstall() {
  SC_HANDLE scm = ::OpenSCManagerW(nullptr, nullptr, SC_MANAGER_ALL_ACCESS);
  if (!scm) return 3;
  SC_HANDLE service = ::OpenServiceW(scm, kServiceName, SERVICE_ALL_ACCESS);
  if (service) {
    StopService(service);
    ::DeleteService(service);
    ::CloseServiceHandle(service);
  }
  ::CloseServiceHandle(scm);
  // Свой exe в каталоге службы удалить нельзя, пока он работает, поэтому удаляют копией из приложения.
  // Процесс остановленной службы отпускает exe не сразу, а что так и не отпустилось, Windows сотрёт при перезагрузке
  if (_wcsicmp(SelfPath().c_str(), ServiceExePath().c_str()) != 0) {
    const std::wstring dir = InstallDir();
    for (int i = 0; i < 25; ++i) {
      RemoveTree(dir);
      if (::GetFileAttributesW(dir.c_str()) == INVALID_FILE_ATTRIBUTES) break;
      ::Sleep(200);
    }
    if (::GetFileAttributesW(dir.c_str()) != INVALID_FILE_ATTRIBUTES) {
      ::MoveFileExW(ServiceExePath().c_str(), nullptr,
                    MOVEFILE_DELAY_UNTIL_REBOOT);
      ::MoveFileExW(dir.c_str(), nullptr, MOVEFILE_DELAY_UNTIL_REBOOT);
    }
  } else {
    RemoveTree(RunDir());
  }
  return 0;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE, _In_opt_ HINSTANCE, _In_ wchar_t*, _In_ int) {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (!argv) return 1;
  int result = 1;
  const std::wstring mode = argc > 1 ? argv[1] : L"";
  if (mode == L"--service") {
    SERVICE_TABLE_ENTRYW table[] = {
        {const_cast<wchar_t*>(kServiceName), ServiceMain},
        {nullptr, nullptr}};
    result = ::StartServiceCtrlDispatcherW(table) ? 0 : 1;
  } else if (mode == L"install" && argc > 2) {
    result = Install(argv[2]);
  } else if (mode == L"update") {
    result = Update();
  } else if (mode == L"uninstall") {
    result = Uninstall();
  }
  ::LocalFree(argv);
  return result;
}
