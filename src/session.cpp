#include "sunshinedual/session.h"

#include <windows.h>
#include <wtsapi32.h>
#include <lm.h>
#include <userenv.h>

#include <string>
#include <vector>

namespace sd::session {

std::vector<SessionInfo> enumerate() {
    std::vector<SessionInfo> sessions;
    PWTS_SESSION_INFOW pSessionInfo = nullptr;
    DWORD count = 0;

    if (!WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &pSessionInfo, &count)) {
        return sessions;
    }

    sessions.reserve(count);
    for (DWORD i = 0; i < count; ++i) {
        const auto& s = pSessionInfo[i];
        SessionInfo info;
        info.id = s.SessionId;
        if (s.pWinStationName != nullptr) {
            info.station = s.pWinStationName;
        }
        info.state = static_cast<DWORD>(s.State);

        LPWSTR pUser = nullptr;
        DWORD bytesReturned = 0;
        if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, s.SessionId, WTSUserName, &pUser, &bytesReturned)) {
            if (pUser != nullptr) {
                info.user = pUser;
                WTSFreeMemory(pUser);
            }
        }

        sessions.push_back(std::move(info));
    }

    WTSFreeMemory(pSessionInfo);
    return sessions;
}

bool ensure_local_user(const wchar_t* name, const wchar_t* password) {
    if (name == nullptr) {
        return false;
    }

    LPBYTE buf = nullptr;
    NET_API_STATUS status = NetUserGetInfo(nullptr, name, 1, &buf);
    if (buf != nullptr) {
        NetApiBufferFree(buf);
        buf = nullptr;
    }

    if (status == NERR_Success) {
        return true;
    }

    if (status == NERR_UserNotFound) {
        USER_INFO_1 ui{};
        ui.usri1_name = const_cast<LPWSTR>(name);
        ui.usri1_password = const_cast<LPWSTR>(password != nullptr ? password : L"");
        ui.usri1_priv = USER_PRIV_USER;
        ui.usri1_flags = UF_DONT_EXPIRE_PASSWD | UF_SCRIPT;

        DWORD parm_err = 0;
        NET_API_STATUS add_status = NetUserAdd(nullptr, 1, reinterpret_cast<LPBYTE>(&ui), &parm_err);
        return (add_status == NERR_Success || add_status == NERR_UserExists);
    }

    return false;
}

DWORD launch_in_session(DWORD session_id, const std::wstring& command_line) {
    if (command_line.empty()) {
        return 0;
    }

    HANDLE token = nullptr;
    if (!WTSQueryUserToken(session_id, &token)) {
        return 0;
    }

    HANDLE primary = nullptr;
    if (!DuplicateTokenEx(token, MAXIMUM_ALLOWED, nullptr, SecurityImpersonation, TokenPrimary, &primary)) {
        CloseHandle(token);
        return 0;
    }

    LPVOID env = nullptr;
    if (!CreateEnvironmentBlock(&env, primary, FALSE)) {
        CloseHandle(primary);
        CloseHandle(token);
        return 0;
    }

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    wchar_t desktop[] = L"winsta0\\default";
    si.lpDesktop = desktop;

    PROCESS_INFORMATION pi{};
    std::vector<wchar_t> cmd_buf(command_line.begin(), command_line.end());
    cmd_buf.push_back(L'\0');

    BOOL ok = CreateProcessAsUserW(
        primary,
        nullptr,
        cmd_buf.data(),
        nullptr,
        nullptr,
        FALSE,
        CREATE_UNICODE_ENVIRONMENT,
        env,
        nullptr,
        &si,
        &pi
    );

    DWORD pid = 0;
    if (ok) {
        pid = pi.dwProcessId;
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
    }

    DestroyEnvironmentBlock(env);
    CloseHandle(primary);
    CloseHandle(token);

    return pid;
}

bool logoff(DWORD session_id, bool wait) {
    return WTSLogoffSession(WTS_CURRENT_SERVER_HANDLE, session_id, wait ? TRUE : FALSE) != FALSE;
}

} // namespace sd::session
