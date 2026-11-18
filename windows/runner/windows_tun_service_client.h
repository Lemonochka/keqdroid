#ifndef RUNNER_WINDOWS_TUN_SERVICE_CLIENT_H_
#define RUNNER_WINDOWS_TUN_SERVICE_CLIENT_H_

#include <flutter/flutter_engine.h>

// канал keqdroid/tun_service: служба KeqdroidTun поднимает ядро в TUN, когда у приложения нет прав администратора
void RegisterKeqdroidTunServiceChannel(flutter::FlutterEngine* engine);

#endif  // RUNNER_WINDOWS_TUN_SERVICE_CLIENT_H_
