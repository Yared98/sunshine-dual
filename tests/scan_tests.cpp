#include "test_harness.h"
#include "sunshinedual/signature.h"

#include <vector>
#include <string>
#include <string_view>
#include <optional>
#include <stdexcept>

static void test_parse_ida_valid() {
    // Standard pattern with ??
    {
        auto sig = sd::scan::parse_ida("48 8B ?? C3", "test_sig");
        SD_CHECK(sig.valid());
        SD_CHECK_EQ(sig.size(), 4u);
        SD_CHECK_EQ(sig.name, "test_sig");
        SD_CHECK_EQ(sig.mask, "xx?x");
        const std::vector<uint8_t> expected = {0x48, 0x8B, 0x00, 0xC3};
        SD_CHECK(sig.bytes == expected);
    }

    // Single '?' as wildcard, lowercase hex, irregular whitespace
    {
        auto sig = sd::scan::parse_ida("  \t48   8b  ?   c3  \n");
        SD_CHECK(sig.valid());
        SD_CHECK_EQ(sig.size(), 4u);
        SD_CHECK_EQ(sig.mask, "xx?x");
        const std::vector<uint8_t> expected = {0x48, 0x8B, 0x00, 0xC3};
        SD_CHECK(sig.bytes == expected);
    }

    // Pattern with only wildcards
    {
        auto sig = sd::scan::parse_ida("? ?? ?");
        SD_CHECK(sig.valid());
        SD_CHECK_EQ(sig.size(), 3u);
        SD_CHECK_EQ(sig.mask, "???");
        const std::vector<uint8_t> expected = {0x00, 0x00, 0x00};
        SD_CHECK(sig.bytes == expected);
    }

    // Full range hex bytes
    {
        auto sig = sd::scan::parse_ida("00 7F 80 FF");
        SD_CHECK(sig.valid());
        SD_CHECK_EQ(sig.size(), 4u);
        SD_CHECK_EQ(sig.mask, "xxxx");
        const std::vector<uint8_t> expected = {0x00, 0x7F, 0x80, 0xFF};
        SD_CHECK(sig.bytes == expected);
    }
}

static void test_parse_ida_invalid() {
    auto check_throws = [](std::string_view pat) {
        bool threw = false;
        try {
            (void)sd::scan::parse_ida(pat);
        } catch (const std::invalid_argument&) {
            threw = true;
        }
        SD_CHECK(threw);
    };

    // Empty or whitespace only
    check_throws("");
    check_throws("   ");
    check_throws("\t\n\r");

    // Odd nibbles
    check_throws("4");
    check_throws("48 8 C3");
    check_throws("48 8B C");

    // Bad tokens
    check_throws("48 8B 123");
    check_throws("???");
    check_throws("????");
    check_throws("0x48 8B");
    check_throws("ZZ 8B");
    check_throws("48 ?A");
    check_throws("48 A?");
    check_throws("48-8B");
}

static void test_from_bytes_valid() {
    using namespace std::string_view_literals;
    std::string_view raw = "\x48\x8B\x00\xC3"sv;
    auto sig = sd::scan::from_bytes(raw, "xx?x", "from_bytes_test");
    SD_CHECK(sig.valid());
    SD_CHECK_EQ(sig.size(), 4u);
    SD_CHECK_EQ(sig.name, "from_bytes_test");
    SD_CHECK_EQ(sig.mask, "xx?x");
    const std::vector<uint8_t> expected = {0x48, 0x8B, 0x00, 0xC3};
    SD_CHECK(sig.bytes == expected);
}

static void test_from_bytes_invalid() {
    auto check_throws = [](std::string_view raw, std::string_view mask) {
        bool threw = false;
        try {
            (void)sd::scan::from_bytes(raw, mask);
        } catch (const std::invalid_argument&) {
            threw = true;
        }
        SD_CHECK(threw);
    };

    // Mismatched size
    check_throws("\x48\x8B", "x");
    check_throws("\x48", "xx");
    check_throws("\x48\x8B\xC3", "xx");

    // Mask must only accept 'x' and '?'
    check_throws("\x48\x8B", "xX");
    check_throws("\x48\x8B", "x.");
    check_throws("\x48\x8B", "x ");
    check_throws("\x48\x8B", "x0");
    check_throws("\x48\x8B", "x*");
}

static void test_find_first() {
    const std::vector<uint8_t> data = {
        0x90, 0x90, 0x48, 0x8B, 0x05, 0xC3, 0x90, 0x90,
        0x48, 0x8B, 0xFF, 0xC3, 0xCC, 0xCC, 0xAA, 0xBB
    };

    // Match at beginning
    {
        auto sig = sd::scan::parse_ida("90 90 48");
        auto off = sd::scan::find_first(data.data(), data.size(), sig);
        SD_CHECK(off.has_value());
        SD_CHECK_EQ(*off, 0u);
    }

    // Match in the middle with wildcard
    {
        auto sig = sd::scan::parse_ida("48 8B ?? C3");
        auto off = sd::scan::find_first(data.data(), data.size(), sig);
        SD_CHECK(off.has_value());
        SD_CHECK_EQ(*off, 2u);
    }

    // Match at the very end
    {
        auto sig = sd::scan::parse_ida("CC AA BB");
        auto off = sd::scan::find_first(data.data(), data.size(), sig);
        SD_CHECK(off.has_value());
        SD_CHECK_EQ(*off, 13u);
    }

    // No match
    {
        auto sig = sd::scan::parse_ida("DE AD BE EF");
        auto off = sd::scan::find_first(data.data(), data.size(), sig);
        SD_CHECK(!off.has_value());
    }

    // Signature size greater than buffer
    {
        const std::vector<uint8_t> small_data = {0x48, 0x8B};
        auto sig = sd::scan::parse_ida("48 8B C3");
        auto off = sd::scan::find_first(small_data.data(), small_data.size(), sig);
        SD_CHECK(!off.has_value());
    }

    // Null data pointer or zero size
    {
        auto sig = sd::scan::parse_ida("48 8B");
        auto off1 = sd::scan::find_first(nullptr, 10, sig);
        SD_CHECK(!off1.has_value());
        auto off2 = sd::scan::find_first(data.data(), 0, sig);
        SD_CHECK(!off2.has_value());
    }

    // Invalid signature (default-constructed)
    {
        sd::scan::Signature invalid_sig{};
        auto off = sd::scan::find_first(data.data(), data.size(), invalid_sig);
        SD_CHECK(!off.has_value());
    }

    // Exact full buffer match
    {
        const std::vector<uint8_t> exact_data = {0x01, 0x02, 0x03};
        auto sig = sd::scan::parse_ida("01 ?? 03");
        auto off = sd::scan::find_first(exact_data.data(), exact_data.size(), sig);
        SD_CHECK(off.has_value());
        SD_CHECK_EQ(*off, 0u);
    }
}

static void test_find_all_and_overlapping() {
    // Overlapping matches: "AA AA" in "AA AA AA AA"
    {
        const std::vector<uint8_t> data = {0xAA, 0xAA, 0xAA, 0xAA};
        auto sig = sd::scan::parse_ida("AA AA");
        auto matches = sd::scan::find_all(data.data(), data.size(), sig);
        const std::vector<size_t> expected = {0, 1, 2};
        SD_CHECK(matches == expected);
    }

    // Multiple non-overlapping matches
    {
        const std::vector<uint8_t> data = {
            0x48, 0x8B, 0x01, 0xC3,
            0x90, 0x90,
            0x48, 0x8B, 0x02, 0xC3,
            0xCC,
            0x48, 0x8B, 0x03, 0xC3
        };
        auto sig = sd::scan::parse_ida("48 8B ?? C3");
        auto matches = sd::scan::find_all(data.data(), data.size(), sig);
        const std::vector<size_t> expected = {0, 6, 11};
        SD_CHECK(matches == expected);
    }

    // No matches returns empty vector
    {
        const std::vector<uint8_t> data = {0x01, 0x02, 0x03};
        auto sig = sd::scan::parse_ida("FF FF");
        auto matches = sd::scan::find_all(data.data(), data.size(), sig);
        SD_CHECK(matches.empty());
    }

    // Buffer smaller than sig returns empty vector
    {
        const std::vector<uint8_t> data = {0xAA};
        auto sig = sd::scan::parse_ida("AA AA");
        auto matches = sd::scan::find_all(data.data(), data.size(), sig);
        SD_CHECK(matches.empty());
    }

    // Invalid signature returns empty vector
    {
        const std::vector<uint8_t> data = {0xAA, 0xAA};
        sd::scan::Signature invalid_sig{};
        auto matches = sd::scan::find_all(data.data(), data.size(), invalid_sig);
        SD_CHECK(matches.empty());
    }

    // Null pointer data returns empty vector
    {
        auto sig = sd::scan::parse_ida("AA");
        auto matches = sd::scan::find_all(nullptr, 5, sig);
        SD_CHECK(matches.empty());
    }
}

int main() {
    test_parse_ida_valid();
    test_parse_ida_invalid();
    test_from_bytes_valid();
    test_from_bytes_invalid();
    test_find_first();
    test_find_all_and_overlapping();

    return SD_TEST_SUMMARY();
}
