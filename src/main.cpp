#include <windows.h>
#include <wtsapi32.h>
#include <wchar.h>

#include <cstdio>
#include <string>
#include <vector>

#include "sunshinedual/patcher.h"
#include "sunshinedual/session.h"

// The dedicated local user whose session streams the game. Provisioned once
// (see scripts/), logged in headless, and used as the target for Apollo.
static const wchar_t* kStreamUser = L"SwitchGamer";

static int usage() {
    std::puts(
        "sunshine-dual - headless multiseat enabler (dry-run first)\n"
        "usage:\n"
        "  patch commands (termsrv single-session gate):\n"
        "    sunshine_dual scan-file <termsrv.dll>  offline: locate target, no admin, no write\n"
        "    sunshine_dual dry-run                  live TermService: locate + report, no write\n"
        "    sunshine_dual patch                    live: write if a verified spec matches (admin)\n"
        "  orchestration commands (second-session lifecycle):\n"
        "    sunshine_dual sessions                 list Terminal Services sessions (no admin)\n"
        "    sunshine_dual up <apollo.exe>          launch Apollo in the SwitchGamer session (SYSTEM)\n"
        "    sunshine_dual down                     log off the SwitchGamer session (SYSTEM)\n");
    return 2;
}

static const char* state_name(DWORD s) {
    switch (s) {
        case WTSActive:       return "Active";
        case WTSConnected:    return "Connected";
        case WTSConnectQuery: return "ConnectQuery";
        case WTSShadow:       return "Shadow";
        case WTSDisconnected: return "Disconnected";
        case WTSIdle:         return "Idle";
        case WTSListen:       return "Listen";
        case WTSReset:        return "Reset";
        case WTSDown:         return "Down";
        case WTSInit:         return "Init";
        default:              return "?";
    }
}

// Find a session owned by kStreamUser. Prefers Active, then Disconnected, then
// any. Returns the session id, or (DWORD)-1 if the user has no session.
static DWORD find_stream_session() {
    auto sessions = sd::session::enumerate();
    DWORD best = static_cast<DWORD>(-1);
    int best_rank = -1;
    for (const auto& s : sessions) {
        if (_wcsicmp(s.user.c_str(), kStreamUser) != 0) continue;
        int rank = (s.state == WTSActive) ? 2 : (s.state == WTSDisconnected ? 1 : 0);
        if (rank > best_rank) { best_rank = rank; best = s.id; }
    }
    return best;
}

int wmain(int argc, wchar_t** argv) {
    if (argc < 2) return usage();
    const std::wstring cmd = argv[1];

    // ---- patch commands --------------------------------------------------
    if (cmd == L"scan-file") {
        if (argc < 3) return usage();
        auto r = sd::patch::scan_image_file(argv[2]);
        std::printf("%s\n", r.message.c_str());
        return r.found ? 0 : 1;
    }
    if (cmd == L"dry-run") {
        auto r = sd::patch::enable_multisession(/*apply=*/false);
        std::printf("%s\n", r.message.c_str());
        return r.found ? 0 : 1;
    }
    if (cmd == L"patch") {
        auto r = sd::patch::enable_multisession(/*apply=*/true);
        std::printf("%s\n", r.message.c_str());
        return (r.applied || r.already_applied) ? 0 : 1;
    }

    // ---- orchestration commands -----------------------------------------
    if (cmd == L"sessions") {
        auto sessions = sd::session::enumerate();
        std::printf("%-5s %-16s %-14s %s\n", "ID", "USER", "STATION", "STATE");
        for (const auto& s : sessions) {
            std::printf("%-5lu %-16ls %-14ls %s\n",
                        static_cast<unsigned long>(s.id),
                        s.user.empty() ? L"-" : s.user.c_str(),
                        s.station.empty() ? L"-" : s.station.c_str(),
                        state_name(s.state));
        }
        return 0;
    }
    if (cmd == L"up") {
        if (argc < 3) return usage();
        const std::wstring apollo = argv[2];

        // Idempotent: make sure the account exists (created once by scripts/).
        sd::session::ensure_local_user(kStreamUser, L"");

        DWORD sid = find_stream_session();
        if (sid == static_cast<DWORD>(-1)) {
            std::printf("no %ls session found — log the user in (headless RDP "
                        "loopback) before 'up'\n", kStreamUser);
            return 1;
        }

        DWORD pid = sd::session::launch_in_session(sid, apollo);
        if (pid == 0) {
            std::printf("launch_in_session(%lu) failed — needs SYSTEM/SeTcbPrivilege; GLE=%lu\n",
                        static_cast<unsigned long>(sid),
                        static_cast<unsigned long>(GetLastError()));
            return 1;
        }
        std::printf("launched Apollo in session %lu as %ls, pid=%lu\n",
                    static_cast<unsigned long>(sid), kStreamUser,
                    static_cast<unsigned long>(pid));
        return 0;
    }
    if (cmd == L"down") {
        DWORD sid = find_stream_session();
        if (sid == static_cast<DWORD>(-1)) {
            std::printf("no %ls session to log off\n", kStreamUser);
            return 0;
        }
        bool ok = sd::session::logoff(sid, /*wait=*/true);
        std::printf("logoff session %lu: %s\n",
                    static_cast<unsigned long>(sid), ok ? "ok" : "failed");
        return ok ? 0 : 1;
    }

    return usage();
}
