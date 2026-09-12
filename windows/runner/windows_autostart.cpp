#include "windows_autostart.h"

#include <windows.h>

#include <sddl.h>
#include <shellapi.h>
#include <taskschd.h>

#include <string>

namespace {

// Имя задачи в корне планировщика. Его видно человеку в «Планировщике
// заданий», поэтому оно человеческое, а не идентификатор.
constexpr wchar_t kTaskName[] = L"KeqDroid Autostart";

constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValue[] = L"KeqDroid";

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

// SID текущего пользователя. В задаче он стоит и в триггере, и в принципале:
// имя вида «КОМПЬЮТЕР\Пользователь» на локализованной системе планировщик
// принимает не всегда, SID — всегда.
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

// Путь к exe, который поднимает задача, или пусто, если задачи нет.
//
// Через COM, а не разбором вывода schtasks: тот пришлось бы читать с оглядкой
// на язык системы, а его /XML — ещё и на кодировку перенаправленного потока.
std::wstring TaskExecPath() {
  std::wstring result;
  // S_FALSE — COM на этом потоке уже поднят (это делает main.cpp), но пару
  // CoUninitialize всё равно должен получить. RPC_E_CHANGED_MODE — чужая
  // модель потока, внутрипроцессному объекту она не мешает.
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
  // Планировщик отдаёт путь таким, каким его записали. Кавычки снимаем, чтобы
  // сравнение с GetModuleFileNameW не зависело от того, кто создал задачу.
  if (result.size() >= 2 && result.front() == L'"' && result.back() == L'"') {
    result = result.substr(1, result.size() - 2);
  }
  return result;
}

std::wstring TempXmlPath() {
  wchar_t dir[MAX_PATH] = {};
  const DWORD len = ::GetTempPathW(MAX_PATH, dir);
  if (len == 0 || len >= MAX_PATH) return std::wstring();
  return std::wstring(dir, len) + L"keqdroid_autostart.xml";
}

// UTF-16 с BOM: файл задачи schtasks читает только так.
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
  // Пять секунд форы: вход в систему — самая занятая минута, а туннелю нужен
  // уже поднятый сетевой стек.
  xml += L"      <Delay>PT5S</Delay>\n    </LogonTrigger>\n  </Triggers>\n";
  xml += L"  <Principals>\n    <Principal id=\"Author\">\n";
  xml += L"      <UserId>" + sid + L"</UserId>\n";
  xml += L"      <LogonType>InteractiveToken</LogonType>\n";
  xml += L"      <RunLevel>HighestAvailable</RunLevel>\n";
  xml += L"    </Principal>\n  </Principals>\n";
  xml += L"  <Settings>\n";
  xml += L"    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>\n";
  // На ноутбуке планировщик по умолчанию не запускает задачи от батареи и
  // останавливает уже запущенные — для автозапуска VPN негодно и то и другое.
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
  // Ноль — «без ограничения». По умолчанию задачу убивают через трое суток, а
  // это приложение живёт столько, сколько включён компьютер.
  xml += L"    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>\n";
  xml += L"    <Priority>7</Priority>\n  </Settings>\n";
  xml += L"  <Actions Context=\"Author\">\n    <Exec>\n";
  xml += L"      <Command>" + XmlEscape(exe) + L"</Command>\n";
  xml += L"      <Arguments>--autostart</Arguments>\n";
  xml += L"      <WorkingDirectory>" + XmlEscape(DirectoryOf(exe)) +
         L"</WorkingDirectory>\n";
  xml += L"    </Exec>\n  </Actions>\n</Task>\n";
  return xml;
}

// schtasks под UAC. Полным путём, а не именем: на повышение уходит то, что
// лежит в системном каталоге, а не первое попавшееся в PATH.
bool RunSchtasksElevated(const std::wstring& params) {
  wchar_t system_dir[MAX_PATH] = {};
  if (::GetSystemDirectoryW(system_dir, MAX_PATH) == 0) return false;
  const std::wstring exe = std::wstring(system_dir) + L"\\schtasks.exe";

  SHELLEXECUTEINFOW info = {};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC;
  info.lpVerb = L"runas";
  info.lpFile = exe.c_str();
  info.lpParameters = params.c_str();
  info.nShow = SW_HIDE;
  // Отказ от UAC приходит сюда же (ERROR_CANCELLED) и обрабатывается так же,
  // как сбой: вызывающий вернёт переключатель обратно.
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

// Указывает ли найденная задача на этот же exe.
bool TaskMatchesThisExe(const std::wstring& task_exe) {
  if (task_exe.empty()) return false;
  const std::wstring exe = CurrentExePath();
  return !exe.empty() && _wcsicmp(task_exe.c_str(), exe.c_str()) == 0;
}

}  // namespace

bool KeqdroidIsAutostartElevated() {
  return TaskMatchesThisExe(TaskExecPath());
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

bool KeqdroidApplyAutostart(bool enabled, bool elevated, bool allow_elevation) {
  const bool want_task = enabled && elevated;
  // «Задача есть» и «задача поднимает этот exe» — разные вопросы. Выключая,
  // сносим любую: после переезда папки в планировщике осталась бы чужая.
  // Включая — пересоздаём, если путь разъехался.
  const std::wstring task_exe = TaskExecPath();
  const bool task_present = !task_exe.empty();
  const bool task_matches = TaskMatchesThisExe(task_exe);

  bool ok = true;
  bool task_now = task_matches;
  if (want_task != task_matches || (!want_task && task_present)) {
    if (allow_elevation) {
      if (want_task) {
        task_now = CreateElevatedTask();
        ok = task_now;
      } else {
        ok = DeleteElevatedTask();
        task_now = false;
      }
    } else {
      // Молча: запрашивать UAC на каждом запуске приложения — ровно то, от
      // чего эта настройка избавляет.
      ok = false;
    }
  }

  // Ключ Run закрывает всё, чего не делает задача: отказались от UAC —
  // остаётся обычный автозапуск, и приложение хотя бы стартует.
  SetRunValue(enabled && !task_now);
  return ok;
}
