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

std::string report(const PatchSpec& ps, uintptr_t addr,
                   const std::vector<uint8_t>& original,
                   const char* verb) {
    std::string m = std::string(verb) + " @ 0x";
    char a[20];
    std::snprintf(a, sizeof(a), "%llX", static_cast<unsigned long long>(addr));
    m += a;
    m += "\n  spec     : " + ps.note + (ps.verified ? " [VERIFIED]" : " [UNVERIFIED]");
    m += "\n  original : " + hex(original.data(), original.size());
    m += "\n  proposed : " + hex(ps.patch.data(), ps.patch.size());
    return m;
}

} // namespace

const std::vector<PatchSpec>& patch_specs() {
    // Intentionally empty until a signature is derived from the PDB-guided
    // disassembly of the exact termsrv.dll build. Keeping this empty guarantees
    // enable_multisession() cannot write anything by accident.
    static const std::vector<PatchSpec> specs{};
    return specs;
}

Result enable_multisession(bool apply) {
    Result r;

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

    std::string why;
    auto hit = locate_unique(buf, why);
    if (!hit) {
        CloseHandle(h);
        r.message = why;
        return r;
    }

    const PatchSpec& ps = patch_specs()[hit->spec];
    const uintptr_t addr = mod->base + hit->off;
    r.found = true;
    r.spec_used = ps.note;
    r.address = addr;
    r.original.assign(buf.begin() + hit->off, buf.begin() + hit->off + ps.sig.size());
    r.proposed = ps.patch;

    if (!apply) {
        r.message = report(ps, addr, r.original, "DRY-RUN: would patch");
        CloseHandle(h);
        return r;
    }

    if (!ps.verified) {
        r.message = report(ps, addr, r.original,
                           "REFUSING to write (spec not verified for this build)");
        CloseHandle(h);
        return r;
    }

    auto rec = proc::apply_patch(h, addr, ps.patch.data(), ps.patch.size());
    if (!rec) {
        r.message = report(ps, addr, r.original, "apply_patch FAILED");
        CloseHandle(h);
        return r;
    }

    r.applied = true;
    r.rollback.push_back(*rec);
    r.message = report(ps, addr, r.original, "PATCHED");
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

    std::string why;
    auto hit = locate_unique(buf, why);
    if (!hit) {
        r.message = why;
        return r;
    }

    const PatchSpec& ps = patch_specs()[hit->spec];
    r.found = true;
    r.spec_used = ps.note;
    r.address = hit->off;  // file offset here, not a VA
    r.original.assign(buf.begin() + hit->off, buf.begin() + hit->off + ps.sig.size());
    r.proposed = ps.patch;
    r.message = report(ps, hit->off, r.original, "FILE SCAN: unique match at file offset");
    return r;
}

bool revert(const Result& r) {
    if (r.rollback.empty()) return false;

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
