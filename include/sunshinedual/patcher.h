#pragma once
// High-level multi-session patch: scan termsrv.dll in the live TermService
// process for the single-session check and flip it to allow concurrent
// sessions. Owns the signature set and the safety policy. Windows-only.

#include <string>
#include <vector>

#include "sunshinedual/procmem.h"

namespace sd::patch {

struct Result {
    bool                            applied = false;
    std::string                     signature_used;  // name of the matched signature
    std::vector<proc::PatchRecord>  rollback;        // for revert()
    std::string                     message;         // human-readable outcome
};

// Enable concurrent interactive sessions by patching the live TermService.
// Safety contract: writes nothing unless exactly one known signature matches.
// If zero or more than one candidate matches, it aborts and reports via
// Result::message with applied == false.
Result enable_multisession();

// Revert a prior patch using the rollback records in `r`.
bool revert(const Result& r);

} // namespace sd::patch
