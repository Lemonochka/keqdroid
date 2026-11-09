#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "deep_link.h"
#include "flutter_window.h"
#include "single_instance.h"
#include "tunnel_channel_handler.h"
#include "utils.h"
#include "window_placement.h"
#include "windows_autostart.h"
#include "windows_tray.h"

namespace {

constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kWindowTitle[] = L"keqdroid";
constexpr wchar_t kSingleInstanceMutex[] = L"Local\\KeqDroid.SingleInstance";
constexpr wchar_t kAdminRestartFlag[] = L"--admin-restart";
constexpr wchar_t kAutostartFlag[] = L"--autostart";
constexpr UINT kAutostartConnectMsg = WM_APP + 100;

HANDLE g_instance_mutex = nullptr;

bool HasCommandLineFlag(const wchar_t* flag) {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return false;
  }
  bool found = false;
  for (int i = 1; i < argc; ++i) {
    if (_wcsicmp(argv[i], flag) == 0) {
      found = true;
      break;
    }
  }
  ::LocalFree(argv);
  return found;
}

bool HasAdminRestartFlag() {
  return HasCommandLineFlag(kAdminRestartFlag);
}

bool HasAutostartFlag() {
  return HasCommandLineFlag(kAutostartFlag);
}

void NotifyExistingInstanceAutostart() {
  HWND existing = ::FindWindowW(kWindowClassName, kWindowTitle);
  if (existing != nullptr) {
    ::PostMessageW(existing, kAutostartConnectMsg, 0, 0);
  }
}

// мьютекс держится с первой строки, а окно появляется чуть позже, и вторая ссылка сразу за первой не нашла бы, кому отдаться
HWND WaitForExistingWindow() {
  for (int attempt = 0; attempt < 30; ++attempt) {
    HWND existing = ::FindWindowW(kWindowClassName, kWindowTitle);
    if (existing != nullptr) {
      return existing;
    }
    ::Sleep(100);
  }
  return nullptr;
}

bool ActivateExistingInstance() {
  HWND existing = ::FindWindowW(kWindowClassName, kWindowTitle);
  if (existing == nullptr) {
    return WindowsTrayActivateMainWindow();
  }
  if (::IsIconic(existing)) {
    ::ShowWindow(existing, SW_RESTORE);
  } else if (!::IsWindowVisible(existing)) {
    ::ShowWindow(existing, SW_SHOW);
  } else {
    ::ShowWindow(existing, SW_SHOW);
  }
  ::SetForegroundWindow(existing);
  return true;
}

}  // namespace

void RunnerReleaseSingleInstanceMutex() {
  if (g_instance_mutex == nullptr) {
    return;
  }
  ::ReleaseMutex(g_instance_mutex);
  ::CloseHandle(g_instance_mutex);
  g_instance_mutex = nullptr;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  const bool admin_restart = HasAdminRestartFlag();
  const std::string deep_link = KeqdroidDeepLinkFromCommandLine();
  const bool start_in_tray = HasAutostartFlag() && KeqdroidAutostartInTray();

  if (admin_restart) {
    for (int attempt = 0; attempt < 100; ++attempt) {
      g_instance_mutex =
          ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
      if (g_instance_mutex != nullptr &&
          ::GetLastError() != ERROR_ALREADY_EXISTS) {
        break;
      }
      if (g_instance_mutex != nullptr) {
        ::CloseHandle(g_instance_mutex);
        g_instance_mutex = nullptr;
      }
      ::Sleep(100);
    }
    if (g_instance_mutex == nullptr) {
      g_instance_mutex =
          ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
    }
  } else {
    g_instance_mutex =
        ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
    if (g_instance_mutex != nullptr &&
        ::GetLastError() == ERROR_ALREADY_EXISTS) {
      if (!deep_link.empty()) {
        KeqdroidForwardDeepLinkToRunningInstance(WaitForExistingWindow(),
                                                 deep_link);
      }
      if (HasAutostartFlag()) {
        NotifyExistingInstanceAutostart();
      }
      // Run и задача планировщика могут сработать обе, и вторая подняла бы окно из трея
      if (!start_in_tray) {
        ActivateExistingInstance();
      }
      ::CloseHandle(g_instance_mutex);
      g_instance_mutex = nullptr;
      return EXIT_SUCCESS;
    }
  }

  // на каждом старте: приложение портативное и обновляет себя на месте, путь иначе никто не поправит
  KeqdroidRegisterUrlProtocols();
  if (!deep_link.empty()) {
    KeqdroidSetPendingDeepLink(deep_link);
  }

  FlutterWindow window(project);
  window.SetShowOnFirstFrame(!start_in_tray);
  const Win32Window::Size size(920, 720);
  const Win32Window::Point origin = Win32Window::ComputeCenteredOrigin(size);
  if (!window.Create(L"keqdroid", origin, size)) {
    return EXIT_FAILURE;
  }
  bool restore_maximized = false;
  if (KeqdroidRestoreWindowPlacement(window.GetHandle(), &restore_maximized) &&
      restore_maximized) {
    window.SetPreferredShowCommand(SW_SHOWMAXIMIZED);
  }
  if (start_in_tray) {
    WindowsTrayStartHidden(restore_maximized ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (g_instance_mutex != nullptr) {
    ::CloseHandle(g_instance_mutex);
    g_instance_mutex = nullptr;
  }
  return EXIT_SUCCESS;
}
