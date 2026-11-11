#ifndef RUNNER_TUNNEL_CHANNEL_HANDLER_H_
#define RUNNER_TUNNEL_CHANNEL_HANDLER_H_

#include <flutter/flutter_engine.h>

#include <string>

void RegisterKeqdroidTunnelChannel(flutter::FlutterEngine* engine);

// второй экземпляр с --autostart пересылает подключение
void KeqdroidRequestAutostartConnect();

// до движка, Dart заберёт через getPendingDeepLink
void KeqdroidSetPendingDeepLink(const std::string& url);

void KeqdroidRequestDeepLink(const std::string& url);

void KeqdroidNotifyHotkeyPressed(const std::string& action);

// Dart по нему ставит на паузу анимацию и опрос трафика: жизненный цикл Flutter отдаёт SW_HIDE как inactive, не hidden
void KeqdroidNotifyWindowVisibility(bool visible);

// чтобы после перезагрузки интернет был до запуска keqdroid
void KeqdroidClearSystemProxyOnSessionEnd();

// после удаления приложение больше не стартует и свой зависший прокси уже не снимет
void KeqdroidClearStaleSystemProxy();

#endif  // RUNNER_TUNNEL_CHANNEL_HANDLER_H_
