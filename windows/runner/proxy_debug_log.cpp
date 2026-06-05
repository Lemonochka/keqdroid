#include "proxy_debug_log.h"

#include <windows.h>

#include <cstdarg>
#include <cstdio>
#include <deque>
#include <fstream>
#include <mutex>
#include <string>

namespace {

std::mutex g_mutex;
std::deque<std::string> g_lines;
constexpr std::size_t kMaxBufferedLines = 2000;
std::wstring g_log_file_path;

std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) {
    return std::string();
  }
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                         static_cast<int>(wide.size()), nullptr, 0,
                                         nullptr, nullptr);
  if (size <= 0) {
    return std::string();
  }
  std::string utf8(static_cast<std::size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()),
                        utf8.data(), size, nullptr, nullptr);
  return utf8;
}

void EnsureLogFilePathUnlocked() {
  if (!g_log_file_path.empty()) {
    return;
  }
  wchar_t temp[MAX_PATH] = {};
  const DWORD len = ::GetTempPathW(MAX_PATH, temp);
  if (len == 0 || len >= MAX_PATH) {
    g_log_file_path = L"keqdis_proxy_debug.log";
    return;
  }
  g_log_file_path = std::wstring(temp) + L"keqdis_proxy_debug.log";
}

void AppendLineUnlocked(const std::string& line) {
  g_lines.push_back(line);
  while (g_lines.size() > kMaxBufferedLines) {
    g_lines.pop_front();
  }

  EnsureLogFilePathUnlocked();
  std::ofstream out(g_log_file_path, std::ios::app);
  if (out) {
    out << line << '\n';
  }

  std::string debug_line = line + "\n";
  ::OutputDebugStringA(debug_line.c_str());
}

}  // namespace

void ProxyDebugClear() {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_lines.clear();
  EnsureLogFilePathUnlocked();
  std::ofstream out(g_log_file_path, std::ios::trunc);
}

void ProxyDebugLog(const char* fmt, ...) {
  char message[2048] = {};
  va_list args;
  va_start(args, fmt);
  vsnprintf(message, sizeof(message), fmt, args);
  va_end(args);

  SYSTEMTIME st = {};
  ::GetLocalTime(&st);

  char line[2300] = {};
  snprintf(line, sizeof(line), "%04u-%02u-%02u %02u:%02u:%02u.%03u %s", st.wYear,
           st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, st.wMilliseconds,
           message);

  std::lock_guard<std::mutex> lock(g_mutex);
  AppendLineUnlocked(line);
}

std::string ProxyDebugGetLogs(const std::size_t max_lines) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_lines.empty()) {
    EnsureLogFilePathUnlocked();
    return std::string("(proxy debug log empty — file: ") +
           WideToUtf8(g_log_file_path) + ")";
  }

  const std::size_t count =
      max_lines == 0 ? g_lines.size() : (max_lines < g_lines.size() ? max_lines : g_lines.size());
  const std::size_t start = g_lines.size() - count;

  std::string out;
  out.reserve(count * 80);
  for (std::size_t i = start; i < g_lines.size(); ++i) {
    out += g_lines[i];
    out += '\n';
  }
  return out;
}

std::string ProxyDebugGetLogFilePathUtf8() {
  std::lock_guard<std::mutex> lock(g_mutex);
  EnsureLogFilePathUnlocked();
  return WideToUtf8(g_log_file_path);
}
