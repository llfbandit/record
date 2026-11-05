#include "wasapi_mix_recorder.h"
#include <future>
#include <cmath>
#include <algorithm>
#include "pcm_utils.h"

using Microsoft::WRL::ComPtr;

namespace record_windows {

WasapiMixRecorder::~WasapiMixRecorder() { Cancel(); }

HRESULT WasapiMixRecorder::Start(const WasapiMixConfig& cfg, const std::wstring& path) {
  if (running_) return E_ILLEGAL_METHOD_CALL;
  cfg_ = cfg;
  path_ = path;
  if (_wfopen_s(&file_, path.c_str(), L"wb") != 0 || !file_)
    return HRESULT_FROM_WIN32(ERROR_OPEN_FAILED);
  dataBytes_ = 0;
  WriteWavHeader(false);                         // placeholder
  HRESULT hr = StartInternal(cfg);
  if (FAILED(hr)) { fclose(file_); file_ = nullptr; DeleteFileW(path.c_str()); }
  return hr;
}

HRESULT WasapiMixRecorder::StartStream(const WasapiMixConfig& cfg, PcmCallback cb) {
  if (running_) return E_ILLEGAL_METHOD_CALL;
  streamCb_ = std::move(cb);
  return StartInternal(cfg);
}

HRESULT WasapiMixRecorder::StartInternal(const WasapiMixConfig& cfg) {
  cfg_ = cfg;
  curDb_ = maxDb_ = -160.0;
  paused_ = false;

  std::promise<HRESULT> init;
  auto fut = init.get_future();
  running_ = true;
  thread_ = std::thread(&WasapiMixRecorder::ThreadMain, this, &init);
  HRESULT hr = fut.get();                        // wait for init result from capture thread
  if (FAILED(hr)) {
    running_ = false;
    if (thread_.joinable()) thread_.join();
  }
  return hr;
}

HRESULT WasapiMixRecorder::OpenSource(Source& s, IMMDeviceEnumerator* en,
                                      EDataFlow flow, const std::wstring& id,
                                      bool loopback) {
  ComPtr<IMMDevice> dev;
  HRESULT hr = id.empty()
      ? en->GetDefaultAudioEndpoint(flow, eConsole, &dev)
      : en->GetDevice(id.c_str(), &dev);
  if (FAILED(hr)) return hr;

  hr = dev->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                     reinterpret_cast<void**>(s.client.GetAddressOf()));
  if (FAILED(hr)) return hr;

  // One common format for both sources: Windows converts/resamples for us.
  WAVEFORMATEX fmt{};
  fmt.wFormatTag = WAVE_FORMAT_PCM;
  fmt.nChannels = cfg_.channels;
  fmt.nSamplesPerSec = cfg_.sampleRate;
  fmt.wBitsPerSample = 16;
  fmt.nBlockAlign = fmt.nChannels * 2;
  fmt.nAvgBytesPerSec = fmt.nSamplesPerSec * fmt.nBlockAlign;

  DWORD flags = AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
                AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY;
  if (loopback) flags |= AUDCLNT_STREAMFLAGS_LOOPBACK;

  hr = s.client->Initialize(AUDCLNT_SHAREMODE_SHARED, flags,
                            2000000 /* 200 ms */, 0, &fmt, nullptr);
  if (FAILED(hr)) return hr;

  hr = s.client->GetService(__uuidof(IAudioCaptureClient),
                            reinterpret_cast<void**>(s.capture.GetAddressOf()));
  if (FAILED(hr)) return hr;

  s.active = true;
  return S_OK;
}

void WasapiMixRecorder::ThreadMain(std::promise<HRESULT>* initResult) {
  HRESULT co = CoInitializeEx(nullptr, COINIT_MULTITHREADED);

  mic_ = Source{}; sys_ = Source{};
  mic_.gain = cfg_.micGain;
  sys_.gain = cfg_.systemGain;

  HRESULT hr = S_OK;
  {
    ComPtr<IMMDeviceEnumerator> en;
    hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                          IID_PPV_ARGS(&en));
    if (SUCCEEDED(hr) && cfg_.captureMic)
      hr = OpenSource(mic_, en.Get(), eCapture, cfg_.micDeviceId, false);
    if (SUCCEEDED(hr) && cfg_.captureSystem)
      hr = OpenSource(sys_, en.Get(), eRender, cfg_.renderDeviceId, true);
    if (SUCCEEDED(hr) && !mic_.active && !sys_.active) hr = E_INVALIDARG;

    if (SUCCEEDED(hr)) {
      if (mic_.active) hr = mic_.client->Start();
      if (SUCCEEDED(hr) && sys_.active) hr = sys_.client->Start();
    }
  }
  initResult->set_value(hr);

  if (SUCCEEDED(hr)) {
    while (running_) {
      Drain(mic_);
      Drain(sys_);
      MixAndOutput();
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    Drain(mic_); Drain(sys_);
    MixAndOutput();                              // flush the tail
    if (mic_.active) mic_.client->Stop();
    if (sys_.active) sys_.client->Stop();
  }

  mic_ = Source{}; sys_ = Source{};              // release COM before CoUninitialize
  if (SUCCEEDED(co)) CoUninitialize();
}

void WasapiMixRecorder::Drain(Source& s) {
  if (!s.active) return;
  UINT32 packet = 0;
  while (SUCCEEDED(s.capture->GetNextPacketSize(&packet)) && packet > 0) {
    BYTE* data = nullptr; UINT32 frames = 0; DWORD flags = 0;
    if (FAILED(s.capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) break;
    const size_t samples = size_t(frames) * cfg_.channels;
    if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
      s.queue.insert(s.queue.end(), samples, 0);
    } else {
      auto* p = reinterpret_cast<const int16_t*>(data);
      s.queue.insert(s.queue.end(), p, p + samples);
    }
    s.capture->ReleaseBuffer(frames);
  }
}

void WasapiMixRecorder::MixAndOutput() {
  // Master clock = mic if present, otherwise system audio.
  // The other source is padded with silence (loopback emits nothing when idle).
  Source& master = mic_.active ? mic_ : sys_;
  size_t n = master.queue.size();
  n -= n % cfg_.channels;
  if (n == 0) return;

  std::vector<int16_t> out(n);
  int peak = 0;
  auto pull = [](Source& s) -> float {
    if (!s.active || s.queue.empty()) return 0.0f;
    float v = float(s.queue.front()) * s.gain;
    s.queue.pop_front();
    return v;
  };
  for (size_t i = 0; i < n; ++i) {
    out[i] = pcm::MixSample(pull(mic_), pull(sys_));
    peak = (std::max)(peak, std::abs(int(out[i])));
  }

  // Amplitude (dBFS)
  double db = pcm::PeakToDb(peak);
  curDb_ = db;
  if (db > maxDb_) maxDb_ = db;

  if (paused_) return;                           // keep draining, drop data

  const size_t bytes = n * sizeof(int16_t);
  if (file_) {
    fwrite(out.data(), 1, bytes, file_);
    dataBytes_ += bytes;
  }
  if (streamCb_) streamCb_(reinterpret_cast<const uint8_t*>(out.data()), bytes);
}

void WasapiMixRecorder::WriteWavHeader(bool finalize) {
  if (!file_) return;
  auto h = pcm::MakeWavHeader(cfg_.channels, cfg_.sampleRate,
                              finalize ? uint32_t(dataBytes_) : 0);
  if (finalize) fseek(file_, 0, SEEK_SET);
  fwrite(&h, sizeof(h), 1, file_);
}

HRESULT WasapiMixRecorder::Stop(std::wstring* outPath) {
  if (!running_) return S_OK;
  running_ = false;
  if (thread_.joinable()) thread_.join();
  if (file_) {
    WriteWavHeader(true);
    fclose(file_); file_ = nullptr;
    if (outPath) *outPath = path_;
  }
  streamCb_ = nullptr;
  return S_OK;
}

void WasapiMixRecorder::Cancel() {
  if (running_) {
    running_ = false;
    if (thread_.joinable()) thread_.join();
  }
  if (file_) { fclose(file_); file_ = nullptr; DeleteFileW(path_.c_str()); }
  streamCb_ = nullptr;
}

void WasapiMixRecorder::GetAmplitude(double* current, double* max) const {
  *current = curDb_; *max = maxDb_;
}

}  