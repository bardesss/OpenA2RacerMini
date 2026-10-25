#pragma once
#include <cstddef>
#include <vector>

namespace a2 {
// Frame-time controller for the race world scale. Steps down one level after
// 2 consecutive frames over the budget and up one level after 30 consecutive
// frames under 70% of it; any other frame breaks both streaks.
class DynamicResolution {
public:
  explicit DynamicResolution(std::vector<float> steps = {1.0f, 0.75f, 0.5f},
                             double budget = 1.0 / 60);
  float update(double frameSeconds);
  float scale() const { return steps_[index_]; }
  void reset();

private:
  std::vector<float> steps_;
  double budget_;
  size_t index_ = 0;
  int slow_ = 0, fast_ = 0;
};
} // namespace a2
