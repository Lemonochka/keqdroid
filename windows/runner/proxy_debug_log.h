#ifndef RUNNER_PROXY_DEBUG_LOG_H_
#define RUNNER_PROXY_DEBUG_LOG_H_

#include <cstddef>
#include <string>

void ProxyDebugClear();
void ProxyDebugLog(const char* fmt, ...);
std::string ProxyDebugGetLogs(std::size_t max_lines);
std::string ProxyDebugGetLogFilePathUtf8();

#endif  // RUNNER_PROXY_DEBUG_LOG_H_
