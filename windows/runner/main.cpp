#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "single_instance.h"
#include "utils.h"
#include "windows_tray.h"

namespace {

constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kWindowTitle[] = L"keqdroid";
constexpr wchar_t kSingleInstanceMutex[] = L"Local\\KeqDroid.SingleInstance";
constexpr wchar_t kAdminRestartFlag[] = L"--admin-restart";

HANDLE g_instance_mutex = nullptr;

bool HasAdminRestartFlag() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return false;
  }
  bool found = false;
  for (int i = 1; i < argc; ++i) {
    if (_wcsicmp(argv[i], kAdminRestartFlag) == 0) {
      found = true;
      break;
    }
  }
  ::LocalFree(argv);
  return found;
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
      ActivateExistingInstance();
      ::CloseHandle(g_instance_mutex);
      g_instance_mutex = nullptr;
      return EXIT_SUCCESS;
    }
  }

  FlutterWindow window(project);
  const Win32Window::Size size(920, 720);
  const Win32Window::Point origin = Win32Window::ComputeCenteredOrigin(size);
  if (!window.Create(L"keqdroid", origin, size)) {
    return EXIT_FAILURE;
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
