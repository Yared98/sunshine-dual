#include "sunshinedual/procmem.h"

// SCAFFOLD STUB — implemented by worker task 02 (docs/worker-tasks/task-02-procmem.md).
namespace sd::proc {

DWORD find_service_pid(const wchar_t*) { return 0; }

std::optional<ModuleRegion> find_module(DWORD, const wchar_t*) { return std::nullopt; }

size_t read_mem(HANDLE, uintptr_t, void*, size_t) { return 0; }

std::optional<PatchRecord> apply_patch(HANDLE, uintptr_t, const uint8_t*, size_t) {
    return std::nullopt;
}

bool restore_patch(HANDLE, const PatchRecord&) { return false; }

} // namespace sd::proc
