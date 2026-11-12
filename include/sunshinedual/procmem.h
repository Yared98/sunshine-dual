#pragma once
// Remote-process memory access and module resolution for the live TermService
// svchost. Windows-only.

#include <windows.h>

#include <cstdint>
#include <optional>
#include <vector>

namespace sd::proc {

struct ModuleRegion {
    uintptr_t base = 0;  // base address of the module in the remote process
    size_t    size = 0;  // size of the module image, in bytes
};

// Enable SeDebugPrivilege in the current process token. An elevated admin token
// *holds* this privilege but it is DISABLED by default; without it, OpenProcess
// on a service svchost (e.g. the one hosting TermService) fails with
// ERROR_ACCESS_DENIED (GLE=5) even when running elevated. Returns true if the
// privilege is enabled on return. Safe to call repeatedly.
bool enable_debug_privilege();

// PID of the svchost.exe instance that hosts the given service
// (e.g. L"TermService"). Returns 0 if the service or its host is not found.
DWORD find_service_pid(const wchar_t* service_name);

// Locate a loaded module (e.g. L"termsrv.dll") inside the remote process `pid`.
// Returns std::nullopt if the module is not loaded or the process can't be
// inspected.
std::optional<ModuleRegion> find_module(DWORD pid, const wchar_t* module_name);

// Read `n` bytes from the remote process at `addr` into `out`.
// Returns the number of bytes actually read (0 on failure).
size_t read_mem(HANDLE process, uintptr_t addr, void* out, size_t n);

// Records bytes replaced by a patch so they can be restored later.
struct PatchRecord {
    uintptr_t            addr = 0;
    std::vector<uint8_t> original;  // bytes present before the patch was applied
};

// Apply `patch` (n bytes) at `addr` in the remote process: snapshot the current
// bytes, make the page writable via VirtualProtectEx, write, flush the
// instruction cache, and restore the original page protection. Returns the
// rollback record on success, std::nullopt on any failure (in which case the
// target memory is left unchanged).
std::optional<PatchRecord> apply_patch(HANDLE process, uintptr_t addr,
                                        const uint8_t* patch, size_t n);

// Restore the bytes recorded in `rec`. Returns true on success.
bool restore_patch(HANDLE process, const PatchRecord& rec);

} // namespace sd::proc
