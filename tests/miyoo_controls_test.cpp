#include "miyoo_controls.hpp"
#include <iostream>
#include <stdexcept>
#include <utility>

using namespace a2;
namespace {
using B = MiyooButton;
using C = MiyooCommand;
using Commands = std::vector<MiyooCommand>;
constexpr MiyooContext race = MiyooContext::Race, menu = MiyooContext::Menu,
                       movie = MiyooContext::Movie;

void check(bool ok, const char *message) {
  if (!ok)
    throw std::runtime_error(message);
}
// One press immediately followed by its release, both in `context`.
Commands tap(MiyooControls &c, MiyooButton b, MiyooContext context) {
  Commands out = c.press(b, context);
  check(c.held(b), "Pressed button is not held");
  Commands up = c.release(b, context);
  check(!c.held(b), "Released button is still held");
  out.insert(out.end(), up.begin(), up.end());
  return out;
}

void raceButtons() {
  MiyooControls c;
  check(c.press(B::A, race).empty(), "Race A must not emit a command (gas is polled)");
  check(c.release(B::A, race).empty(), "Race A release emitted a command");
  check(tap(c, B::B, race).empty(), "Race B must not emit a command (brake is polled)");
  check(tap(c, B::R1, race).empty(), "Race R1 must not emit a command (handbrake is polled)");
  check(tap(c, B::Left, race).empty(), "Race D-pad must not emit a command (steer is polled)");
  check(tap(c, B::Y, race) == Commands{C::CycleCamera}, "Race Y must cycle the camera");
  check(tap(c, B::X, race) == Commands{C::ToggleRadar}, "Race X must toggle the radar");
  check(tap(c, B::Start, race) == Commands{C::Pause}, "Race Start must pause");
  for (B unassigned : {B::L1, B::L2, B::R2, B::Select})
    check(tap(c, unassigned, race).empty(), "Unassigned race button emitted a command");
}
void selectStartRestarts() {
  MiyooControls c;
  check(c.press(B::Select, race).empty(), "Select alone emitted a command");
  check(c.press(B::Start, race) == Commands{C::RestartStage},
        "Select + Start must restart the stage without pausing");
  check(c.release(B::Start, race).empty(), "Start release emitted a command");
  check(c.release(B::Select, race).empty(), "Select release emitted a command");
  check(tap(c, B::Start, race) == Commands{C::Pause}, "Start after Select release must pause");
}
void menuAloneAutosavesOnRelease() {
  MiyooControls c;
  check(c.press(B::Menu, race).empty(), "Menu press must wait for the release");
  check(c.held(B::Menu), "Menu is not held");
  check(c.release(B::Menu, race) == Commands{C::AutosaveAndExit},
        "Menu release in a race must autosave and exit");
}
void menuCombos() {
  for (auto [shoulder, command] :
       {std::pair{B::R2, C::QuickSave}, std::pair{B::L2, C::QuickLoad}}) {
    MiyooControls c;
    check(c.press(B::Menu, race).empty(), "Menu press emitted a command");
    check(c.press(shoulder, race) == Commands{command}, "Menu + shoulder combo wrong command");
    check(c.release(shoulder, race).empty(), "Shoulder release emitted a command");
    check(c.release(B::Menu, race).empty(), "Menu release after a combo must not exit");
    // The combo is forgotten afterwards: the next lone Menu tap exits again.
    check(tap(c, B::Menu, race) == Commands{C::AutosaveAndExit},
          "Lone Menu tap after a combo must autosave and exit");
  }
  MiyooControls c;
  c.press(B::Menu, race);
  check(c.press(B::R2, race) == Commands{C::QuickSave}, "First quick save missing");
  c.release(B::R2, race);
  check(c.press(B::R2, race) == Commands{C::QuickSave}, "Repeated quick save while Menu held");
  c.release(B::R2, race);
  check(c.release(B::Menu, race).empty(), "Menu release after repeated combos must not exit");
}
void menuContext() {
  MiyooControls c;
  check(tap(c, B::A, menu) == Commands{C::Confirm}, "Menu A must confirm");
  check(tap(c, B::B, menu) == Commands{C::Back}, "Menu B must go back");
  check(tap(c, B::Up, menu) == Commands{C::Up}, "Menu Up wrong");
  check(tap(c, B::Down, menu) == Commands{C::Down}, "Menu Down wrong");
  check(tap(c, B::Left, menu) == Commands{C::Left}, "Menu Left wrong");
  check(tap(c, B::Right, menu) == Commands{C::Right}, "Menu Right wrong");
  check(c.press(B::Menu, menu).empty(), "Menu press in a menu emitted a command");
  check(c.release(B::Menu, menu) == Commands{C::Exit}, "Menu release in a menu must exit");
}
void movieContext() {
  MiyooControls c;
  check(tap(c, B::A, movie) == Commands{C::Confirm}, "Movie A must skip");
  check(tap(c, B::B, movie) == Commands{C::Confirm}, "Movie B must skip");
  check(c.press(B::Menu, movie).empty(), "Menu press in a movie emitted a command");
  check(c.release(B::Menu, movie) == Commands{C::Exit}, "Menu release in a movie must exit");
}
void fineDialog() {
  // The glue passes MiyooContext::Menu while a fine dialog is open.
  MiyooControls c;
  check(c.press(B::A, menu) == Commands{C::Confirm}, "A must dismiss the fine dialog");
}
void releaseWithoutPress() {
  // A Menu still held from before the game started must not exit on release.
  MiyooControls c;
  check(c.release(B::Menu, race).empty(), "Unseen Menu press exited on release");
  check(c.release(B::Menu, menu).empty(), "Unseen Menu press exited on release");
}
void scancodes() {
  // SDL2 SDL_SCANCODE_* values of the Miyoo evdev keys.
  const std::pair<int, MiyooButton> table[] = {
      {82, B::Up},      {81, B::Down},  {80, B::Left},     {79, B::Right},  {44, B::A},
      {224, B::B},      {225, B::X},    {226, B::Y},       {8, B::L1},      {23, B::R1},
      {43, B::L2},      {42, B::R2},    {40, B::Start},    {228, B::Select}, {41, B::Menu}};
  for (auto [code, button] : table)
    check(miyooButtonFromScancode(code) == button, "Scancode maps to the wrong button");
  for (int unrelated : {0, 4, 26, 58, 229, 512})
    check(!miyooButtonFromScancode(unrelated), "Unrelated scancode mapped to a button");
}
} // namespace

int main() {
  try {
    raceButtons();
    selectStartRestarts();
    menuAloneAutosavesOnRelease();
    menuCombos();
    menuContext();
    movieContext();
    fineDialog();
    releaseWithoutPress();
    scancodes();
    std::cout << "Miyoo controls: race, menu and movie buttons, Select+Start, Menu combos and "
                 "scancode table passed\n";
    return 0;
  } catch (const std::exception &e) {
    std::cerr << "Miyoo controls test failed: " << e.what() << '\n';
    return 1;
  }
}
