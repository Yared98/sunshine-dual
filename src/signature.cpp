#include "sunshinedual/signature.h"

#include <cctype>
#include <stdexcept>

namespace sd::scan {

namespace {

inline int hex_digit_to_val(char c) noexcept {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

} // namespace

Signature parse_ida(std::string_view pattern, std::string name) {
    std::vector<uint8_t> bytes;
    std::string mask;

    size_t i = 0;
    const size_t len = pattern.size();

    while (i < len) {
        while (i < len && std::isspace(static_cast<unsigned char>(pattern[i]))) {
            ++i;
        }
        if (i >= len) {
            break;
        }

        const size_t start = i;
        while (i < len && !std::isspace(static_cast<unsigned char>(pattern[i]))) {
            ++i;
        }
        std::string_view token = pattern.substr(start, i - start);

        if (token == "?" || token == "??") {
            bytes.push_back(0x00);
            mask.push_back('?');
        } else if (token.size() == 2) {
            int hi = hex_digit_to_val(token[0]);
            int lo = hex_digit_to_val(token[1]);
            if (hi < 0 || lo < 0) {
                throw std::invalid_argument("Invalid hex byte token in IDA pattern: " + std::string(token));
            }
            bytes.push_back(static_cast<uint8_t>((hi << 4) | lo));
            mask.push_back('x');
        } else {
            throw std::invalid_argument("Malformed token in IDA pattern: " + std::string(token));
        }
    }

    if (bytes.empty()) {
        throw std::invalid_argument("IDA pattern is empty or contains no byte tokens");
    }

    return Signature{std::move(bytes), std::move(mask), std::move(name)};
}

Signature from_bytes(std::string_view raw_bytes, std::string_view mask,
                     std::string name) {
    if (raw_bytes.size() != mask.size()) {
        throw std::invalid_argument("raw_bytes and mask length mismatch");
    }

    for (char c : mask) {
        if (c != 'x' && c != '?') {
            throw std::invalid_argument("mask must only contain 'x' or '?' characters");
        }
    }

    std::vector<uint8_t> bytes;
    bytes.reserve(raw_bytes.size());
    for (char c : raw_bytes) {
        bytes.push_back(static_cast<uint8_t>(c));
    }

    return Signature{std::move(bytes), std::string(mask), std::move(name)};
}

std::optional<size_t> find_first(const uint8_t* data, size_t size,
                                 const Signature& sig) {
    if (!sig.valid() || data == nullptr || size < sig.size()) {
        return std::nullopt;
    }

    const size_t sig_len = sig.size();
    const size_t max_off = size - sig_len;

    for (size_t off = 0; off <= max_off; ++off) {
        bool match = true;
        for (size_t i = 0; i < sig_len; ++i) {
            if (sig.mask[i] != '?' && data[off + i] != sig.bytes[i]) {
                match = false;
                break;
            }
        }
        if (match) {
            return off;
        }
    }

    return std::nullopt;
}

std::vector<size_t> find_all(const uint8_t* data, size_t size,
                             const Signature& sig) {
    if (!sig.valid() || data == nullptr || size < sig.size()) {
        return {};
    }

    std::vector<size_t> matches;
    const size_t sig_len = sig.size();
    const size_t max_off = size - sig_len;

    for (size_t off = 0; off <= max_off; ++off) {
        bool match = true;
        for (size_t i = 0; i < sig_len; ++i) {
            if (sig.mask[i] != '?' && data[off + i] != sig.bytes[i]) {
                match = false;
                break;
            }
        }
        if (match) {
            matches.push_back(off);
        }
    }

    return matches;
}

} // namespace sd::scan
