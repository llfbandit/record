#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>

namespace record_windows::pcm {

// Sum of two already-gained samples with hard clipping to int16.
inline int16_t MixSample(float a, float b) {
  float v = a + b;
  v = (std::max)(-32768.0f, (std::min)(32767.0f, v));
  return static_cast<int16_t>(v);
}

inline double PeakToDb(int peak) {
  return peak > 0 ? 20.0 * std::log10(peak / 32768.0) : -160.0;
}

#pragma pack(push, 1)
struct WavHeader {
  char riff[4] = {'R','I','F','F'};
  uint32_t fileSize = 0;
  char wave[4] = {'W','A','V','E'};
  char fmt[4] = {'f','m','t',' '};
  uint32_t fmtSize = 16;
  uint16_t format = 1;
  uint16_t channels = 0;
  uint32_t rate = 0;
  uint32_t byteRate = 0;
  uint16_t blockAlign = 0;
  uint16_t bits = 16;
  char data[4] = {'d','a','t','a'};
  uint32_t dataSize = 0;
};
#pragma pack(pop)
static_assert(sizeof(WavHeader) == 44, "WAV header must be 44 bytes");

inline WavHeader MakeWavHeader(uint16_t channels, uint32_t rate, uint32_t dataBytes) {
  WavHeader h;
  h.channels = channels;
  h.rate = rate;
  h.blockAlign = static_cast<uint16_t>(channels * 2);
  h.byteRate = rate * h.blockAlign;
  h.dataSize = dataBytes;
  h.fileSize = 36 + dataBytes;
  return h;
}

} 