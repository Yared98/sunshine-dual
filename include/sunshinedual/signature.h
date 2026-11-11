#pragma once
// Pure, portable byte-pattern scanning. No Win32, no external dependencies.
// This is the reusable core that locates a function's code "shape" inside a
// memory buffer regardless of its absolute address.

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace sd::scan {

// A byte signature with wildcards. For each index i, bytes[i] must match the
// target exactly when mask[i] == 'x', and is ignored when mask[i] == '?'.
struct Signature {
    std::vector<uint8_t> bytes;
    std::string          mask;  // same length as bytes; each char is 'x' or '?'
    std::string          name;  // human-readable id, for diagnostics/logging

    bool   valid() const { return !bytes.empty() && bytes.size() == mask.size(); }
    size_t size()  const { return bytes.size(); }
};

// Parse an IDA-style pattern string, e.g. "48 8B ?? C3" (also accepts single
// '?' as a wildcard). Hex bytes are case-insensitive. Throws
// std::invalid_argument on malformed input (odd nibble, bad token, empty).
Signature parse_ida(std::string_view pattern, std::string name = "");

// Build a signature from a raw byte string and a mask string, e.g.
// from_bytes("\x48\x8B\x00\xC3", "xx?x"). raw_bytes and mask must be the same
// length. Throws std::invalid_argument on mismatch.
Signature from_bytes(std::string_view raw_bytes, std::string_view mask,
                     std::string name = "");

// Offset of the first match of `sig` within [data, data+size), or std::nullopt.
std::optional<size_t> find_first(const uint8_t* data, size_t size,
                                 const Signature& sig);

// All match offsets of `sig` within [data, data+size), left to right.
std::vector<size_t> find_all(const uint8_t* data, size_t size,
                             const Signature& sig);

} // namespace sd::scan
