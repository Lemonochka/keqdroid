#ifndef RUNNER_WINDOWS_TUN_ADAPTERS_H_
#define RUNNER_WINDOWS_TUN_ADAPTERS_H_

#include <string>
#include <vector>

// instance_ids вида SWD\Wintun\{GUID}, возвращает удалённые
std::vector<std::wstring> KeqdroidRemoveStaleWintunAdapters(
    const std::vector<std::wstring>& instance_ids);

#endif  // RUNNER_WINDOWS_TUN_ADAPTERS_H_
