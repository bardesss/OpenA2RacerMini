#include "perf_stats.hpp"
#include <algorithm>
#include <cstdio>
#include <functional>
#include <numeric>
#if defined(__linux__)
#include <fstream>
#include <unistd.h>
#endif

namespace a2 {
PerfSummary PerfStats::summary() const {
  PerfSummary s{int(times_.size()), 0, 0, 0};
  if (times_.empty())
    return s;
  const double total = std::accumulate(times_.begin(), times_.end(), 0.0);
  const size_t worst = (times_.size() + 99) / 100;
  std::vector<double> sorted(times_);
  std::partial_sort(sorted.begin(), sorted.begin() + std::ptrdiff_t(worst), sorted.end(),
                    std::greater<double>());
  const double slowMean =
      std::accumulate(sorted.begin(), sorted.begin() + std::ptrdiff_t(worst), 0.0) / double(worst);
  s.avgFps = total > 0 ? double(times_.size()) / total : 0;
  s.low1Fps = slowMean > 0 ? 1 / slowMean : 0;
  s.worstMs = sorted.front() * 1000;
  return s;
}
std::string perfCsvLine(int stage, int camera, float scale, double frameMs, long rssKb) {
  char line[96];
  std::snprintf(line, sizeof line, "%d,%d,%.2f,%.2f,%ld", stage, camera, double(scale), frameMs,
                rssKb);
  return line;
}
long residentKb() {
#if defined(__linux__)
  std::ifstream statm("/proc/self/statm");
  long size = 0, resident = 0;
  if (statm >> size >> resident)
    return resident * (sysconf(_SC_PAGESIZE) / 1024);
#endif
  return 0;
}
} // namespace a2
