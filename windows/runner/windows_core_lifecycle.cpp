#include "windows_core_lifecycle.h"

#include <shlobj.h>

#include <fstream>
#include <string>
#include <vector>

namespace {

HANDLE g_core_job = nullptr;

std::wstring KeqdisDataDir() {
  wchar_t appdata[MAX_PATH] = {};
  if (FAILED(SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, 0, appdata))) {
    return L"";
  }
  return std::wstring(appdata) + L"\\com.keqdroid\\keqdroid";
}

std::wstring CorePidFilePath() {
  const std::wstring dir = KeqdisDataDir();
  if (dir.empty()) {
    return L"";
  }
  return dir + L"\\active_core_pids.txt";
}

void EnsureDataDir() {
  const std::wstring dir = KeqdisDataDir();
  if (dir.empty()) {
    return;
  }
  wchar_t appdata[MAX_PATH] = {};
  if (FAILED(SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, 0, appdata))) {
    return;
  }
  CreateDirectoryW((std::wstring(appdata) + L"\\com.keqdroid").c_str(), nullptr);
  CreateDirectoryW(dir.c_str(), nullptr);
}

bool EnsureCoreJobObject() {
  if (g_core_job != nullptr) {
    return true;
  }
  // Безымянный job — принципиально. С именем ("KeqDroidCoreJob") новый
  // экземпляр приложения (перезапуск с правами администратора при переходе
  // proxy → TUN) открывал ТОТ ЖЕ объект: пока жив его второй хэндл,
  // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE при выходе старого экземпляра не
  // срабатывает, и ядро старой сессии остаётся висеть, занимая порты.
  g_core_job = ::CreateJobObjectW(nullptr, nullptr);
  if (g_core_job == nullptr) {
    return false;
  }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  ::SetInformationJobObject(g_core_job, JobObjectExtendedLimitInformation, &limits,
                            sizeof(limits));
  return true;
}

bool AttachProcessToCoreJob(DWORD pid) {
  if (pid == 0 || !EnsureCoreJobObject()) {
    return false;
  }
  HANDLE process =
      ::OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, FALSE, pid);
  if (process == nullptr) {
    return false;
  }
  const BOOL ok = ::AssignProcessToJobObject(g_core_job, process);
  ::CloseHandle(process);
  return ok != FALSE;
}

bool EndsWithIgnoreCase(const std::wstring& value, const std::wstring& suffix) {
  if (value.size() < suffix.size()) {
    return false;
  }
  const std::wstring tail = value.substr(value.size() - suffix.size());
  return _wcsicmp(tail.c_str(), suffix.c_str()) == 0;
}

bool IsKeqdisCoreProcess(DWORD pid) {
  HANDLE process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) {
    return false;
  }
  wchar_t path[MAX_PATH];
  DWORD size = MAX_PATH;
  bool is_core = false;
  if (::QueryFullProcessImageNameW(process, 0, path, &size)) {
    const std::wstring image(path);
    // keqrnel.exe — единственное ядро, которое приложение сейчас запускает
    // (sing-box host + встроенный xray). Без него в списке осиротевший процесс
    // не убивался: pid-файл вычищался, а ядро жило и занимало порт/TUN, из-за
    // чего следующая сессия падала и процесс приходилось снимать вручную.
    is_core = EndsWithIgnoreCase(image, L"keqrnel.exe") ||
              EndsWithIgnoreCase(image, L"xray.exe") ||
              EndsWithIgnoreCase(image, L"sing-box.exe") ||
              EndsWithIgnoreCase(image, L"wireproxy.exe");
  }
  ::CloseHandle(process);
  return is_core;
}

bool TerminatePid(DWORD pid) {
  if (pid == 0) {
    return false;
  }
  HANDLE process = ::OpenProcess(PROCESS_TERMINATE, FALSE, pid);
  if (process == nullptr) {
    return false;
  }
  const BOOL ok = ::TerminateProcess(process, 1);
  ::CloseHandle(process);
  return ok != FALSE;
}

void WritePidFile(const std::vector<DWORD>& pids) {
  const std::wstring path = CorePidFilePath();
  if (path.empty()) {
    return;
  }
  EnsureDataDir();
  std::wofstream out(path, std::ios::trunc);
  if (!out) {
    return;
  }
  for (const DWORD pid : pids) {
    if (pid != 0) {
      out << pid << L"\n";
    }
  }
}

void ClearPidFile() {
  const std::wstring path = CorePidFilePath();
  if (!path.empty()) {
    ::DeleteFileW(path.c_str());
  }
}

int KillOrphanCoresFromPidFile() {
  const std::wstring path = CorePidFilePath();
  if (path.empty()) {
    return 0;
  }

  std::vector<DWORD> pids;
  {
    std::wifstream in(path);
    if (!in) {
      return 0;
    }
    DWORD pid = 0;
    while (in >> pid) {
      pids.push_back(pid);
    }
  }

  int killed = 0;
  std::vector<DWORD> survivors;
  for (const DWORD pid : pids) {
    // Проверка образа обязательна: pid мог быть переиспользован системой под
    // чужой процесс, и TerminateProcess по нему был бы диверсией.
    if (!IsKeqdisCoreProcess(pid)) {
      continue;  // мёртв или уже не наш — просто забываем
    }
    if (TerminatePid(pid)) {
      ++killed;
      continue;
    }
    // Живое наше ядро, но снять не вышло — обычно оно elevated, а мы нет.
    // Оставляем в файле: следующий запуск с правами администратора доберёт.
    survivors.push_back(pid);
  }

  if (survivors.empty()) {
    ClearPidFile();
  } else {
    WritePidFile(survivors);
  }
  return killed;
}

}  // namespace

void KeqdisInitCoreProcessGuard() {
  EnsureCoreJobObject();
  KillOrphanCoresFromPidFile();
}

void KeqdisAttachCoreProcess(DWORD pid) {
  AttachProcessToCoreJob(pid);
}

void KeqdisRegisterSessionCoreProcesses(DWORD xray_pid, DWORD singbox_pid) {
  EnsureCoreJobObject();
  if (xray_pid != 0) {
    AttachProcessToCoreJob(xray_pid);
  }
  if (singbox_pid != 0) {
    AttachProcessToCoreJob(singbox_pid);
  }
  WritePidFile({xray_pid, singbox_pid});
}

void KeqdisClearSessionCoreProcesses() {
  ClearPidFile();
}
