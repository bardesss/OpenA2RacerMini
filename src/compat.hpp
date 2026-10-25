#pragma once
#include <cstddef>
#include <cstring>
#include <string>
#include <type_traits>
// Feature-test macros: <version> exists from GCC 9 / Clang 7 / MSVC 2019.
// Without it (GCC 8) none of the C++20 library features below are assumed.
#if defined(__has_include)
#if __has_include(<version>)
#include <version>
#endif
#endif
#if defined(__cpp_lib_span)
#include <span>
#endif
#if defined(__cpp_lib_bit_cast)
#include <bit>
#endif

namespace a2 {
#if defined(__cpp_lib_bit_cast)
template <class To, class From> constexpr To bitCast(const From &from) noexcept {
  return std::bit_cast<To>(from);
}
#else
// memcpy-based std::bit_cast replacement (GCC 8).
template <class To, class From> To bitCast(const From &from) noexcept {
  static_assert(sizeof(To) == sizeof(From), "bitCast requires equal sizes");
  static_assert(std::is_trivially_copyable<To>::value && std::is_trivially_copyable<From>::value,
                "bitCast requires trivially copyable types");
  To to;
  std::memcpy(&to, &from, sizeof(To));
  return to;
}
#endif

#if defined(__cpp_lib_span)
template <class T> using span = std::span<T>;
#else
// Minimal dynamic-extent std::span stand-in for C++17 toolchains (GCC 8).
template <class T> class span {
public:
  using element_type = T;
  using iterator = T *;
  constexpr span() noexcept = default;
  constexpr span(T *data, size_t size) noexcept : data_(data), size_(size) {}
  template <class C, class = std::enable_if_t<std::is_convertible<
                         std::remove_pointer_t<decltype(std::declval<C &>().data())> (*)[], T (*)[]>::value>>
  constexpr span(C &c) noexcept : data_(c.data()), size_(c.size()) {}
  template <class U, class = std::enable_if_t<std::is_convertible<U (*)[], T (*)[]>::value>>
  constexpr span(const span<U> &o) noexcept : data_(o.data()), size_(o.size()) {}
  constexpr T *data() const noexcept { return data_; }
  constexpr size_t size() const noexcept { return size_; }
  constexpr bool empty() const noexcept { return size_ == 0; }
  constexpr T &operator[](size_t i) const noexcept { return data_[i]; }
  constexpr T *begin() const noexcept { return data_; }
  constexpr T *end() const noexcept { return data_ + size_; }
  constexpr span first(size_t n) const noexcept { return {data_, n}; }
  constexpr span subspan(size_t off, size_t n) const noexcept { return {data_ + off, n}; }

private:
  T *data_ = nullptr;
  size_t size_ = 0;
};
#endif

// Associative-container contains() (C++20) for C++17 toolchains.
template <class Map, class Key> bool contains(const Map &m, const Key &k) { return m.find(k) != m.end(); }
// std::string::ends_with (C++20) for C++17 toolchains.
inline bool endsWith(const std::string &s, const std::string &suffix) {
#if defined(__cpp_lib_starts_ends_with)
  return s.ends_with(suffix);
#else
  return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
#endif
}
} // namespace a2
