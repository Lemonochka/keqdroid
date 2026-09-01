#ifndef RUNNER_TUNNEL_CHANNEL_HANDLER_H_
#define RUNNER_TUNNEL_CHANNEL_HANDLER_H_

#include <flutter/flutter_engine.h>

#include <string>

void RegisterKeqdisTunnelChannel(flutter::FlutterEngine* engine);

// Called when a second --autostart instance forwards connect to the running app.
void KeqdisRequestAutostartConnect();

// The link the app was launched with (cold start), stored before the engine is
// up. Dart picks it up with getPendingDeepLink once its UI is built.
void KeqdisSetPendingDeepLink(const std::string& url);

// A link forwarded by a second instance while this one is already running.
void KeqdisRequestDeepLink(const std::string& url);

// WM_HOTKEY: forward the triggered global-hotkey action to Dart.
void KeqdisNotifyHotkeyPressed(const std::string& action);

// Main window hidden to / restored from the tray. Dart uses this as the
// authoritative "is the window on screen" signal to pause the off-screen wave
// animation and the traffic-stats polling — the Flutter lifecycle reports a
// tray SW_HIDE only as `inactive`, not `hidden`, so those guards never engage.
void KeqdisNotifyWindowVisibility(bool visible);

#endif  // RUNNER_TUNNEL_CHANNEL_HANDLER_H_
