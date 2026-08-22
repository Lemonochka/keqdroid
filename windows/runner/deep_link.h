#ifndef RUNNER_DEEP_LINK_H_
#define RUNNER_DEEP_LINK_H_

#include <windows.h>

#include <string>

// Teaches Windows about the keqdroid:// and keqdis:// schemes (HKCU, no admin
// rights needed). Without this the "add to client" button on a subscription
// panel page has nothing to open and the click does nothing at all.
// Idempotent, and refreshes the stored path when the executable has moved.
void KeqdroidRegisterUrlProtocols();

// The link the system was asked to open us with (cold start), UTF-8.
// Empty string for a plain launch.
std::string KeqdroidDeepLinkFromCommandLine();

// Warm start: hand the link to the instance that is already running.
bool KeqdroidForwardDeepLinkToRunningInstance(HWND target,
                                              const std::string& url);

// Let a non-elevated sender through UIPI: TUN mode restarts this app as
// administrator, while the browser that opens the link is not elevated, and
// its WM_COPYDATA would otherwise be dropped without a trace.
void KeqdroidAllowDeepLinkMessages(HWND hwnd);

// Reads the link back out of a WM_COPYDATA payload.
// false — the message came from someone else and must be passed on.
bool KeqdroidDeepLinkFromCopyData(LPARAM lparam, std::string* url);

#endif  // RUNNER_DEEP_LINK_H_
