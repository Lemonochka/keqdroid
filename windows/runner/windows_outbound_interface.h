#ifndef RUNNER_WINDOWS_OUTBOUND_INTERFACE_H_
#define RUNNER_WINDOWS_OUTBOUND_INTERFACE_H_

#include <cstdint>
#include <string>

// сеть, которой ядро туннеля выходит само: findOutboundInterface у xray, checkUpdate в monitor_windows.go
// у sing-tun для mihomo; пусто, если выхода нет
std::wstring FindTunBypassInterface(uint32_t tun_index, bool mihomo_rule);

#endif  // RUNNER_WINDOWS_OUTBOUND_INTERFACE_H_
