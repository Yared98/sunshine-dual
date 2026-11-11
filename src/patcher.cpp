#include "sunshinedual/patcher.h"

// SCAFFOLD STUB — owned by the maintainer (ties scan + procmem to the real
// termsrv.dll signatures). Not delegated to a worker.
namespace sd::patch {

Result enable_multisession() {
    Result r;
    r.message = "sd::patch::enable_multisession not implemented";
    return r;
}

bool revert(const Result&) { return false; }

} // namespace sd::patch
