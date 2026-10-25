#pragma once
#include <string>
#include <vector>

namespace a2 {
struct PerfSummary {
  int frames;
  double avgFps, low1Fps, worstMs;
};
// Frame-time statistics: average fps, the fps of the slowest 1% of frames
// (mean of the worst ceil(frames/100) frame times) and the worst frame.
class PerfStats {
public:
  void add(double frameSeconds) { times_.push_back(frameSeconds); }
  PerfSummary summary() const;

private:
  std::vector<double> times_;
};
constexpr const char *perfCsvHeader = "stage,camera,scale,frame_ms,rss_kb";
std::string perfCsvLine(int stage, int camera, float scale, double frameMs, long rssKb);
// Resident set size of this process in KiB (Linux /proc/self/statm), else 0.
long residentKb();
} // namespace a2
