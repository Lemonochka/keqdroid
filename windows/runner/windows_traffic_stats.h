#ifndef RUNNER_WINDOWS_TRAFFIC_STATS_H_
#define RUNNER_WINDOWS_TRAFFIC_STATS_H_

#include <cstdint>

// Sums InOctets/OutOctets for virtual VPN adapters (Wintun, sing-box TUN, TAP).
// Falls back to loopback when no virtual adapter has traffic (Proxy mode).
bool ReadSessionTrafficCounters(uint64_t* in_octets, uint64_t* out_octets);

#endif  // RUNNER_WINDOWS_TRAFFIC_STATS_H_
