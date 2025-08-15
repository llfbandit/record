#pragma once

#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <audiopolicy.h>
//#include <audioengineextensionapo.h> // Temporarily disabled due to GUID compilation issues
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <functiondiscoverykeys_devpkey.h>
#include <mmreg.h>
#include <ks.h>
#include <ksmedia.h>

#include <atomic>
#include <thread>
#include <memory>
#include <functional>
#include <vector>
#include <string>
#include <map>
#include <fstream>

// utility functions
#include "utils.h"
#include "record_config.h"
#include "event_stream_handler.h"

using namespace flutter;

namespace record_windows
{
	enum RecordState {
		pause, record, stop
	};

	// Lock-free ring buffer for real-time audio processing
	template<typename T>
	class LockFreeRingBuffer {
	private:
		std::vector<T> m_buffer;
		std::atomic<size_t> m_writeIndex{0};
		std::atomic<size_t> m_readIndex{0};
		size_t m_size;
		size_t m_mask; // For power-of-2 sizes

	public:
		explicit LockFreeRingBuffer(size_t size);
		bool Write(const T* data, size_t count);
		size_t Read(T* data, size_t maxCount);
		size_t Available() const;
		void Clear();
	};

	// Real-time amplitude analyzer
	class AmplitudeAnalyzer {
	private:
		std::atomic<float> m_currentAmplitude{-160.0f};
		std::atomic<float> m_maxAmplitude{-160.0f};
		
	public:
		void ProcessSamples(const float* samples, size_t count);
		float GetCurrentAmplitude() const { return m_currentAmplitude.load(); }
		float GetMaxAmplitude() const { return m_maxAmplitude.load(); }
		void Reset();
	};

	// Async audio file writer with multiple codec support
	class AsyncAudioWriter {
	private:
		std::unique_ptr<LockFreeRingBuffer<float>> m_audioBuffer;
		std::thread m_writerThread;
		std::atomic<bool> m_isRunning{false};
		std::wstring m_filePath;
		std::string m_encoderName;
		DWORD m_sampleRate;
		WORD m_channels;
		std::ofstream m_fileStream;
		size_t m_bytesWritten{0};
		
		// Media Foundation for advanced codecs
		IMFSinkWriter* m_pSinkWriter{nullptr};
		DWORD m_streamIndex{0};
		bool m_useMediaFoundation{false};

		void WriterThreadProc();
		HRESULT WriteWavHeader();
		HRESULT UpdateWavHeader();
		
		// Media Foundation codec support
		HRESULT InitializeMediaFoundationEncoder();
		HRESULT WriteMediaFoundationSample(const float* samples, size_t count);
		void CleanupMediaFoundation();

	public:
		AsyncAudioWriter();
		~AsyncAudioWriter();
		
		HRESULT Initialize(const std::wstring& filePath, const std::string& encoder, 
						  DWORD sampleRate, WORD channels);
		HRESULT Start();
		HRESULT Stop();
		void QueueAudio(const float* samples, size_t count);
		size_t GetBytesWritten() const { return m_bytesWritten; }
	};

	// WASAPI audio capture engine
	class WASAPICapture {
	private:
		IMMDeviceEnumerator* m_pDeviceEnumerator;
		IMMDevice* m_pDevice;
		IAudioClient* m_pAudioClient;
		IAudioCaptureClient* m_pCaptureClient;
		// IAudioEffectsManager* m_pEffectsManager; // Temporarily disabled due to GUID compilation issues
		
		HANDLE m_hCaptureEvent;
		std::thread m_captureThread;
		std::atomic<bool> m_isCapturing{false};
		
		WAVEFORMATEX* m_pWaveFormat;
		DWORD m_sampleRate;
		WORD m_channels;
		
		// Audio processing configuration
		bool m_enableNoiseSuppress{false};
		bool m_enableEchoCancel{false};
		bool m_enableAutoGain{false};
		
		// Callbacks
		std::function<void(const float* samples, size_t count)> m_onAudioData;
		
		void CaptureThreadProc();
		HRESULT InitializeAudioClient();
		HRESULT InitializeAudioEffects();
		bool IsFloatFormat();

	public:
		WASAPICapture();
		~WASAPICapture();
		
		HRESULT Initialize(const std::string& deviceId, DWORD sampleRate, WORD channels, 
						  bool noiseSuppress = false, bool echoCancel = false, bool autoGain = false);
		HRESULT Start();
		HRESULT Stop();
		HRESULT Pause();
		HRESULT Resume();
		
		void SetAudioDataCallback(std::function<void(const float* samples, size_t count)> callback);
		
		DWORD GetSampleRate() const { return m_sampleRate; }
		WORD GetChannels() const { return m_channels; }
		bool IsCapturing() const { return m_isCapturing.load(); }
		
		// Get actual device format for debugging
		std::string GetActualFormat() const {
			if (!m_pWaveFormat) return "No format";
			return "Channels: " + std::to_string(m_pWaveFormat->nChannels) + 
				   ", SampleRate: " + std::to_string(m_pWaveFormat->nSamplesPerSec) +
				   ", BitsPerSample: " + std::to_string(m_pWaveFormat->wBitsPerSample);
		}
	};

	// Main recorder class - orchestrates all components
	class Recorder
	{
	public:
		static HRESULT CreateInstance(EventStreamHandler<>* stateEventHandler, 
									  EventStreamHandler<>* recordEventHandler, 
									  Recorder** recorder);

		Recorder(EventStreamHandler<>* stateEventHandler, EventStreamHandler<>* recordEventHandler);
		virtual ~Recorder();

		// Public interface (matches existing API)
		HRESULT Start(std::unique_ptr<RecordConfig> config, std::wstring path);
		HRESULT StartStream(std::unique_ptr<RecordConfig> config);
		HRESULT Pause();
		HRESULT Resume();
		HRESULT Stop();
		HRESULT Cancel();
		bool IsPaused();
		bool IsRecording();
		HRESULT Dispose();
		std::map<std::string, double> GetAmplitude();
		std::wstring GetRecordingPath();
		HRESULT isEncoderSupported(std::string encoderName, bool* supported);

	private:
		// Core components
		std::unique_ptr<WASAPICapture> m_capture;
		std::unique_ptr<AmplitudeAnalyzer> m_amplitudeAnalyzer;
		std::unique_ptr<AsyncAudioWriter> m_fileWriter;
		
		// State management
		RecordState m_recordState;
		std::unique_ptr<RecordConfig> m_config;
		std::wstring m_recordingPath;
		
		// Flutter event handlers
		EventStreamHandler<>* m_stateEventHandler;
		EventStreamHandler<>* m_recordEventHandler;
		
		// Internal state
		std::atomic<bool> m_isInitialized{false};
		std::atomic<bool> m_isRecordingToFile{false};
		std::atomic<bool> m_isStreaming{false};
		
		// Audio data callback
		void OnAudioData(const float* samples, size_t count);
		
		// State updates
		void UpdateState(RecordState state);
		
		// Cleanup
		void Cleanup();
		
		// Helper methods
		HRESULT ValidateConfig(const RecordConfig& config);
		DWORD GetSampleRateFromConfig(const RecordConfig& config);
		WORD GetChannelsFromConfig(const RecordConfig& config);
	};
}