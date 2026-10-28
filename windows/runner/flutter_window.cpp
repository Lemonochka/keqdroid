#include "flutter_window.h"

#include <flutter_windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

#include "deep_link.h"
#include "tunnel_channel_handler.h"
#include "windows_hotkeys.h"
#include "windows_tray.h"

#include <string>

namespace {
constexpr UINT kAutostartConnectMsg = WM_APP + 100;

// окно по первому кадру, без кадра остаётся процесс без окна и трея.
// id не единица: её первой берёт window_manager, который сабклассит это окно
constexpr UINT_PTR kStartupWatchdogTimerId = 0x4B440001;
// с запасом на самый медленный честный старт
constexpr UINT kStartupWatchdogMs = 20000;

// вкладкам нужна ширина узкого телефона (360) рядом с боковой панелью (77)
constexpr int kMinWindowWidth = 480;
constexpr int kMinWindowHeight = 580;

void ApplyMinWindowSize(HWND hwnd, MINMAXINFO* info) {
  const double scale = FlutterDesktopGetDpiForHWND(hwnd) / 96.0;
  LONG width = static_cast<LONG>(kMinWindowWidth * scale);
  LONG height = static_cast<LONG>(kMinWindowHeight * scale);
  // на маленьком экране с крупным масштабом минимум не больше рабочей области
  MONITORINFO monitor = {sizeof(monitor)};
  if (::GetMonitorInfo(::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                       &monitor)) {
    const LONG work_width = monitor.rcWork.right - monitor.rcWork.left;
    const LONG work_height = monitor.rcWork.bottom - monitor.rcWork.top;
    if (width > work_width) width = work_width;
    if (height > work_height) height = work_height;
  }
  info->ptMinTrackSize.x = width;
  info->ptMinTrackSize.y = height;
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

// деструктор unique_ptr удаляет, не обнулив указатель, и WM_PARENTNOTIFY от гибнущего вида Flutter
// ушёл бы в HandleTopLevelWindowProc уже без вида. так выходит window_manager destroy()
FlutterWindow::~FlutterWindow() { flutter_controller_ = nullptr; }

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterKeqdisTunnelChannel(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    first_frame_seen_ = true;
    ::KillTimer(GetHandle(), kStartupWatchdogTimerId);
    if (show_on_first_frame_) {
      this->Show();
    }
  });
  ::SetTimer(GetHandle(), kStartupWatchdogTimerId, kStartupWatchdogMs,
             nullptr);

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  WindowsTrayInit(GetHandle());
  KeqdroidAllowDeepLinkMessages(GetHandle());

  return true;
}

void FlutterWindow::OnDestroy() {
  KeqdroidUnregisterAllHotkeys(GetHandle());
  WindowsTrayDispose(GetHandle());

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::ReportStartupFailure(HWND hwnd) {
  // закрытие обязано завершать процесс: иконку трея ставит Dart, а его нет
  WindowsTraySetMinimizeToTray(false);
  ::ShowWindow(hwnd, SW_SHOW);
  ::SetForegroundWindow(hwnd);
  ::MessageBoxW(
      hwnd,
      L"keqdroid запустился, но не смог показать интерфейс.\n\n"
      L"Закройте это окно и пришлите файл app.log из папки\n"
      L"%APPDATA%\\com.keqdroid\\keqdroid — по нему видно, что сломалось.",
      L"keqdroid", MB_OK | MB_ICONERROR);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // до Flutter и плагинов: любой может ответить сам, и прокси повис бы. на WM_QUERYENDSESSION рано, выключение ещё отменят
  if (message == WM_ENDSESSION && wparam) {
    KeqdisClearSystemProxyOnSessionEnd();
  }
  // тоже до плагинов: window_manager отвечает на WM_GETMINMAXINFO сам и дальше не пускает
  if (message == WM_GETMINMAXINFO) {
    ApplyMinWindowSize(hwnd, reinterpret_cast<MINMAXINFO*>(lparam));
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  {
    LRESULT tray_result = 0;
    if (WindowsTrayHandleMessage(hwnd, message, wparam, lparam, &tray_result)) {
      return tray_result;
    }
  }

  switch (message) {
    case kAutostartConnectMsg:
      KeqdisRequestAutostartConnect();
      return 0;
    case WM_COPYDATA: {
      std::string url;
      if (KeqdroidDeepLinkFromCopyData(lparam, &url)) {
        // из трея поднимаемся сами: только этот процесс знает, спрятано ли окно, а итог импорта должно быть видно
        WindowsTrayActivateMainWindow();
        KeqdisRequestDeepLink(url);
        return TRUE;
      }
      break;
    }
    case WM_HOTKEY: {
      const std::string action =
          KeqdroidHotkeyActionForId(static_cast<int>(wparam));
      if (!action.empty()) {
        KeqdisNotifyHotkeyPressed(action);
        return 0;
      }
      break;
    }
    case WM_TIMER:
      if (wparam == kStartupWatchdogTimerId) {
        ::KillTimer(hwnd, kStartupWatchdogTimerId);
        if (!first_frame_seen_) {
          ReportStartupFailure(hwnd);
        }
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
