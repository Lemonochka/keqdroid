#include "windows_traffic_stats.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>

#include <cstdlib>
#include <cstring>
#include <string>

namespace {

bool IsVirtualVpnAdapter(const MIB_IFROW& row) {
  if (row.dwOperStatus != IF_OPER_STATUS_OPERATIONAL) {
    return false;
  }
  if (row.dwType == IF_TYPE_PROP_VIRTUAL) {
    return true;
  }
  const std::string desc(reinterpret_cast<const char*>(row.bDescr), row.dwDescrLen);
  return desc.find("Wintun") != std::string::npos ||
         desc.find("wintun") != std::string::npos ||
         desc.find("sing") != std::string::npos ||
         desc.find("TAP") != std::string::npos ||
         desc.find("WireGuard") != std::string::npos;
}

bool IsLoopbackAdapter(const MIB_IFROW& row) {
  return row.dwType == IF_TYPE_SOFTWARE_LOOPBACK;
}

}  // namespace

bool ReadSessionTrafficCounters(uint64_t* in_octets, uint64_t* out_octets) {
  if (in_octets == nullptr || out_octets == nullptr) {
    return false;
  }
  *in_octets = 0;
  *out_octets = 0;

  ULONG buffer_size = 0;
  if (::GetIfTable(nullptr, &buffer_size, FALSE) != ERROR_INSUFFICIENT_BUFFER) {
    return false;
  }

  auto* table = reinterpret_cast<MIB_IFTABLE*>(std::malloc(buffer_size));
  if (table == nullptr) {
    return false;
  }

  const DWORD result = ::GetIfTable(table, &buffer_size, FALSE);
  if (result != NO_ERROR) {
    std::free(table);
    return false;
  }

  uint64_t virtual_in = 0;
  uint64_t virtual_out = 0;
  uint64_t loop_in = 0;
  uint64_t loop_out = 0;

  for (DWORD i = 0; i < table->dwNumEntries; ++i) {
    const MIB_IFROW& row = table->table[i];
    if (IsVirtualVpnAdapter(row)) {
      virtual_in += row.dwInOctets;
      virtual_out += row.dwOutOctets;
    } else if (IsLoopbackAdapter(row)) {
      loop_in += row.dwInOctets;
      loop_out += row.dwOutOctets;
    }
  }

  std::free(table);

  if (virtual_in > 0 || virtual_out > 0) {
    *in_octets = virtual_in;
    *out_octets = virtual_out;
    return true;
  }

  *in_octets = loop_in;
  *out_octets = loop_out;
  return true;
}
