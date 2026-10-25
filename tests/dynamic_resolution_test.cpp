#include "dynamic_resolution.hpp"
#include <iostream>
#include <stdexcept>

using namespace a2;
namespace {
void check(bool ok, const char *message) {
  if (!ok)
    throw std::runtime_error(message);
}
constexpr double slow = 0.020, fast = 0.010, steady = 0.015;
void stepsDownAndUp() {
  DynamicResolution d;
  check(d.scale() == 1.0f, "Starts at 1.0");
  check(d.update(slow) == 1.0f, "One slow frame keeps 1.0");
  check(d.update(slow) == 0.75f, "Two slow frames step down to 0.75");
  d.update(slow);
  check(d.update(slow) == 0.5f, "Two more slow frames step down to 0.5");
  for (int i = 0; i < 10; ++i)
    d.update(slow);
  check(d.scale() == 0.5f, "Never below the last step");
  for (int i = 0; i < 29; ++i)
    check(d.update(fast) == 0.5f, "29 fast frames keep the scale");
  check(d.update(fast) == 0.75f, "The 30th fast frame steps up");
  for (int i = 0; i < 15; ++i)
    d.update(fast);
  check(d.update(slow) == 0.75f, "A single slow frame does not step down");
  for (int i = 0; i < 29; ++i)
    check(d.update(fast) == 0.75f, "A slow frame resets the fast counter");
  check(d.update(fast) == 1.0f, "30 fast frames after the slow one step up");
  for (int i = 0; i < 40; ++i)
    d.update(fast);
  check(d.scale() == 1.0f, "Never above the first step");
}
void inBetweenFramesBreakStreaks() {
  DynamicResolution d;
  d.update(slow);
  d.update(steady);
  check(d.update(slow) == 1.0f, "Slow frames must be consecutive");
  d.update(slow);
  check(d.scale() == 0.75f, "Two consecutive slow frames step down");
  for (int i = 0; i < 20; ++i)
    d.update(fast);
  d.update(steady);
  for (int i = 0; i < 29; ++i)
    d.update(fast);
  check(d.scale() == 0.75f, "Fast frames must be consecutive");
  d.reset();
  check(d.scale() == 1.0f, "Reset returns to the first step");
}
void customSteps() {
  DynamicResolution d({1.0f, 0.5f}, 1.0 / 30);
  d.update(0.030);
  check(d.update(0.030) == 1.0f, "Frames within the budget keep the scale");
  d.update(0.040);
  check(d.update(0.040) == 0.5f, "Custom budget and steps");
}
} // namespace
int main() {
  try {
    stepsDownAndUp();
    inBetweenFramesBreakStreaks();
    customSteps();
    std::cout << "Dynamic resolution checks passed\n";
    return 0;
  } catch (const std::exception &e) {
    std::cerr << e.what() << "\n";
    return 1;
  }
}
