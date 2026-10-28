#include "windows_tun_adapters.h"

#include <windows.h>

#include <cfgmgr32.h>
#include <setupapi.h>

#include <utility>

// условие и удаление как в AdapterCleanupOrphanedDevices wintun 0.14.1. там уборку делает фоновый поток ядра,
// и ядро, вышедшее или убитое сразу после неудачи, её не дожидается
std::vector<std::wstring> KeqdroidRemoveStaleWintunAdapters(
    const std::vector<std::wstring>& instance_ids) {
  std::vector<std::wstring> removed;
  HDEVINFO devices = ::SetupDiGetClassDevsExW(
      nullptr, L"SWD\\Wintun", nullptr, DIGCF_ALLCLASSES, nullptr, nullptr,
      nullptr);
  if (devices == INVALID_HANDLE_VALUE) {
    return removed;
  }

  std::vector<std::pair<SP_DEVINFO_DATA, std::wstring>> stale;
  SP_DEVINFO_DATA device = {sizeof(device)};
  for (DWORD index = 0; ::SetupDiEnumDeviceInfo(devices, index, &device);
       ++index) {
    wchar_t id[MAX_DEVICE_ID_LEN] = {};
    if (!::SetupDiGetDeviceInstanceIdW(devices, &device, id, MAX_DEVICE_ID_LEN,
                                       nullptr)) {
      continue;
    }
    bool ours = false;
    for (const auto& wanted : instance_ids) {
      if (_wcsicmp(wanted.c_str(), id) == 0) {
        ours = true;
        break;
      }
    }
    if (!ours) {
      continue;
    }
    ULONG status = 0;
    ULONG problem = 0;
    if (::CM_Get_DevNode_Status(&status, &problem, device.DevInst, 0) ==
            CR_SUCCESS &&
        !(status & DN_HAS_PROBLEM)) {
      continue;
    }
    stale.emplace_back(device, id);
  }

  for (auto& [data, id] : stale) {
    SP_REMOVEDEVICE_PARAMS params = {};
    params.ClassInstallHeader.cbSize = sizeof(params.ClassInstallHeader);
    params.ClassInstallHeader.InstallFunction = DIF_REMOVE;
    params.Scope = DI_REMOVEDEVICE_GLOBAL;
    if (::SetupDiSetClassInstallParamsW(devices, &data,
                                        &params.ClassInstallHeader,
                                        sizeof(params)) &&
        ::SetupDiCallClassInstaller(DIF_REMOVE, devices, &data)) {
      removed.push_back(id);
    }
  }
  ::SetupDiDestroyDeviceInfoList(devices);
  return removed;
}
