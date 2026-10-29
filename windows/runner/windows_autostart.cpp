#include "windows_autostart.h"

#include <windows.h>

#include <sddl.h>
#include <shellapi.h>
#include <taskschd.h>

#include <string>

namespace {

// имя видно в Планировщике заданий, поэтому человеческое
constexpr wchar_t kTaskName[] = L"KeqDroid Autostart";

constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValue[] = L"KeqDroid";

// тот же ключ, где window_placement.cpp держит границы окна
constexpr wchar_t kSettingsKey[] = L"Software\\KeqDroid";
constexpr wchar_t kInTrayValue[] = L"AutostartInTray";

// 7, умолчание планировщика, это BELOW_NORMAL_PRIORITY_CLASS, и его наследуют ядра. 4-6 интерактивные (TaskSettings.Priority)
constexpr int kTaskPriority = 5;

std::wstring CurrentExePath() {
  wchar_t path[MAX_PATH] = {};
  const DWORD len = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) return std::wstring();
  return std::wstring(path, len);
}

std::wstring DirectoryOf(const std::wstring& path) {
  const auto slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? std::wstring() : path.substr(0, slash);
}

// SID, а не имя: КОМПЬЮТЕР\Пользователь на локализованной системе планировщик принимает не всегда
std::wstring CurrentUserSid() {
  HANDLE token = nullptr;
  if (!::OpenProcessToken(::GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return std::wstring();
  }
  DWORD size = 0;
  ::GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  std::wstring sid;
  if (size > 0) {
    auto* buffer = static_cast<TOKEN_USER*>(::LocalAlloc(LPTR, size));
    if (buffer != nullptr) {
      if (::GetTokenInformation(token, TokenUser, buffer, size, &size)) {
        wchar_t* text = nullptr;
        if (::ConvertSidToStringSidW(buffer->User.Sid, &text) &&
            text != nullptr) {
          sid = text;
          ::LocalFree(text);
        }
      }
      ::LocalFree(buffer);
    }
  }
  ::CloseHandle(token);
  return sid;
}

std::wstring XmlEscape(const std::wstring& value) {
  std::wstring out;
  out.reserve(value.size());
  for (const wchar_t ch : value) {
    switch (ch) {
      case L'&':
        out += L"&amp;";
        break;
      case L'<':
        out += L"&lt;";
        break;
      case L'>':
        out += L"&gt;";
        break;
      case L'"':
        out += L"&quot;";
        break;
      default:
        out += ch;
        break;
    }
  }
  return out;
}

struct ElevatedTask {
  std::wstring exe;
  int priority = -1;
};

// через COM: вывод schtasks зависит от языка системы, а /XML ещё и от кодировки потока
ElevatedTask ReadElevatedTask() {
  std::wstring result;
  int priority = -1;
  // S_FALSE: COM уже поднят в main.cpp, но пара CoUninitialize нужна. RPC_E_CHANGED_MODE внутрипроцессному объекту не мешает
  const HRESULT com = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool balance = SUCCEEDED(com);

  ITaskService* service = nullptr;
  if (SUCCEEDED(::CoCreateInstance(CLSID_TaskScheduler, nullptr,
                                   CLSCTX_INPROC_SERVER, IID_ITaskService,
                                   reinterpret_cast<void**>(&service)))) {
    VARIANT empty;
    ::VariantInit(&empty);
    if (SUCCEEDED(service->Connect(empty, empty, empty, empty))) {
      BSTR root = ::SysAllocString(L"\\");
      ITaskFolder* folder = nullptr;
      if (SUCCEEDED(service->GetFolder(root, &folder)) && folder != nullptr) {
        BSTR name = ::SysAllocString(kTaskName);
        IRegisteredTask* task = nullptr;
        if (SUCCEEDED(folder->GetTask(name, &task)) && task != nullptr) {
          ITaskDefinition* definition = nullptr;
          if (SUCCEEDED(task->get_Definition(&definition)) &&
              definition != nullptr) {
            ITaskSettings* settings = nullptr;
            if (SUCCEEDED(definition->get_Settings(&settings)) &&
                settings != nullptr) {
              settings->get_Priority(&priority);
              settings->Release();
            }
            IActionCollection* actions = nullptr;
            if (SUCCEEDED(definition->get_Actions(&actions)) &&
                actions != nullptr) {
              IAction* action = nullptr;
              if (SUCCEEDED(actions->get_Item(1, &action)) &&
                  action != nullptr) {
                IExecAction* exec = nullptr;
                if (SUCCEEDED(action->QueryInterface(
                        IID_IExecAction, reinterpret_cast<void**>(&exec))) &&
                    exec != nullptr) {
                  BSTR path = nullptr;
                  if (SUCCEEDED(exec->get_Path(&path)) && path != nullptr) {
                    result = path;
                    ::SysFreeString(path);
                  }
                  exec->Release();
                }
                action->Release();
              }
              actions->Release();
            }
            definition->Release();
          }
          task->Release();
        }
        ::SysFreeString(name);
        folder->Release();
      }
      ::SysFreeString(root);
    }
    service->Release();
  }

  if (balance) ::CoUninitialize();
  // кавычки снимаем, чтобы сравнение не зависело от того, кто создал задачу
  if (result.size() >= 2 && result.front() == L'"' && result.back() == L'"') {
    result = result.substr(1, result.size() - 2);
  }
  return {result, priority};
}

bool ProcessIsElevated() {
  HANDLE token = nullptr;
  if (!::OpenProcessToken(::GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }
  TOKEN_ELEVATION elevation = {};
  DWORD size = 0;
  const bool ok = ::GetTokenInformation(token, TokenElevation, &elevation,
                                        sizeof(elevation), &size) != 0;
  ::CloseHandle(token);
  return ok && elevation.TokenIsElevated != 0;
}

std::wstring TempXmlPath() {
  wchar_t dir[MAX_PATH] = {};
  const DWORD len = ::GetTempPathW(MAX_PATH, dir);
  if (len == 0 || len >= MAX_PATH) return std::wstring();
  return std::wstring(dir, len) + L"keqdroid_autostart.xml";
}

// UTF-16 с BOM, иначе schtasks файл не читает
bool WriteXmlFile(const std::wstring& path, const std::wstring& xml) {
  const HANDLE file =
      ::CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                    FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  const wchar_t bom = 0xFEFF;
  DWORD written = 0;
  bool ok = ::WriteFile(file, &bom, sizeof(bom), &written, nullptr) != 0;
  if (ok && !xml.empty()) {
    ok = ::WriteFile(file, xml.data(),
                     static_cast<DWORD>(xml.size() * sizeof(wchar_t)), &written,
                     nullptr) != 0;
  }
  ::CloseHandle(file);
  return ok;
}

std::wstring BuildTaskXml() {
  const std::wstring exe = CurrentExePath();
  const std::wstring sid = CurrentUserSid();
  if (exe.empty() || sid.empty()) return std::wstring();

  std::wstring xml = L"<?xml version=\"1.0\" encoding=\"UTF-16\"?>\n";
  xml +=
      L"<Task version=\"1.2\" "
      L"xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\">\n";
  xml += L"  <RegistrationInfo>\n";
  xml +=
      L"    <Description>Starts KeqDroid at sign-in with administrator "
      L"rights.</Description>\n";
  xml += L"  </RegistrationInfo>\n";
  xml += L"  <Triggers>\n    <LogonTrigger>\n      <Enabled>true</Enabled>\n";
  xml += L"      <UserId>" + sid + L"</UserId>\n";
  // пять секунд: на входе в систему туннелю нужен уже поднятый сетевой стек
  xml += L"      <Delay>PT5S</Delay>\n    </LogonTrigger>\n  </Triggers>\n";
  xml += L"  <Principals>\n    <Principal id=\"Author\">\n";
  xml += L"      <UserId>" + sid + L"</UserId>\n";
  xml += L"      <LogonType>InteractiveToken</LogonType>\n";
  xml += L"      <RunLevel>HighestAvailable</RunLevel>\n";
  xml += L"    </Principal>\n  </Principals>\n";
  xml += L"  <Settings>\n";
  xml += L"    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>\n";
  // по умолчанию на батарее задача не стартует и останавливается
  xml +=
      L"    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>\n";
  xml += L"    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>\n";
  xml += L"    <AllowHardTerminate>false</AllowHardTerminate>\n";
  xml += L"    <StartWhenAvailable>false</StartWhenAvailable>\n";
  xml += L"    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>\n";
  xml += L"    <IdleSettings>\n      <StopOnIdleEnd>false</StopOnIdleEnd>\n";
  xml += L"      <RestartOnIdle>false</RestartOnIdle>\n    </IdleSettings>\n";
  xml += L"    <AllowStartOnDemand>true</AllowStartOnDemand>\n";
  xml += L"    <Enabled>true</Enabled>\n    <Hidden>false</Hidden>\n";
  xml += L"    <RunOnlyIfIdle>false</RunOnlyIfIdle>\n";
  xml += L"    <WakeToRun>false</WakeToRun>\n";
  // по умолчанию задачу убивают через трое суток
  xml += L"    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>\n";
  xml += L"    <Priority>" + std::to_wstring(kTaskPriority) +
         L"</Priority>\n  </Settings>\n";
  xml += L"  <Actions Context=\"Author\">\n    <Exec>\n";
  xml += L"      <Command>" + XmlEscape(exe) + L"</Command>\n";
  xml += L"      <Arguments>--autostart</Arguments>\n";
  xml += L"      <WorkingDirectory>" + XmlEscape(DirectoryOf(exe)) +
         L"</WorkingDirectory>\n";
  xml += L"    </Exec>\n  </Actions>\n</Task>\n";
  return xml;
}

// полным путём: на повышение уходит системный schtasks, а не первый в PATH
bool RunSchtasksElevated(const std::wstring& params) {
  wchar_t system_dir[MAX_PATH] = {};
  if (::GetSystemDirectoryW(system_dir, MAX_PATH) == 0) return false;
  const std::wstring exe = std::wstring(system_dir) + L"\\schtasks.exe";

  SHELLEXECUTEINFOW info = {};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC;
  // из процесса с правами runas не нужен: потомок наследует его токен, и окна UAC нет
  info.lpVerb = ProcessIsElevated() ? L"open" : L"runas";
  info.lpFile = exe.c_str();
  info.lpParameters = params.c_str();
  info.nShow = SW_HIDE;
  // отказ от UAC (ERROR_CANCELLED) тоже сюда, переключатель вернётся
  if (!::ShellExecuteExW(&info) || info.hProcess == nullptr) return false;

  ::WaitForSingleObject(info.hProcess, 60000);
  DWORD code = 1;
  ::GetExitCodeProcess(info.hProcess, &code);
  ::CloseHandle(info.hProcess);
  return code == 0;
}

bool CreateElevatedTask() {
  const std::wstring xml = BuildTaskXml();
  const std::wstring path = TempXmlPath();
  if (xml.empty() || path.empty() || !WriteXmlFile(path, xml)) return false;
  const std::wstring params = std::wstring(L"/Create /TN \"") + kTaskName +
                              L"\" /XML \"" + path + L"\" /F";
  const bool ok = RunSchtasksElevated(params);
  ::DeleteFileW(path.c_str());
  return ok;
}

bool DeleteElevatedTask() {
  const std::wstring params =
      std::wstring(L"/Delete /TN \"") + kTaskName + L"\" /F";
  return RunSchtasksElevated(params);
}

bool SetRunValue(bool enable) {
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0,
                      KEY_SET_VALUE | KEY_QUERY_VALUE, &key) != ERROR_SUCCESS) {
    return false;
  }
  if (!enable) {
    ::RegDeleteValueW(key, kRunValue);
    ::RegCloseKey(key);
    return true;
  }
  const std::wstring exe = CurrentExePath();
  if (exe.empty()) {
    ::RegCloseKey(key);
    return false;
  }
  const std::wstring command = L"\"" + exe + L"\" --autostart";
  const LSTATUS status = ::RegSetValueExW(
      key, kRunValue, 0, REG_SZ,
      reinterpret_cast<const BYTE*>(command.c_str()),
      static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  ::RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

bool TaskMatchesThisExe(const std::wstring& task_exe) {
  if (task_exe.empty()) return false;
  const std::wstring exe = CurrentExePath();
  return !exe.empty() && _wcsicmp(task_exe.c_str(), exe.c_str()) == 0;
}

}  // namespace

bool KeqdroidIsAutostartElevated() {
  return TaskMatchesThisExe(ReadElevatedTask().exe);
}

bool KeqdroidIsAutostartEnabled() {
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_QUERY_VALUE, &key) !=
      ERROR_SUCCESS) {
    return false;
  }
  DWORD type = 0;
  DWORD size = 0;
  const LSTATUS status =
      ::RegQueryValueExW(key, kRunValue, nullptr, &type, nullptr, &size);
  ::RegCloseKey(key);
  return status == ERROR_SUCCESS && type == REG_SZ;
}

void KeqdroidSetAutostartInTray(bool enabled) {
  HKEY key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, kSettingsKey, 0, nullptr, 0,
                        KEY_SET_VALUE, nullptr, &key,
                        nullptr) != ERROR_SUCCESS) {
    return;
  }
  if (enabled) {
    const DWORD one = 1;
    ::RegSetValueExW(key, kInTrayValue, 0, REG_DWORD,
                     reinterpret_cast<const BYTE*>(&one), sizeof(one));
  } else {
    ::RegDeleteValueW(key, kInTrayValue);
  }
  ::RegCloseKey(key);
}

bool KeqdroidAutostartInTray() {
  DWORD value = 0;
  DWORD size = sizeof(value);
  return ::RegGetValueW(HKEY_CURRENT_USER, kSettingsKey, kInTrayValue,
                        RRF_RT_REG_DWORD, nullptr, &value,
                        &size) == ERROR_SUCCESS &&
         value != 0;
}

bool KeqdroidApplyAutostart(bool enabled, bool elevated, bool allow_elevation) {
  const bool want_task = enabled && elevated;
  // выключая, сносим любую задачу: после переезда папки осталась бы чужая. включая, пересоздаём при другом пути
  const ElevatedTask task = ReadElevatedTask();
  const bool task_present = !task.exe.empty();
  const bool task_matches = TaskMatchesThisExe(task.exe);
  // задачи до этой версии стоят с приоритетом 7. запущенное ими приложение уже с правами, пересоздаём без UAC
  const bool stale_priority =
      want_task && task_matches && task.priority != kTaskPriority;

  bool ok = true;
  bool task_now = task_matches;
  if (want_task != task_matches || (!want_task && task_present) ||
      stale_priority) {
    if (allow_elevation || (stale_priority && ProcessIsElevated())) {
      if (want_task) {
        task_now = CreateElevatedTask();
        ok = task_now;
      } else {
        ok = DeleteElevatedTask();
        task_now = false;
      }
    } else {
      // молча: UAC на каждом запуске и есть то, от чего настройка избавляет
      ok = false;
    }
  }

  // ключ Run подстраховывает: отказались от UAC, приложение хотя бы стартует
  SetRunValue(enabled && !task_now);
  return ok;
}
