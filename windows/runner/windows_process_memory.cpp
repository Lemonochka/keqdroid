#include "windows_process_memory.h"

#include <windows.h>
#include <psapi.h>
#include <tlhelp32.h>

#include <atomic>
#include <memory>
#include <thread>
#include <vector>

namespace {

std::atomic<bool> g_prefetching{false};

void PrefetchCommittedMemory() {
  std::vector<WIN32_MEMORY_RANGE_ENTRY> ranges;
  MEMORY_BASIC_INFORMATION info{};
  const char* address = nullptr;
  while (VirtualQuery(address, &info, sizeof(info)) == sizeof(info)) {
    const bool readable =
        info.Protect != 0 && (info.Protect & (PAGE_NOACCESS | PAGE_GUARD)) == 0;
    if (info.State == MEM_COMMIT && readable &&
        (info.Type == MEM_PRIVATE || info.Type == MEM_IMAGE)) {
      ranges.push_back({info.BaseAddress, info.RegionSize});
    }
    address = static_cast<const char*>(info.BaseAddress) + info.RegionSize;
  }
  if (!ranges.empty()) {
    PrefetchVirtualMemory(GetCurrentProcess(), ranges.size(), ranges.data(), 0);
  }
}

// своего вызова для чужого процесса в Win32 нет, а снимок раз в десять минут ничего не стоит
uint32_t ThreadCount(DWORD pid) {
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return 0;
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  uint32_t threads = 0;
  if (Process32FirstW(snapshot, &entry)) {
    do {
      if (entry.th32ProcessID == pid) {
        threads = entry.cntThreads;
        break;
      }
    } while (Process32NextW(snapshot, &entry));
  }
  CloseHandle(snapshot);
  return threads;
}

}  // namespace

ProcessResources QueryProcessResources(uint32_t pid) {
  ProcessResources out;
  const bool self = pid == 0;
  const DWORD target = self ? GetCurrentProcessId() : static_cast<DWORD>(pid);
  HANDLE process =
      self ? GetCurrentProcess()
           : OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ,
                         FALSE, target);
  if (process == nullptr) return out;

  PROCESS_MEMORY_COUNTERS_EX counters{};
  if (GetProcessMemoryInfo(process,
                           reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&counters),
                           sizeof(counters))) {
    out.ok = true;
    out.private_bytes = counters.PrivateUsage;
    out.working_set = counters.WorkingSetSize;
    out.peak_working_set = counters.PeakWorkingSetSize;
  }
  DWORD handles = 0;
  if (GetProcessHandleCount(process, &handles)) out.handles = handles;
  out.gdi_objects = GetGuiResources(process, GR_GDIOBJECTS);
  out.user_objects = GetGuiResources(process, GR_USEROBJECTS);
  out.threads = ThreadCount(target);

  if (!self) CloseHandle(process);
  return out;
}

void PrefetchOwnMemory(DWORD wait_ms) {
  if (g_prefetching.exchange(true)) return;
  std::shared_ptr<void> done(CreateEventW(nullptr, TRUE, FALSE, nullptr),
                             [](HANDLE event) {
                               if (event != nullptr) CloseHandle(event);
                             });
  std::thread([done] {
    PrefetchCommittedMemory();
    g_prefetching = false;
    if (done.get() != nullptr) SetEvent(done.get());
  }).detach();
  if (done.get() != nullptr) WaitForSingleObject(done.get(), wait_ms);
}
