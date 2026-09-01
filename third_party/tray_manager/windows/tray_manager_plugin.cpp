#include "include/tray_manager/tray_manager_plugin.h"

// This must be included before many other Windows headers.
#include <stdio.h>
#include <windows.h>

#include <shellapi.h>
#include <strsafe.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <codecvt>
#include <map>
#include <memory>
#include <sstream>

#define WM_MYMESSAGE (WM_USER + 1)

namespace {

const flutter::EncodableValue* ValueOrNull(const flutter::EncodableMap& map,
                                           const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return nullptr;
  }
  return &(it->second);
}
std::unique_ptr<
    flutter::MethodChannel<flutter::EncodableValue>,
    std::default_delete<flutter::MethodChannel<flutter::EncodableValue>>>
    channel = nullptr;

// --- keqdroid patch: см. third_party/tray_manager/PATCH.md -----------------
//
// Невидимое окно — владелец меню трея.
//
// TrackPopupMenu требует, чтобы окно-владелец было foreground: иначе меню не
// закрывается по клику мимо. Окно приложения на эту роль не годится. Спрятанное
// в трей, оно ловит WM_ACTIVATE как «верните окно на экран» (так второй
// экземпляр разворачивает первый, см. windows/runner/windows_tray.cpp), и
// правый клик по иконке разворачивал приложение вместо меню. Свёрнутое в панель
// задач — всплывает от активации. Развёрнутое — вылезает поверх того, на что
// человек смотрел.
//
// Документация TrackPopupMenu разрешает владельцем ЛЮБОЕ окно процесса, если
// стоит TPM_NONOTIFY. Берём собственное, нулевого размера и никогда не
// показываемое: меню не трогает окно приложения вообще.
HWND g_menu_owner = nullptr;

HWND EnsureMenuOwnerWindow() {
  if (g_menu_owner != nullptr && ::IsWindow(g_menu_owner)) {
    return g_menu_owner;
  }
  const wchar_t kClassName[] = L"KeqdroidTrayMenuOwner";
  HINSTANCE instance = ::GetModuleHandleW(nullptr);
  static bool class_registered = false;
  if (!class_registered) {
    WNDCLASSEXW window_class = {};
    window_class.cbSize = sizeof(WNDCLASSEXW);
    window_class.lpfnWndProc = ::DefWindowProcW;
    window_class.hInstance = instance;
    window_class.lpszClassName = kClassName;
    class_registered = ::RegisterClassExW(&window_class) != 0;
  }
  g_menu_owner =
      ::CreateWindowExW(WS_EX_TOOLWINDOW, kClassName, L"", WS_POPUP, 0, 0, 0, 0,
                        nullptr, nullptr, instance, nullptr);
  return g_menu_owner;
}

void DestroyMenuOwnerWindow() {
  if (g_menu_owner != nullptr && ::IsWindow(g_menu_owner)) {
    ::DestroyWindow(g_menu_owner);
  }
  g_menu_owner = nullptr;
}
// --- end keqdroid patch ----------------------------------------------------

class TrayManagerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  TrayManagerPlugin(flutter::PluginRegistrarWindows* registrar);

  virtual ~TrayManagerPlugin();

 private:
  std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> g_converter;

  flutter::PluginRegistrarWindows* registrar;
  NOTIFYICONDATA nid;
  NOTIFYICONIDENTIFIER niif;
  // do create pop-up menu only once.
  HMENU hMenu = CreatePopupMenu();
  bool tray_icon_setted = false;
  UINT windows_taskbar_created_message_id = 0;

  // The ID of the WindowProc delegate registration.
  int window_proc_id = -1;

  void TrayManagerPlugin::_CreateMenu(HMENU menu, flutter::EncodableMap args);
  void TrayManagerPlugin::_ApplyIcon();

  // Called for top-level WindowProc delegation.
  std::optional<LRESULT> TrayManagerPlugin::HandleWindowProc(HWND hwnd,
                                                             UINT message,
                                                             WPARAM wparam,
                                                             LPARAM lparam);
  HWND TrayManagerPlugin::GetMainWindow();
  void TrayManagerPlugin::Destroy(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void TrayManagerPlugin::SetIcon(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void TrayManagerPlugin::SetToolTip(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void TrayManagerPlugin::SetContextMenu(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void TrayManagerPlugin::PopUpContextMenu(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void TrayManagerPlugin::GetBounds(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

static bool plugin_already_registered = false;

// static
void TrayManagerPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  if (plugin_already_registered) {
    // Skip registration in subwindow
    return;
  }
  
  plugin_already_registered = true;
  
  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "tray_manager",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<TrayManagerPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

TrayManagerPlugin::TrayManagerPlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar(registrar) {
  window_proc_id = registrar->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
  windows_taskbar_created_message_id = RegisterWindowMessage(L"TaskbarCreated");
}

TrayManagerPlugin::~TrayManagerPlugin() {
  registrar->UnregisterTopLevelWindowProcDelegate(window_proc_id);
  // keqdroid patch: своё окно-владелец меню живёт ровно столько же.
  DestroyMenuOwnerWindow();
}

void TrayManagerPlugin::_CreateMenu(HMENU menu, flutter::EncodableMap args) {
  flutter::EncodableList items = std::get<flutter::EncodableList>(
      args.at(flutter::EncodableValue("items")));

  int count = GetMenuItemCount(menu);
  for (int i = 0; i < count; i++) {
    // always remove at 0 because they shift every time
    RemoveMenu(menu, 0, MF_BYPOSITION);
  }

  for (flutter::EncodableValue item_value : items) {
    flutter::EncodableMap item_map =
        std::get<flutter::EncodableMap>(item_value);
    int id = std::get<int>(item_map.at(flutter::EncodableValue("id")));
    std::string type =
        std::get<std::string>(item_map.at(flutter::EncodableValue("type")));
    std::string label =
        std::get<std::string>(item_map.at(flutter::EncodableValue("label")));
    auto* checked = std::get_if<bool>(ValueOrNull(item_map, "checked"));
    bool disabled =
        std::get<bool>(item_map.at(flutter::EncodableValue("disabled")));

    UINT_PTR item_id = id;
    UINT uFlags = MF_STRING;

    if (disabled) {
      uFlags |= MF_GRAYED;
    }

    if (type.compare("separator") == 0) {
      AppendMenuW(menu, MF_SEPARATOR, item_id, NULL);
    } else {
      if (type.compare("checkbox") == 0) {
        if (checked == nullptr) {
          // skip
        } else {
          uFlags |= (*checked == true ? MF_CHECKED : MF_UNCHECKED);
        }
      } else if (type.compare("submenu") == 0) {
        uFlags |= MF_POPUP;
        HMENU sub_menu = ::CreatePopupMenu();
        _CreateMenu(sub_menu, std::get<flutter::EncodableMap>(item_map.at(
                                  flutter::EncodableValue("submenu"))));
        item_id = reinterpret_cast<UINT_PTR>(sub_menu);
      }
      AppendMenuW(menu, uFlags, item_id, g_converter.from_bytes(label).c_str());
    }
  }
}

std::optional<LRESULT> TrayManagerPlugin::HandleWindowProc(HWND hWnd,
                                                           UINT message,
                                                           WPARAM wParam,
                                                           LPARAM lParam) {
  std::optional<LRESULT> result;
  if (message == WM_DESTROY) {
    if (tray_icon_setted) {
      Shell_NotifyIcon(NIM_DELETE, &nid);
      DestroyIcon(nid.hIcon);
    }
  } else if (message == WM_COMMAND) {
    // keqdroid patch: меню трея сюда больше не приходит — оно показывается с
    // TPM_RETURNCMD | TPM_NONOTIFY и отдаёт выбранный пункт возвратом
    // TrackPopupMenuEx. Ветка оставлена как была, для любого другого меню.
    flutter::EncodableMap eventData = flutter::EncodableMap();
    eventData[flutter::EncodableValue("id")] =
        flutter::EncodableValue((int)wParam);

    channel->InvokeMethod("onTrayMenuItemClick",
                          std::make_unique<flutter::EncodableValue>(eventData));
  } else if (message == WM_MYMESSAGE) {
    switch (lParam) {
      case WM_LBUTTONUP:
        channel->InvokeMethod("onTrayIconMouseDown",
                              std::make_unique<flutter::EncodableValue>());
        break;
      case WM_RBUTTONUP:
        channel->InvokeMethod("onTrayIconRightMouseDown",
                              std::make_unique<flutter::EncodableValue>());
        break;
      default:
        return DefWindowProc(hWnd, message, wParam, lParam);
    };
  } else if (message == windows_taskbar_created_message_id) {
    if (windows_taskbar_created_message_id != 0 && tray_icon_setted) {
      // restore the icon with the existing resource.
      tray_icon_setted = false;
      _ApplyIcon();
    }
  } else if (message == WM_POWERBROADCAST) {
    // Handle power management events (sleep/wake)
    switch (wParam) {
      case PBT_APMRESUMEAUTOMATIC:
      case PBT_APMRESUMESUSPEND:
        // System is resuming from sleep/hibernation
        if (tray_icon_setted) {
          // Restore the tray icon after system wakes up
          tray_icon_setted = false;
          _ApplyIcon();
        }
        break;
      default:
        break;
    }
  }
  return result;
}

HWND TrayManagerPlugin::GetMainWindow() {
  return ::GetAncestor(registrar->GetView()->GetNativeWindow(), GA_ROOT);
}

void TrayManagerPlugin::Destroy(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  Shell_NotifyIcon(NIM_DELETE, &nid);
  DestroyIcon(nid.hIcon);
  tray_icon_setted = false;

  result->Success(flutter::EncodableValue(true));
}

void TrayManagerPlugin::SetIcon(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const flutter::EncodableMap& args =
      std::get<flutter::EncodableMap>(*method_call.arguments());

  std::string iconPath =
      std::get<std::string>(args.at(flutter::EncodableValue("iconPath")));

  std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;

  if (nid.hIcon != nullptr) {
    DestroyIcon(nid.hIcon);
  }

  nid.hIcon = static_cast<HICON>(
      LoadImage(nullptr, (LPCWSTR)(converter.from_bytes(iconPath).c_str()),
                IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
                GetSystemMetrics(SM_CYSMICON), LR_LOADFROMFILE));

  _ApplyIcon();

  result->Success(flutter::EncodableValue(true));
}

void TrayManagerPlugin::_ApplyIcon() {
  if (tray_icon_setted) {
    Shell_NotifyIcon(NIM_MODIFY, &nid);
  } else {
    HICON hIconBackup = nid.hIcon;
    WCHAR szTipBackup[128];
    StringCchCopy(szTipBackup, _countof(szTipBackup), nid.szTip);
    
    ZeroMemory(&nid, sizeof(NOTIFYICONDATA));
    nid.cbSize = sizeof(NOTIFYICONDATA);
    nid.hWnd = GetMainWindow();
    nid.uID = 1;
    nid.hIcon = hIconBackup;
    StringCchCopy(nid.szTip, _countof(nid.szTip), szTipBackup);
    nid.uCallbackMessage = WM_MYMESSAGE;
    nid.uFlags = NIF_MESSAGE | NIF_ICON;
    if (nid.szTip[0] != '\0') {
      nid.uFlags |= NIF_TIP;
    }
    Shell_NotifyIcon(NIM_ADD, &nid);
  }

  niif.cbSize = sizeof(NOTIFYICONIDENTIFIER);
  niif.hWnd = nid.hWnd;
  niif.uID = nid.uID;
  niif.guidItem = GUID_NULL;

  tray_icon_setted = true;
}

void TrayManagerPlugin::SetToolTip(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const flutter::EncodableMap& args =
      std::get<flutter::EncodableMap>(*method_call.arguments());

  std::string toolTip =
      std::get<std::string>(args.at(flutter::EncodableValue("toolTip")));

  std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;
  nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  StringCchCopy(nid.szTip, _countof(nid.szTip),
                converter.from_bytes(toolTip).c_str());
  Shell_NotifyIcon(NIM_MODIFY, &nid);

  result->Success(flutter::EncodableValue(true));
}

void TrayManagerPlugin::SetContextMenu(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const flutter::EncodableMap& args =
      std::get<flutter::EncodableMap>(*method_call.arguments());

  _CreateMenu(hMenu, std::get<flutter::EncodableMap>(
                         args.at(flutter::EncodableValue("menu"))));

  result->Success(flutter::EncodableValue(true));
}

void TrayManagerPlugin::PopUpContextMenu(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const flutter::EncodableMap& args =
      std::get<flutter::EncodableMap>(*method_call.arguments());

  bool bringAppToFront =
      std::get<bool>(args.at(flutter::EncodableValue("bringAppToFront")));

  HWND hWnd = GetMainWindow();

  // --- keqdroid patch: см. third_party/tray_manager/PATCH.md ---------------
  //
  // bringAppToFront не влияет ни на что: активное окно нужно всегда, но окно
  // приложения при этом не трогаем вовсе. Оставлен ради сигнатуры канала.
  (void)bringAppToFront;

  // 1. Владелец меню — своё невидимое окно, не окно приложения.
  HWND owner = EnsureMenuOwnerWindow();
  if (owner == nullptr) {
    owner = hWnd;  // класс не зарегистрировался — хоть какое-то окно
  }

  // 2. Привязка — прямоугольник самой иконки, а не курсор.
  //
  //    Курсор в момент клика находится ВНУТРИ панели задач, и меню, выровненное
  //    по нему снизу, нижним краем на панель и заходило. Нативные меню трея так
  //    не делают: они встают ровно на границу рабочей области с той стороны,
  //    где панель. Считаем это явно — прежний TPM_WORKAREA в документации
  //    TrackPopupMenu не описан вовсе, и что он делает на самом деле, знает
  //    только оболочка.
  POINT cursor = {};
  ::GetCursorPos(&cursor);
  RECT anchor = {cursor.x, cursor.y, cursor.x + 1, cursor.y + 1};
  RECT icon = {};
  if (tray_icon_setted && SUCCEEDED(Shell_NotifyIconGetRect(&niif, &icon)) &&
      icon.right > icon.left && icon.bottom > icon.top) {
    anchor = icon;
  }

  MONITORINFO monitor = {};
  monitor.cbSize = sizeof(MONITORINFO);
  HMONITOR screen = ::MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST);
  if (screen == nullptr || !::GetMonitorInfoW(screen, &monitor)) {
    monitor.rcWork = {0, 0, ::GetSystemMetrics(SM_CXSCREEN),
                      ::GetSystemMetrics(SM_CYSCREEN)};
  }
  const RECT work = monitor.rcWork;

  UINT flags = TPM_RIGHTBUTTON | TPM_VERTICAL | TPM_RETURNCMD | TPM_NONOTIFY;
  int x = anchor.left;
  int y = anchor.top;
  // Панель задач лежит ВНЕ рабочей области, поэтому сторона, с которой иконка
  // за её границей, и есть сторона панели.
  auto align_along_taskbar = [&]() {
    if (anchor.left >= (work.left + work.right) / 2) {
      flags |= TPM_RIGHTALIGN;
      x = anchor.right;
    } else {
      flags |= TPM_LEFTALIGN;
      x = anchor.left;
    }
  };
  if (anchor.top >= work.bottom) {  // панель снизу
    flags |= TPM_BOTTOMALIGN;
    y = work.bottom;
    align_along_taskbar();
  } else if (anchor.bottom <= work.top) {  // панель сверху
    flags |= TPM_TOPALIGN;
    y = work.top;
    align_along_taskbar();
  } else if (anchor.left >= work.right) {  // панель справа
    flags |= TPM_RIGHTALIGN | TPM_BOTTOMALIGN;
    x = work.right;
    y = anchor.bottom < work.bottom ? anchor.bottom : work.bottom;
  } else if (anchor.right <= work.left) {  // панель слева
    flags |= TPM_LEFTALIGN | TPM_BOTTOMALIGN;
    x = work.left;
    y = anchor.bottom < work.bottom ? anchor.bottom : work.bottom;
  } else {
    // Иконка внутри рабочей области — это раскрытая шторка скрытых значков
    // либо панель задач с автоскрытием (у такой рабочая область равна всему
    // экрану, границы, к которой прижаться, просто нет). Панели рядом нет —
    // ведём себя как обычное контекстное меню: от курсора.
    flags |= TPM_LEFTALIGN | TPM_BOTTOMALIGN;
    x = cursor.x;
    y = cursor.y;
  }

  // 3. Активное окно обязательно — это прямо в документации TrackPopupMenu:
  //    без него меню не закрывается по клику мимо, и человеку остаётся только
  //    выбрать пункт.
  if (!::SetForegroundWindow(owner)) {
    // Страховка: если система отказала скрытому окну, показываем его (оно
    // нулевого размера и с WS_EX_TOOLWINDOW — увидеть нечего) и пробуем ещё
    // раз. Без активного окна меню не закроется по клику мимо.
    ::ShowWindow(owner, SW_SHOWNA);
    ::SetForegroundWindow(owner);
  }
  TPMPARAMS exclude = {};
  exclude.cbSize = sizeof(TPMPARAMS);
  exclude.rcExclude = anchor;
  const int selected = static_cast<int>(
      ::TrackPopupMenuEx(hMenu, flags, x, y, owner, &exclude));
  // 4. Тоже из документации: без этого сообщения следующее меню может не
  //    появиться, пока окно не потеряет фокус.
  ::PostMessage(owner, WM_NULL, 0, 0);

  // 5. Выбранный пункт забираем возвратом (TPM_RETURNCMD), а не через
  //    WM_COMMAND: владелец меню — невидимое окно, у него нет нашего
  //    обработчика, и WM_COMMAND ушло бы в никуда.
  if (selected != 0) {
    flutter::EncodableMap eventData = flutter::EncodableMap();
    eventData[flutter::EncodableValue("id")] =
        flutter::EncodableValue(selected);
    channel->InvokeMethod("onTrayMenuItemClick",
                          std::make_unique<flutter::EncodableValue>(eventData));
  }
  // --- end keqdroid patch --------------------------------------------------
  result->Success(flutter::EncodableValue(true));
}

void TrayManagerPlugin::GetBounds(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const flutter::EncodableMap& args =
      std::get<flutter::EncodableMap>(*method_call.arguments());

  if (!tray_icon_setted) {
    result->Success();
    return;
  }

  double devicePixelRatio =
      std::get<double>(args.at(flutter::EncodableValue("devicePixelRatio")));

  RECT rect;
  Shell_NotifyIconGetRect(&niif, &rect);
  flutter::EncodableMap resultMap = flutter::EncodableMap();

  double x = rect.left / devicePixelRatio * 1.0f;
  double y = rect.top / devicePixelRatio * 1.0f;
  double width = (rect.right - rect.left) / devicePixelRatio * 1.0f;
  double height = (rect.bottom - rect.top) / devicePixelRatio * 1.0f;

  resultMap[flutter::EncodableValue("x")] = flutter::EncodableValue(x);
  resultMap[flutter::EncodableValue("y")] = flutter::EncodableValue(y);
  resultMap[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
  resultMap[flutter::EncodableValue("height")] =
      flutter::EncodableValue(height);

  result->Success(flutter::EncodableValue(resultMap));
}

void TrayManagerPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("destroy") == 0) {
    Destroy(method_call, std::move(result));
  } else if (method_call.method_name().compare("setIcon") == 0) {
    SetIcon(method_call, std::move(result));
  } else if (method_call.method_name().compare("setToolTip") == 0) {
    SetToolTip(method_call, std::move(result));
  } else if (method_call.method_name().compare("setContextMenu") == 0) {
    SetContextMenu(method_call, std::move(result));
  } else if (method_call.method_name().compare("popUpContextMenu") == 0) {
    PopUpContextMenu(method_call, std::move(result));
  } else if (method_call.method_name().compare("getBounds") == 0) {
    GetBounds(method_call, std::move(result));
  } else {
    result->NotImplemented();
  }
}

}  // namespace

void TrayManagerPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  TrayManagerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
