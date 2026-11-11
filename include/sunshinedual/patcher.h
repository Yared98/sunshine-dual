#pragma once
// High-level multi-session patch for the live TermService. Owns the known patch
// specs and the safety policy. DRY-RUN FIRST: it locates and reports before it
// ever writes, and it writes only when a VERIFIED spec matches exactly once and
// the bytes on site still equal what the spec expects. Windows-only.

#include <cstdint>
#include <string>
#include <vector>

#include "sunshinedual/procmem.h"
#include "sunshinedual/signature.h"

namespace sd::patch {

// One candidate patch: a pattern to locate (with wildcards for relocated/
// build-variable bytes), the replacement bytes, and whether it has been
// confirmed against the build currently being targeted.
struct PatchSpec {
    scan::Signature      sig;       // pattern to locate; size == patch.size()
    std::vector<uint8_t> patch;     // replacement bytes
    std::string          note;      // what it does / provenance (build, symbol)
    bool                 verified = false;  // true only once confirmed on this build
};

struct Result {
    bool                           found    = false;  // exactly one match located
    bool                           applied  = false;  // bytes were written
    std::string                    spec_used;
    uintptr_t                      address  = 0;       // absolute VA of the match
    std::vector<uint8_t>           original;           // bytes currently on site
    std::vector<uint8_t>           proposed;           // bytes we would / did write
    std::vector<proc::PatchRecord> rollback;
    std::string                    message;            // human-readable outcome
};

// The known patch specs for termsrv.dll. Currently empty / unverified until the
// signature is derived from symbol-guided analysis of the exact build. While no
// verified spec exists, enable_multisession() can only ever dry-run.
const std::vector<PatchSpec>& patch_specs();

// Locate the single-session check in the live TermService and optionally patch.
//   apply == false  -> dry-run: locate + report, writes nothing.
//   apply == true   -> writes ONLY IF a verified spec matches exactly once and
//                      the on-site bytes equal the spec's expected originals.
// Requires admin / SeDebugPrivilege to open the TermService svchost.
Result enable_multisession(bool apply);

// Offline check: scan an on-disk termsrv.dll image for the specs and report what
// would be patched. No admin needed, never writes. Used to verify a spec is
// unique in a given build before trusting it on the live process.
Result scan_image_file(const std::wstring& dll_path);

// Revert a prior patch using its rollback records.
bool revert(const Result& r);

} // namespace sd::patch
