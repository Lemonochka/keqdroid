#ifndef RUNNER_TUNNEL_CHANNEL_HANDLER_H_
#define RUNNER_TUNNEL_CHANNEL_HANDLER_H_

#include <flutter/flutter_engine.h>

void RegisterKeqdisTunnelChannel(flutter::FlutterEngine* engine);

// Called when a second --autostart instance forwards connect to the running app.
void KeqdisRequestAutostartConnect();

// Right-click on the tray icon — open the Flutter tray menu.
void KeqdisRequestTrayMenu();

// Tray popup dismissed from native side (click outside / focus loss).
void KeqdisNotifyTrayMenuClosed();
void KeqdisNotifyTrayMenuClosedImmediate();

#endif  // RUNNER_TUNNEL_CHANNEL_HANDLER_H_
