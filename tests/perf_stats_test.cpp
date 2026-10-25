#include "perf_stats.hpp"
#include <cmath>
#include <iostream>
#include <stdexcept>

using namespace a2;
namespace {
void check(bool ok, const char *message) {
  if (!ok)
    throw std::runtime_error(message);
}
void summary() {
  PerfStats stats;
  for (int i = 0; i < 99; ++i)
    stats.add(1.0 / 60);
  stats.add(0.1);
  const PerfSummary s = stats.summary();
  check(s.frames == 100, "Frame count");
  check(std::abs(s.avgFps - 100 / (99.0 / 60 + 0.1)) < 0.01, "Average fps");
  check(s.low1Fps == 10, "1% low is the fps of the slowest 1% of frames");
  check(s.worstMs == 100, "Worst frame in milliseconds");
}
void lowUsesCeilOfOnePercent() {
  PerfStats stats;
  for (int i = 0; i < 199; ++i)
    stats.add(0.01);
  stats.add(0.05);
  stats.add(0.03);
  // 201 frames: the slowest ceil(2.01) = 3 frames average 0.03 s.
  check(std::abs(stats.summary().low1Fps - 1 / 0.03) < 1e-9, "1% low averages ceil(n/100) frames");
}
void empty() {
  const PerfSummary s = PerfStats().summary();
  check(s.frames == 0 && s.avgFps == 0 && s.low1Fps == 0 && s.worstMs == 0, "Empty summary");
}
void csv() {
  check(perfCsvLine(2, 1, 0.75f, 16.5, 40000) == "2,1,0.75,16.50,40000", "CSV line");
  check(perfCsvLine(6, 3, 1.0f, 8.126, 0) == "6,3,1.00,8.13,0", "CSV rounding");
  check(std::string(perfCsvHeader) == "stage,camera,scale,frame_ms,rss_kb", "CSV header");
}
} // namespace
int main() {
  try {
    summary();
    lowUsesCeilOfOnePercent();
    empty();
    csv();
    std::cout << "Perf stats checks passed\n";
    return 0;
  } catch (const std::exception &e) {
    std::cerr << e.what() << "\n";
    return 1;
  }
}
