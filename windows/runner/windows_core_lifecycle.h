#ifndef RUNNER_WINDOWS_CORE_LIFECYCLE_H_
#define RUNNER_WINDOWS_CORE_LIFECYCLE_H_

#include <windows.h>

// job object и реестр pid: ядра умирают вместе с приложением, даже при падении
void KeqdroidInitCoreProcessGuard();
// живое ядро держит свой exe, и удаление не смогло бы стереть папку
void KeqdroidKillOrphanCores();
void KeqdroidAttachCoreProcess(DWORD pid);
void KeqdroidRegisterSessionCoreProcesses(DWORD xray_pid, DWORD singbox_pid);
void KeqdroidClearSessionCoreProcesses();

#endif  // RUNNER_WINDOWS_CORE_LIFECYCLE_H_
