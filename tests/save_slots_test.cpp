#include "save_slots.hpp"
#include <chrono>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>

using namespace a2;
namespace fs = std::filesystem;
namespace {
void check(bool ok, const char *message) {
  if (!ok)
    throw std::runtime_error(message);
}
struct Directory {
  fs::path path = fs::temp_directory_path() /
                  ("a2-save-slots-" +
                   std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
  Directory() { fs::create_directories(path); }
  ~Directory() {
    std::error_code ignored;
    fs::permissions(path, fs::perms::owner_all, fs::perm_options::add, ignored);
    fs::remove_all(path, ignored);
  }
};
std::string read(const fs::path &path) {
  std::ifstream file(path, std::ios::binary);
  return std::string(std::istreambuf_iterator<char>(file), {});
}
fs::path temp(fs::path target) {
  target += ".tmp";
  return target;
}
void paths() {
  const fs::path d = "saves";
  check(slotPath(d, {SlotKind::Manual, 0}) == d / "slot0.sav", "Manual 0 is slot0.sav");
  check(slotPath(d, {SlotKind::Manual, 9}) == d / "slot9.sav", "Manual 9 is slot9.sav");
  check(slotPath(d, {SlotKind::Autosave}) == d / "autosave.sav", "Autosave is autosave.sav");
  for (int i = 0; i < 10; ++i)
    check(slotPath(d, {SlotKind::Autosave}) != slotPath(d, {SlotKind::Manual, i}),
          "Autosave never shares a manual slot");
}
void writesContent() {
  Directory dir;
  std::string error;
  const auto target = dir.path / "fresh" / "autosave.sav";
  check(writeAtomically(
            target, [](std::ostream &out) { out << "first"; }, error),
        "Fresh write succeeds");
  check(error.empty(), "Successful write leaves no error");
  check(read(target) == "first", "Fresh write stores the content");
  check(writeAtomically(
            target, [](std::ostream &out) { out << "second"; }, error),
        "Overwrite succeeds");
  check(read(target) == "second", "Overwrite replaces the content");
  check(!fs::exists(temp(target)), "Successful write removes the temporary file");
}
void throwingWriterKeepsTarget() {
  Directory dir;
  const auto target = dir.path / "autosave.sav";
  {
    std::ofstream file(target, std::ios::binary);
    file << "previous autosave\n";
  }
  std::string error;
  check(!writeAtomically(
            target,
            [](std::ostream &out) {
              out << "partial";
              throw std::runtime_error("writer failed");
            },
            error),
        "Throwing writer reports failure");
  check(!error.empty(), "Throwing writer sets an error");
  check(read(target) == "previous autosave\n", "Throwing writer leaves the target intact");
  check(!fs::exists(temp(target)), "Throwing writer leaves no temporary file");
}
void unwritableDirectory() {
  Directory dir;
  // A regular file where the directory should be: unwritable even for root.
  const auto blocker = dir.path / "not-a-directory";
  {
    std::ofstream file(blocker);
    file << "x";
  }
  std::string error;
  check(!writeAtomically(
            blocker / "saves" / "autosave.sav", [](std::ostream &out) { out << "data"; }, error),
        "Write below a file fails");
  check(!error.empty(), "Write below a file reports an error");

  // A read-only directory (SD card mounted read-only). Root and Windows ignore
  // the permission bits, so this case only runs where they are enforced.
  const auto locked = dir.path / "locked";
  fs::create_directories(locked);
  const auto target = locked / "autosave.sav";
  {
    std::ofstream file(target, std::ios::binary);
    file << "previous autosave\n";
  }
  fs::permissions(locked, fs::perms::owner_read | fs::perms::owner_exec);
  const bool enforced = !std::ofstream(locked / "probe");
  if (enforced) {
    error.clear();
    check(!writeAtomically(
              target, [](std::ostream &out) { out << "new"; }, error),
          "Write into a read-only directory fails");
    check(!error.empty(), "Read-only directory reports an error");
    check(read(target) == "previous autosave\n", "Read-only directory keeps the old autosave");
  }
  fs::permissions(locked, fs::perms::owner_all);
}
} // namespace
int main() {
  try {
    paths();
    writesContent();
    throwingWriterKeepsTarget();
    unwritableDirectory();
    std::cout << "Save slots: slot paths, dedicated autosave and atomic writes passed\n";
    return 0;
  } catch (const std::exception &e) {
    std::cerr << "Save slots test failed: " << e.what() << '\n';
    return 1;
  }
}
