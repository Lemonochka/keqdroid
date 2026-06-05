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
  g_core_job = ::CreateJobObjectW(nullptr, L"KeqDroidCoreJob");
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

void WritePidFile(DWORD xray_pid, DWORD singbox_pid) {
  const std::wstring path = CorePidFilePath();
  if (path.empty()) {
    return;
  }
  EnsureDataDir();
  std::wofstream out(path, std::ios::trunc);
  if (!out) {
    return;
  }
  if (xray_pid != 0) {
    out << xray_pid << L"\n";
  }
  if (singbox_pid != 0) {
    out << singbox_pid << L"\n";
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

  std::wifstream in(path);
  if (!in) {
    return 0;
  }

  int killed = 0;
  DWORD pid = 0;
  while (in >> pid) {
    if (TerminatePid(pid)) {
      ++killed;
    }
  }
  ClearPidFile();
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
  WritePidFile(xray_pid, singbox_pid);
}

void KeqdisClearSessionCoreProcesses() {
  ClearPidFile();
}
