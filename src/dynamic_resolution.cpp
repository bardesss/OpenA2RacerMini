#include "dynamic_resolution.hpp"
#include <utility>

namespace a2 {
namespace {
constexpr int stepDownAfter = 2, stepUpAfter = 30;
constexpr double fastShare = 0.7;
} // namespace
DynamicResolution::DynamicResolution(std::vector<float> steps, double budget)
    : steps_(std::move(steps)), budget_(budget) {
  if (steps_.empty())
    steps_.push_back(1.0f);
}
float DynamicResolution::update(double frameSeconds) {
  if (frameSeconds > budget_) {
    fast_ = 0;
    if (++slow_ >= stepDownAfter) {
      slow_ = 0;
      if (index_ + 1 < steps_.size())
        ++index_;
    }
  } else if (frameSeconds < fastShare * budget_) {
    slow_ = 0;
    if (++fast_ >= stepUpAfter) {
      fast_ = 0;
      if (index_ > 0)
        --index_;
    }
  } else {
    slow_ = fast_ = 0;
  }
  return scale();
}
void DynamicResolution::reset() {
  index_ = 0;
  slow_ = fast_ = 0;
}
} // namespace a2
