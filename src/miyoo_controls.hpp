#pragma once
#include <array>
#include <cstddef>
#include <optional>
#include <vector>

namespace a2 {
// Physical buttons of the Miyoo Mini Plus / Mini Flip.
enum class MiyooButton { Up, Down, Left, Right, A, B, X, Y, L1, L2, R1, R2, Start, Select, Menu };
// Race = Page::Playing, including paused and the fine dialog. MiyooControls
// does not know about fines; miyooContextFor() below picks the context.
enum class MiyooContext { Race, Menu, Movie };
enum class MiyooCommand {
  Up,
  Down,
  Left,
  Right,
  Confirm,
  Back,
  Pause,
  CycleCamera,
  ToggleRadar,
  RestartStage,
  QuickSave,
  QuickLoad,
  AutosaveAndExit,
  Exit
};

// Turns button presses into discrete commands. Driving (gas, brake, steer,
// handbrake) is not handled here: the game polls held keys for it, so the
// BEDIENING remapping keeps working.
//
// Race:  Y = CycleCamera, X = ToggleRadar, Start = Pause, Select + Start =
//        RestartStage (no Pause). D-pad, A, B, R1 emit nothing.
// Menu:  D-pad = directions, A and Start = Confirm, B = Back.
// Movie: A, B and Start = Confirm (skip).
// Menu button: acts on release. Alone it emits AutosaveAndExit in a race and
// Exit elsewhere. Menu + R2 / Menu + L2 emit QuickSave / QuickLoad in a race
// (nothing elsewhere) and cancel the exit of that Menu press. A release whose
// press was never seen (e.g. held at launch) emits nothing.
// L1, and L2/R2 without Menu, are unassigned.
class MiyooControls {
public:
  std::vector<MiyooCommand> press(MiyooButton, MiyooContext);
  std::vector<MiyooCommand> release(MiyooButton, MiyooContext);
  bool held(MiyooButton b) const { return held_[size_t(b)]; }

private:
  std::array<bool, size_t(MiyooButton::Menu) + 1> held_{};
  bool menuCombo_ = false;
};

// Context for one button: Movie while a movie plays, Menu outside a race.
// In a race with a fine dialog showing, A and Start get Menu (Confirm
// dismisses the fine). Every other button stays Race: Menu and L2/R2 still
// autosave / quick save, and B (brake) and the D-pad emit nothing, so they
// can't leave the race.
MiyooContext miyooContextFor(MiyooButton, bool inRace, bool fineShowing, bool inMovie);

// Maps an SDL2 SDL_SCANCODE_* value of the Miyoo evdev keyboard to a button.
// Plain int keeps the core SDL-free.
std::optional<MiyooButton> miyooButtonFromScancode(int sdlScancode);
} // namespace a2
