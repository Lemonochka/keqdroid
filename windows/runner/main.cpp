#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "deep_link.h"
#include "flutter_window.h"
#include "single_instance.h"
#include "tunnel_channel_handler.h"
#include "utils.h"
#include "window_placement.h"
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

// The running instance holds the mutex from its very first line, but its window
// appears only a moment later — clicking a second link right after the first
// would otherwise find nothing to hand it to.
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
  // keqdroid://install-config?url=… from a subscription panel page, or a bare
  // vless:// link dropped onto the exe.
  const std::string deep_link = KeqdroidDeepLinkFromCommandLine();

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
      ActivateExistingInstance();
      ::CloseHandle(g_instance_mutex);
      g_instance_mutex = nullptr;
      return EXIT_SUCCESS;
    }
  }

  // Refreshed on every start rather than at install time: the app ships as a
  // portable archive and updates itself in place, so nothing else would ever
  // fix the stored path.
  KeqdroidRegisterUrlProtocols();
  if (!deep_link.empty()) {
    KeqdisSetPendingDeepLink(deep_link);
  }

  FlutterWindow window(project);
  const Win32Window::Size size(920, 720);
  const Win32Window::Point origin = Win32Window::ComputeCenteredOrigin(size);
  if (!window.Create(L"keqdroid", origin, size)) {
    return EXIT_FAILURE;
  }
  // Reopen with the bounds of the previous session (saved on move/resize and
  // on exit). Falls back to the default centered window when nothing valid
  // is stored (first run, monitor unplugged, corrupt record).
  bool restore_maximized = false;
  if (KeqdroidRestoreWindowPlacement(window.GetHandle(), &restore_maximized) &&
      restore_maximized) {
    window.SetPreferredShowCommand(SW_SHOWMAXIMIZED);
  }
  // WM_CLOSE hides to tray; exit via tray menu calls PostQuitMessage.
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
