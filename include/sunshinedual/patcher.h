#pragma once
// High-level multi-session patch for the live TermService. Owns the known patch
// specs and the safety policy. DRY-RUN FIRST: it locates and reports before it
// ever writes, and it writes only when a VERIFIED spec matches exactly once and
// the byte(s) on site still equal what the spec expects. Windows-only.

#include <cstdint>
#include <string>
#include <vector>

#include "sunshinedual/procmem.h"
#include "sunshinedual/signature.h"

namespace sd::patch {

// One surgical patch: a pattern to locate the site (wildcards allowed for
// build-variable bytes such as struct member displacements), then a tiny write
// at a fixed offset inside the match. The write happens only if the bytes on
// site currently equal `expect`.
struct PatchSpec {
    scan::Signature      sig;            // locate the site; wildcards allowed
    size_t               patch_offset = 0;  // offset within the match to modify
    std::vector<uint8_t> expect;         // bytes that must currently be at the site
    std::vector<uint8_t> patch;          // replacement bytes (same size as expect)
    std::string          note;           // what it does / provenance (build, symbol)
    bool                 verified = false;  // confirmed against the targeted build
};

struct Result {
    bool                           found    = false;  // exactly one match located
    bool                           applied  = false;  // bytes were written
    std::string                    spec_used;
    uintptr_t                      address  = 0;       // absolute VA (or file off) of the write site
    std::vector<uint8_t>           original;           // bytes currently at the site
    std::vector<uint8_t>           proposed;           // bytes we would / did write
    std::vector<proc::PatchRecord> rollback;
    std::string                    message;            // human-readable outcome
};

// The known patch specs for termsrv.dll. Each carries `verified`; while no
// verified spec matches, enable_multisession() can only ever dry-run.
const std::vector<PatchSpec>& patch_specs();

// Locate the single-session check in the live TermService and optionally patch.
//   apply == false  -> dry-run: locate + report, writes nothing.
//   apply == true   -> writes ONLY IF a verified spec matches exactly once and
//                      the on-site bytes equal the spec's `expect`.
// Requires admin / SeDebugPrivilege to open the TermService svchost.
Result enable_multisession(bool apply);

// Offline check: scan an on-disk termsrv.dll image for the specs and report what
// would be patched. No admin needed, never writes. Used to confirm a spec is
// unique in a given build before trusting it on the live process.
Result scan_image_file(const std::wstring& dll_path);

// Revert a prior patch using its rollback records.
bool revert(const Result& r);

} // namespace sd::patch
