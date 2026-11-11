#pragma once
// Terminal Services session lifecycle: enumerate sessions, provision the
// dedicated local user, launch a process inside a specific session, log off.
// Windows-only.

#include <windows.h>

#include <string>
#include <vector>

namespace sd::session {

struct SessionInfo {
    DWORD        id = 0;
    std::wstring user;      // user name, if any
    std::wstring station;   // WinStation name
    DWORD        state = 0; // WTS_CONNECTSTATE_CLASS value
};

// Enumerate current Terminal Services sessions on the local machine.
std::vector<SessionInfo> enumerate();

// Ensure a local user account exists; create it with NetUserAdd if missing.
// Idempotent: returns true if the account exists on return (created or already
// present). `password` may be required by local policy.
bool ensure_local_user(const wchar_t* name, const wchar_t* password);

// Launch `command_line` inside interactive session `session_id`, using that
// session's user token (WTSQueryUserToken + CreateProcessAsUser). Returns the
// new process id, or 0 on failure. Requires SYSTEM / SeTcbPrivilege.
DWORD launch_in_session(DWORD session_id, const std::wstring& command_line);

// Log off session `session_id`. When `wait` is true, block until completion.
bool logoff(DWORD session_id, bool wait);

} // namespace sd::session
