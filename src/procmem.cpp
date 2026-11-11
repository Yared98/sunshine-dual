#include "sunshinedual/procmem.h"

#include <windows.h>
#include <tlhelp32.h>
#include <winsvc.h>
#include <wchar.h>

#include <utility>

namespace sd::proc {

namespace {

struct ScHandleCloser {
    SC_HANDLE handle = nullptr;
    ~ScHandleCloser() {
        if (handle) {
            CloseServiceHandle(handle);
        }
    }
    ScHandleCloser(SC_HANDLE h) : handle(h) {}
    ScHandleCloser(const ScHandleCloser&) = delete;
    ScHandleCloser& operator=(const ScHandleCloser&) = delete;
};

struct HandleCloser {
    HANDLE handle = INVALID_HANDLE_VALUE;
    ~HandleCloser() {
        if (handle != INVALID_HANDLE_VALUE && handle != nullptr) {
            CloseHandle(handle);
        }
    }
    HandleCloser(HANDLE h) : handle(h) {}
    HandleCloser(const HandleCloser&) = delete;
    HandleCloser& operator=(const HandleCloser&) = delete;
};

} // namespace

DWORD find_service_pid(const wchar_t* service_name) {
    if (!service_name) {
        return 0;
    }

    ScHandleCloser scm(OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT));
    if (!scm.handle) {
        return 0;
    }

    ScHandleCloser svc(OpenServiceW(scm.handle, service_name, SERVICE_QUERY_STATUS));
    if (!svc.handle) {
        return 0;
    }

    SERVICE_STATUS_PROCESS ssp{};
    DWORD bytes_needed = 0;
    if (!QueryServiceStatusEx(svc.handle, SC_STATUS_PROCESS_INFO,
                              reinterpret_cast<LPBYTE>(&ssp), sizeof(ssp),
                              &bytes_needed)) {
        return 0;
    }

    return ssp.dwProcessId;
}

std::optional<ModuleRegion> find_module(DWORD pid, const wchar_t* module_name) {
    if (pid == 0 || !module_name) {
        return std::nullopt;
    }

    HANDLE snap_raw = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    if (snap_raw == INVALID_HANDLE_VALUE) {
        return std::nullopt;
    }
    HandleCloser snap(snap_raw);

    MODULEENTRY32W me{};
    me.dwSize = sizeof(me);

    if (!Module32FirstW(snap.handle, &me)) {
        return std::nullopt;
    }

    do {
        if (_wcsicmp(me.szModule, module_name) == 0) {
            return ModuleRegion{
                reinterpret_cast<uintptr_t>(me.modBaseAddr),
                static_cast<size_t>(me.modBaseSize)
            };
        }
    } while (Module32NextW(snap.handle, &me));

    return std::nullopt;
}

size_t read_mem(HANDLE process, uintptr_t addr, void* out, size_t n) {
    if (!process || !out || n == 0) {
        return 0;
    }

    SIZE_T bytes_read = 0;
    if (!ReadProcessMemory(process, reinterpret_cast<LPCVOID>(addr), out,
                           static_cast<SIZE_T>(n), &bytes_read)) {
        return 0;
    }

    return static_cast<size_t>(bytes_read);
}

std::optional<PatchRecord> apply_patch(HANDLE process, uintptr_t addr,
                                       const uint8_t* patch, size_t n) {
    if (!process || !patch || n == 0) {
        return std::nullopt;
    }

    // 1. Snapshot current bytes — abort on failure
    std::vector<uint8_t> original(n);
    if (read_mem(process, addr, original.data(), n) != n) {
        return std::nullopt;
    }

    // 2. Make page writable
    DWORD old_protect = 0;
    if (!VirtualProtectEx(process, reinterpret_cast<LPVOID>(addr), static_cast<SIZE_T>(n),
                          PAGE_EXECUTE_READWRITE, &old_protect)) {
        return std::nullopt;
    }

    // 3. Write patch; if it fails, rollback and restore protection
    SIZE_T written = 0;
    if (!WriteProcessMemory(process, reinterpret_cast<LPVOID>(addr), patch,
                            static_cast<SIZE_T>(n), &written) || written != n) {
        if (written > 0) {
            SIZE_T rollback_written = 0;
            WriteProcessMemory(process, reinterpret_cast<LPVOID>(addr),
                               original.data(), written, &rollback_written);
            FlushInstructionCache(process, reinterpret_cast<LPCVOID>(addr), written);
        }
        DWORD tmp = 0;
        VirtualProtectEx(process, reinterpret_cast<LPVOID>(addr), static_cast<SIZE_T>(n),
                         old_protect, &tmp);
        return std::nullopt;
    }

    // 4. Flush instruction cache
    FlushInstructionCache(process, reinterpret_cast<LPCVOID>(addr), static_cast<SIZE_T>(n));

    // 5. Restore original page protection
    DWORD tmp = 0;
    VirtualProtectEx(process, reinterpret_cast<LPVOID>(addr), static_cast<SIZE_T>(n),
                     old_protect, &tmp);

    // 6. Return rollback record
    return PatchRecord{ addr, std::move(original) };
}

bool restore_patch(HANDLE process, const PatchRecord& rec) {
    if (!process || rec.addr == 0 || rec.original.empty()) {
        return false;
    }

    const size_t n = rec.original.size();
    DWORD old_protect = 0;
    if (!VirtualProtectEx(process, reinterpret_cast<LPVOID>(rec.addr), static_cast<SIZE_T>(n),
                          PAGE_EXECUTE_READWRITE, &old_protect)) {
        return false;
    }

    SIZE_T written = 0;
    BOOL write_ok = WriteProcessMemory(process, reinterpret_cast<LPVOID>(rec.addr),
                                       rec.original.data(), static_cast<SIZE_T>(n), &written);

    FlushInstructionCache(process, reinterpret_cast<LPCVOID>(rec.addr), static_cast<SIZE_T>(n));

    DWORD tmp = 0;
    VirtualProtectEx(process, reinterpret_cast<LPVOID>(rec.addr), static_cast<SIZE_T>(n),
                     old_protect, &tmp);

    return write_ok && (written == n);
}

} // namespace sd::proc
