#include "save_slots.hpp"
#include <fstream>
#include <stdexcept>
#include <system_error>

namespace a2 {
std::filesystem::path slotPath(const std::filesystem::path &saveDir, SlotId slot) {
  if (slot.kind == SlotKind::Autosave)
    return saveDir / "autosave.sav";
  if (slot.index < 0 || slot.index >= 10)
    throw std::invalid_argument("Invalid save slot");
  return saveDir / ("slot" + std::to_string(slot.index) + ".sav");
}

bool writeAtomically(const std::filesystem::path &target,
                     const std::function<void(std::ostream &)> &write, std::string &error) {
  namespace fs = std::filesystem;
  auto temp = target;
  temp += ".tmp";
  std::error_code ec;
  try {
    if (target.has_parent_path()) {
      fs::create_directories(target.parent_path(), ec);
      if (ec)
        throw std::runtime_error("Cannot create save directory: " + ec.message());
    }
    {
      std::ofstream f(temp); // Text mode, as upstream saves.
      if (!f)
        throw std::runtime_error("Cannot create save file");
      write(f);
      f.flush();
      if (!f)
        throw std::runtime_error("Cannot write save file");
      f.close();
      if (!f)
        throw std::runtime_error("Cannot write save file");
    }
    fs::rename(temp, target, ec);
    if (ec) {
      // Some file systems refuse to rename over an existing file.
      ec.clear();
      fs::copy_file(temp, target, fs::copy_options::overwrite_existing, ec);
      if (ec)
        throw std::runtime_error("Cannot replace save file: " + ec.message());
      fs::remove(temp, ec);
    }
    error.clear();
    return true;
  } catch (const std::exception &e) {
    error = e.what();
  } catch (...) {
    error = "Unknown error while saving";
  }
  fs::remove(temp, ec);
  return false;
}
} // namespace a2
