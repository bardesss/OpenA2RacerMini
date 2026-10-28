#pragma once
#include <filesystem>
#include <functional>
#include <ostream>
#include <string>

namespace a2 {
enum class SlotKind { Manual, Autosave };
// Manual slots are 0-9 (quick save is Manual 0, as upstream). The index is
// ignored for the single Autosave slot.
struct SlotId {
  SlotKind kind;
  int index = 0;
};
// slot<N>.sav for Manual (upstream naming), autosave.sav for Autosave.
std::filesystem::path slotPath(const std::filesystem::path &saveDir, SlotId slot);
// Creates the parent directory if needed, writes target.tmp through `write`
// and renames it over `target`. On any failure (including `write` throwing)
// it returns false with a message in `error`, leaves `target` untouched and
// removes the temporary file.
bool writeAtomically(const std::filesystem::path &target,
                     const std::function<void(std::ostream &)> &write, std::string &error);
} // namespace a2
