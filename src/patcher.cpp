#include "sunshinedual/patcher.h"

#include <windows.h>

#include <cstdio>
#include <fstream>
#include <optional>

namespace sd::patch {

namespace {

std::string hex(const uint8_t* p, size_t n) {
    static const char* d = "0123456789ABCDEF";
    std::string s;
    s.reserve(n * 3);
    for (size_t i = 0; i < n; ++i) {
        if (i) s.push_back(' ');
        s.push_back(d[p[i] >> 4]);
        s.push_back(d[p[i] & 0xF]);
    }
    return s;
}

// A single unique location: which spec matched, at what offset into the buffer.
struct Hit {
    size_t spec = 0;
    size_t off  = 0;
};

// Scan `buf` against every spec; require EXACTLY ONE match across all of them.
// On anything else, leave `why` explaining and return nullopt. This is the core
// safety invariant: we never act on an ambiguous or absent target.
std::optional<Hit> locate_unique(const std::vector<uint8_t>& buf, std::string& why) {
    const auto& specs = patch_specs();
    if (specs.empty()) {
        why = "no patch specs defined for this build yet (pending symbol-guided "
              "analysis of termsrv.dll); nothing to locate";
        return std::nullopt;
    }

    std::optional<Hit> hit;
    size_t total = 0;
    for (size_t si = 0; si < specs.size(); ++si) {
        auto offs = scan::find_all(buf.data(), buf.size(), specs[si].sig);
        for (size_t off : offs) {
            ++total;
            if (!hit) hit = Hit{si, off};
        }
    }

    if (total == 0) {
        why = "no spec matched this image";
        return std::nullopt;
    }
    if (total > 1) {
        why = "ambiguous: " + std::to_string(total) +
              " matches found; refusing to act on a non-unique target";
        return std::nullopt;
    }
    return hit;
}

std::string report(const PatchSpec& ps, uintptr_t site,
                   const std::vector<uint8_t>& original, const char* verb) {
    char a[20];
    std::snprintf(a, sizeof(a), "%llX", static_cast<unsigned long long>(site));
    std::string m = std::string(verb) + " @ 0x" + a;
    m += "\n  spec     : " + ps.note + (ps.verified ? " [VERIFIED]" : " [UNVERIFIED]");
    m += "\n  original : " + hex(original.data(), original.size());
    m += "\n  proposed : " + hex(ps.patch.data(), ps.patch.size());
    return m;
}

// Common core: given a buffer that mirrors the image, locate the unique site,
// verify the expected bytes, and fill `r` with the site bytes. Returns the
// (spec index, write-site offset within buf) when the site is good to go.
std::optional<std::pair<size_t, size_t>> prepare(const std::vector<uint8_t>& buf,
                                                 uintptr_t base, Result& r) {
    std::string why;
    auto hit = locate_unique(buf, why);
    if (!hit) {
        r.message = why;
        return std::nullopt;
    }

    const PatchSpec& ps = patch_specs()[hit->spec];
    const size_t site = hit->off + ps.patch_offset;
    if (site + ps.expect.size() > buf.size()) {
        r.message = "patch site runs past end of image (corrupt match)";
        return std::nullopt;
    }

    r.spec_used = ps.note;
    r.address = base + site;
    r.original.assign(buf.begin() + site, buf.begin() + site + ps.expect.size());
    r.proposed = ps.patch;

    // The on-site bytes must equal what the spec expects, or we refuse.
    if (r.original != ps.expect) {
        r.message = report(ps, base + site, r.original,
                           "REFUSING: on-site bytes != expected");
        return std::nullopt;
    }

    r.found = true;
    return std::make_pair(hit->spec, site);
}

} // namespace

const std::vector<PatchSpec>& patch_specs() {
    static const std::vector<PatchSpec> specs = {
        // termsrv.dll 10.0.26100.8875 (Win11 25H2) — CDefPolicy::Query.
        // The function compares [this+0x63c] (max) with [this+0x638] (in-use)
        // and returns error 0xD00A0013 when they are equal (at the limit).
        //   mov r8d,[rdi+0x63c]  44 8B 87 3C 06 00 00
        //   mov r9d,[rdi+0x638]  44 8B 8F 38 06 00 00
        //   cmp r8d,r9d          45 3B C1
        //   jne success          75 14
        // Flipping the jne (0x75) to jmp (0xEB) forces the success path, so the
        // session-limit check is always satisfied. Member displacements are
        // wildcarded so the signature survives minor build changes.
        PatchSpec{
            scan::parse_ida(
                "44 8B 87 ?? ?? 00 00 44 8B 8F ?? ?? 00 00 45 3B C1 75",
                "CDefPolicy::Query limit gate"),
            /*patch_offset=*/17,
            /*expect=*/{0x75},
            /*patch=*/ {0xEB},
            "termsrv 10.0.26100.8875 CDefPolicy::Query: jne->jmp so the "
            "InUse==Max session-limit check always takes the success path",
            /*verified=*/true,
        },
    };
    return specs;
}

Result enable_multisession(bool apply) {
    Result r;

    // Elevated admin tokens hold SeDebugPrivilege but with it disabled; enable it
    // or OpenProcess on the TermService svchost fails with GLE=5.
    proc::enable_debug_privilege();

    DWORD pid = proc::find_service_pid(L"TermService");
    if (pid == 0) {
        r.message = "TermService PID not found (service stopped?)";
        return r;
    }

    HANDLE h = OpenProcess(PROCESS_VM_READ | PROCESS_VM_WRITE | PROCESS_VM_OPERATION |
                               PROCESS_QUERY_INFORMATION,
                           FALSE, pid);
    if (!h) {
        r.message = "OpenProcess(TermService svchost pid=" + std::to_string(pid) +
                    ") failed, GLE=" + std::to_string(GetLastError()) +
                    " — run elevated (SeDebugPrivilege required)";
        return r;
    }

    auto mod = proc::find_module(pid, L"termsrv.dll");
    if (!mod) {
        CloseHandle(h);
        r.message = "termsrv.dll module not found in TermService process";
        return r;
    }

    std::vector<uint8_t> buf(mod->size);
    size_t got = proc::read_mem(h, mod->base, buf.data(), buf.size());
    if (got == 0) {
        CloseHandle(h);
        r.message = "failed to read termsrv.dll image from the process";
        return r;
    }
    buf.resize(got);

    auto target = prepare(buf, mod->base, r);
    if (!target) {
        CloseHandle(h);
        return r;
    }
    const PatchSpec& ps = patch_specs()[target->first];
    const uintptr_t site_va = mod->base + target->second;

    if (!apply) {
        r.message = report(ps, site_va, r.original, "DRY-RUN: would patch");
        CloseHandle(h);
        return r;
    }

    if (!ps.verified) {
        r.message = report(ps, site_va, r.original,
                           "REFUSING to write (spec not verified for this build)");
        CloseHandle(h);
        return r;
    }

    auto rec = proc::apply_patch(h, site_va, ps.patch.data(), ps.patch.size());
    if (!rec) {
        r.message = report(ps, site_va, r.original, "apply_patch FAILED");
        CloseHandle(h);
        return r;
    }

    r.applied = true;
    r.rollback.push_back(*rec);
    r.message = report(ps, site_va, r.original, "PATCHED");
    CloseHandle(h);
    return r;
}

Result scan_image_file(const std::wstring& dll_path) {
    Result r;

    std::ifstream f(dll_path.c_str(), std::ios::binary | std::ios::ate);
    if (!f) {
        r.message = "cannot open image file";
        return r;
    }
    std::streamsize size = f.tellg();
    f.seekg(0, std::ios::beg);
    std::vector<uint8_t> buf(static_cast<size_t>(size));
    if (!f.read(reinterpret_cast<char*>(buf.data()), size)) {
        r.message = "cannot read image file";
        return r;
    }

    // base 0: r.address reports the file offset of the write site.
    auto target = prepare(buf, 0, r);
    if (!target) {
        return r;
    }
    const PatchSpec& ps = patch_specs()[target->first];
    r.message = report(ps, target->second, r.original,
                       "FILE SCAN: unique match, write site at file offset");
    return r;
}

bool revert(const Result& r) {
    if (r.rollback.empty()) return false;

    proc::enable_debug_privilege();

    DWORD pid = proc::find_service_pid(L"TermService");
    if (pid == 0) return false;
    HANDLE h = OpenProcess(PROCESS_VM_READ | PROCESS_VM_WRITE | PROCESS_VM_OPERATION |
                               PROCESS_QUERY_INFORMATION,
                           FALSE, pid);
    if (!h) return false;

    bool ok = true;
    for (const auto& rec : r.rollback) {
        ok = proc::restore_patch(h, rec) && ok;
    }
    CloseHandle(h);
    return ok;
}

} // namespace sd::patch
