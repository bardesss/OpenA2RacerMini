#include "compat.hpp"
#include <cstdint>
#include <stdexcept>

using namespace a2;
namespace {
void check(bool v, const char *message) {
  if (!v)
    throw std::runtime_error(message);
}
} // namespace

int main() {
  check(bitCast<float>(uint32_t(0x3f800000)) == 1.0f, "bitCast uint32 -> float");
  check(bitCast<int16_t>(uint16_t(0xffff)) == -1, "bitCast uint16 -> int16");
  check(bitCast<uint32_t>(-0.0f) == 0x80000000u, "bitCast negative zero");
  return 0;
}
