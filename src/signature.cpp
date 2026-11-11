#include "sunshinedual/signature.h"

#include <stdexcept>

// SCAFFOLD STUB — implemented by worker task 01 (docs/worker-tasks/task-01-patternscan.md).
namespace sd::scan {

Signature parse_ida(std::string_view, std::string) {
    throw std::logic_error("sd::scan::parse_ida not implemented");
}

Signature from_bytes(std::string_view, std::string_view, std::string) {
    throw std::logic_error("sd::scan::from_bytes not implemented");
}

std::optional<size_t> find_first(const uint8_t*, size_t, const Signature&) {
    return std::nullopt;
}

std::vector<size_t> find_all(const uint8_t*, size_t, const Signature&) {
    return {};
}

} // namespace sd::scan
