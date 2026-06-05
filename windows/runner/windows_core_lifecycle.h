#ifndef RUNNER_WINDOWS_CORE_LIFECYCLE_H_
#define RUNNER_WINDOWS_CORE_LIFECYCLE_H_

#include <windows.h>

// Job object + pid registry: xray/sing-box die when the app exits or crashes.
void KeqdisInitCoreProcessGuard();
void KeqdisAttachCoreProcess(DWORD pid);
void KeqdisRegisterSessionCoreProcesses(DWORD xray_pid, DWORD singbox_pid);
void KeqdisClearSessionCoreProcesses();

#endif  // RUNNER_WINDOWS_CORE_LIFECYCLE_H_
