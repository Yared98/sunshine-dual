#include "sunshinedual/session.h"

// SCAFFOLD STUB — implemented by worker task 03 (docs/worker-tasks/task-03-orchestrator.md).
namespace sd::session {

std::vector<SessionInfo> enumerate() { return {}; }

bool ensure_local_user(const wchar_t*, const wchar_t*) { return false; }

DWORD launch_in_session(DWORD, const std::wstring&) { return 0; }

bool logoff(DWORD, bool) { return false; }

} // namespace sd::session
