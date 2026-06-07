#ifndef RUNNER_TUNNEL_CHANNEL_HANDLER_H_
#define RUNNER_TUNNEL_CHANNEL_HANDLER_H_

#include <flutter/flutter_engine.h>

void RegisterKeqdisTunnelChannel(flutter::FlutterEngine* engine);

// Called when a second --autostart instance forwards connect to the running app.
void KeqdisRequestAutostartConnect();

#endif  // RUNNER_TUNNEL_CHANNEL_HANDLER_H_
