#include <gtest/gtest.h>
#include "wasapi/pcm_utils.h"

using namespace record_windows::pcm;

TEST(MixSample, SumsWithinRange) {
  EXPECT_EQ(MixSample(1000.f, 2000.f), 3000);
}

TEST(MixSample, ClipsPositive) {
  EXPECT_EQ(MixSample(30000.f, 30000.f), 32767);
}

TEST(MixSample, ClipsNegative) {
  EXPECT_EQ(MixSample(-30000.f, -30000.f), -32768);
}

TEST(PeakToDb, SilenceIsFloor) {
  EXPECT_DOUBLE_EQ(PeakToDb(0), -160.0);
}

TEST(PeakToDb, FullScaleIsAboutZero) {
  EXPECT_NEAR(PeakToDb(32768), 0.0, 1e-9);
}

TEST(PeakToDb, HalfScaleIsMinusSix) {
  EXPECT_NEAR(PeakToDb(16384), -6.02, 0.01);
}

TEST(WavHeader, LayoutAndFields) {
  auto h = MakeWavHeader(2, 48000, 1000);
  EXPECT_EQ(sizeof(h), 44u);
  EXPECT_EQ(std::string(h.riff, 4), "RIFF");
  EXPECT_EQ(std::string(h.data, 4), "data");
  EXPECT_EQ(h.fileSize, 1036u);
  EXPECT_EQ(h.blockAlign, 4);
  EXPECT_EQ(h.byteRate, 192000u);
  EXPECT_EQ(h.dataSize, 1000u);
}