#include <cstdio>
#include <cstring>
#include <string>

#include "sunshinedual/patcher.h"

static int usage() {
    std::puts(
        "sunshine-dual - multi-session enabler (dry-run first)\n"
        "usage:\n"
        "  sunshine_dual scan-file <path-to-termsrv.dll>  offline: locate the target, no admin, no write\n"
        "  sunshine_dual dry-run                          live TermService: locate + report, no write\n"
        "  sunshine_dual patch                            live: write ONLY if a verified spec matches (needs admin)\n");
    return 2;
}

int wmain(int argc, wchar_t** argv) {
    if (argc < 2) return usage();
    const std::wstring cmd = argv[1];

    if (cmd == L"scan-file") {
        if (argc < 3) return usage();
        auto r = sd::patch::scan_image_file(argv[2]);
        std::printf("%s\n", r.message.c_str());
        return r.found ? 0 : 1;
    }
    if (cmd == L"dry-run") {
        auto r = sd::patch::enable_multisession(/*apply=*/false);
        std::printf("%s\n", r.message.c_str());
        return r.found ? 0 : 1;
    }
    if (cmd == L"patch") {
        auto r = sd::patch::enable_multisession(/*apply=*/true);
        std::printf("%s\n", r.message.c_str());
        return r.applied ? 0 : 1;
    }
    return usage();
}
