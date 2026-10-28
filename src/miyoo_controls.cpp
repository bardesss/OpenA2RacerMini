#include "miyoo_controls.hpp"

namespace a2 {
namespace {
// SDL2 SDL_SCANCODE_* values (SDL_scancode.h) of the keys the Miyoo kernel
// reports for its buttons. Kept as numbers so the core does not include SDL;
// main.cpp static_asserts them against SDL under A2_MIYOO.
constexpr int scancodeE = 8, scancodeT = 23, scancodeReturn = 40, scancodeEscape = 41,
              scancodeBackspace = 42, scancodeTab = 43, scancodeSpace = 44, scancodeRight = 79,
              scancodeLeft = 80, scancodeDown = 81, scancodeUp = 82, scancodeLCtrl = 224,
              scancodeLShift = 225, scancodeLAlt = 226, scancodeRCtrl = 228;
} // namespace

std::vector<MiyooCommand> MiyooControls::press(MiyooButton b, MiyooContext context) {
  held_[size_t(b)] = true;
  using B = MiyooButton;
  using C = MiyooCommand;
  if (b == B::Menu) {
    menuCombo_ = false;
    return {};
  }
  if ((b == B::R2 || b == B::L2) && held(B::Menu)) {
    menuCombo_ = true;
    if (context != MiyooContext::Race)
      return {};
    return {b == B::R2 ? C::QuickSave : C::QuickLoad};
  }
  switch (context) {
  case MiyooContext::Race:
    if (b == B::Y)
      return {C::CycleCamera};
    if (b == B::X)
      return {C::ToggleRadar};
    if (b == B::Start)
      return {held(B::Select) ? C::RestartStage : C::Pause};
    return {};
  case MiyooContext::Menu:
    switch (b) {
    case B::Up:
      return {C::Up};
    case B::Down:
      return {C::Down};
    case B::Left:
      return {C::Left};
    case B::Right:
      return {C::Right};
    case B::A:
    case B::Start:
      return {C::Confirm};
    case B::B:
      return {C::Back};
    default:
      return {};
    }
  case MiyooContext::Movie:
    if (b == B::A || b == B::B || b == B::Start)
      return {C::Confirm};
    return {};
  }
  return {};
}

std::vector<MiyooCommand> MiyooControls::release(MiyooButton b, MiyooContext context) {
  const bool wasHeld = held(b);
  held_[size_t(b)] = false;
  if (b != MiyooButton::Menu || !wasHeld)
    return {};
  if (menuCombo_) {
    menuCombo_ = false;
    return {};
  }
  return {context == MiyooContext::Race ? MiyooCommand::AutosaveAndExit : MiyooCommand::Exit};
}

MiyooContext miyooContextFor(MiyooButton b, bool inRace, bool fineShowing, bool inMovie) {
  if (inMovie)
    return MiyooContext::Movie;
  if (!inRace)
    return MiyooContext::Menu;
  if (fineShowing && (b == MiyooButton::A || b == MiyooButton::Start))
    return MiyooContext::Menu;
  return MiyooContext::Race;
}

std::optional<MiyooButton> miyooButtonFromScancode(int sdlScancode) {
  using B = MiyooButton;
  switch (sdlScancode) {
  case scancodeUp:
    return B::Up;
  case scancodeDown:
    return B::Down;
  case scancodeLeft:
    return B::Left;
  case scancodeRight:
    return B::Right;
  case scancodeSpace:
    return B::A;
  case scancodeLCtrl:
    return B::B;
  case scancodeLShift:
    return B::X;
  case scancodeLAlt:
    return B::Y;
  case scancodeE:
    return B::L1;
  case scancodeT:
    return B::R1;
  case scancodeTab:
    return B::L2;
  case scancodeBackspace:
    return B::R2;
  case scancodeReturn:
    return B::Start;
  case scancodeRCtrl:
    return B::Select;
  case scancodeEscape:
    return B::Menu;
  default:
    return std::nullopt;
  }
}
} // namespace a2
