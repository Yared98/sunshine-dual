#pragma once
// Minimal dependency-free test harness. Include this, write checks, and return
// SD_TEST_SUMMARY() from main().
#include <cstdio>

namespace sdtest {
inline int& failures() { static int f = 0; return f; }
inline int& checks()   { static int c = 0; return c; }
} // namespace sdtest

#define SD_CHECK(cond)                                                        \
    do {                                                                      \
        ++::sdtest::checks();                                                 \
        if (!(cond)) {                                                        \
            ++::sdtest::failures();                                           \
            std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        }                                                                     \
    } while (0)

#define SD_CHECK_EQ(a, b)                                                     \
    do {                                                                      \
        ++::sdtest::checks();                                                 \
        if (!((a) == (b))) {                                                  \
            ++::sdtest::failures();                                           \
            std::fprintf(stderr, "FAIL %s:%d: %s == %s\n", __FILE__, __LINE__, #a, #b); \
        }                                                                     \
    } while (0)

#define SD_TEST_SUMMARY()                                                     \
    (std::fprintf(stderr, "%d/%d checks passed\n",                            \
                  ::sdtest::checks() - ::sdtest::failures(),                  \
                  ::sdtest::checks()),                                        \
     ::sdtest::failures() == 0 ? 0 : 1)
