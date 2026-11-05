#pragma once
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <wrl/client.h>
#include <atomic>
#include <cstdint>
#include <deque>
#include <functional>
#include <future>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace record_windows {

struct WasapiMixConfig {
  uint32_t sampleRate = 48000;
  uint16_t channels = 2;
  bool captureMic = true;
  bool captureSystem = true;
  std::wstring micDeviceId; 
  std::wstring renderDeviceId;
  float micGain = 1.0f;
  float systemGain = 0.7f;
};

class WasapiMixRecorder {
 public:
  using PcmCallback = std::function<void(const uint8_t*, size_t)>;

  ~WasapiMixRecorder();

  HRESULT Start(const WasapiMixConfig& cfg, const std::wstring& path);
  HRESULT StartStream(const WasapiMixConfig& cfg, PcmCallback cb);
  HRESULT Stop(std::wstring* outPath);
  void Cancel();
  void Pause()  { paused_ = true; }
  void Resume() { paused_ = false; }
  bool IsRecording() const { return running_; }
  bool IsPaused() const { return paused_; }
  void GetAmplitude(double* current, double* max) const;

 private:
  struct Source {
    Microsoft::WRL::ComPtr<IAudioClient> client;
    Microsoft::WRL::ComPtr<IAudioCaptureClient> capture;
    std::deque<int16_t> queue;
    float gain = 1.0f;
    bool active = false;
  };

  HRESULT StartInternal(const WasapiMixConfig& cfg);
  void ThreadMain(std::promise<HRESULT>* initResult);
  HRESULT OpenSource(Source& s, IMMDeviceEnumerator* en, EDataFlow flow,
                     const std::wstring& id, bool loopback);
  void Drain(Source& s);
  void MixAndOutput();
  void WriteWavHeader(bool finalize);

  WasapiMixConfig cfg_;
  Source mic_, sys_;

  std::thread thread_;
  std::atomic<bool> running_{false};
  std::atomic<bool> paused_{false};

  std::wstring path_;
  FILE* file_ = nullptr;
  uint64_t dataBytes_ = 0;
  PcmCallback streamCb_;

  std::atomic<double> curDb_{-160.0};
  std::atomic<double> maxDb_{-160.0};
};

}