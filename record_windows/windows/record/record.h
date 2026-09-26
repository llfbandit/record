#pragma once

#include <windows.h>

#include <assert.h>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "record_config.h"
#include "amplitude/amplitude_tracker.h"
#include "device_notification/device_notification_client.h"
#include "record/capture_engine.h"
#include "record/sink/record_sink.h"
#include "record/timeline_clock.h"
#include "recorder_dispatcher.h"

namespace record_windows
{
	enum RecordState {
		pause, record, stop
	};

	// Resume() found no device; Dart raises this as RecordResumeNoDeviceException.
	constexpr HRESULT E_RECORD_NO_INPUT_DEVICE = MAKE_HRESULT(SEVERITY_ERROR, FACILITY_ITF, 0x200);

	// What a finished take reports back.
	struct StopResult
	{
		HRESULT hr;
		// Empty when nothing was written: the take is cancelled instead.
		std::wstring path;
	};

	// Everything the recorder reports. Invoked on the dispatcher thread.
	struct RecorderCallbacks
	{
		std::function<void(RecordState)> onState;
		std::function<void(std::vector<uint8_t>)> onChunk;
		std::function<void(const RecordConfig&)> onConfigChanged;
	};

	// Drives one take: what the config asks for, applied to a [CaptureEngine] and
	// an [IRecordSink]. Runs on the dispatcher thread, so nothing here is locked.
	class Recorder
	{
	public:
		Recorder(std::shared_ptr<RecorderDispatcher> dispatcher, RecorderCallbacks callbacks,
			CaptureEngineFactory makeEngine = MakeCaptureEngine);
		~Recorder();

		HRESULT Start(std::unique_ptr<RecordConfig> config, std::wstring path);
		HRESULT StartStream(std::unique_ptr<RecordConfig> config);
		HRESULT Pause();
		HRESULT Resume();
		StopResult Stop();
		HRESULT Cancel();
		// Applies `audioRouteChange`; the device watch or a read error calls it.
		void OnRouteLost();
		bool IsPaused();
		bool IsRecording();
		HRESULT Dispose();
		std::map<std::string, double> GetAmplitude();

	private:
		HRESULT BeginTake(std::unique_ptr<RecordConfig> config, std::unique_ptr<IRecordSink> sink);
		HRESULT OpenCaptureDevice(std::unique_ptr<RecordConfig> config);
		void UpdateState(RecordState state);
		HRESULT EndRecording(bool discard = false);

		// Holds the take on a gone device, so a later Resume() can retry.
		void PauseForRouteLoss();
		// Moves capture to the current default device, keeping the same sink.
		HRESULT MoveToDefaultDevice(bool keepPaused);
		// Moves capture to deviceId, keeping the same sink. Closes the engine if it fails.
		HRESULT MoveToDevice(const std::string& deviceId, bool keepPaused);
		// Returns deviceId, or the default device's id when deviceId is empty.
		HRESULT ResolveDevice(const std::string& deviceId, std::string& resolved) const;

		void    OnSample(HRESULT hrStatus, DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample);
		HRESULT ProcessSample(DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample);
		HRESULT TrackLevel(IMFSample* pSample);

		void AssertOnDispatcher() const { assert(m_dispatcher->IsCurrentThread()); }

		std::shared_ptr<RecorderDispatcher> m_dispatcher;
		RecorderCallbacks m_callbacks;
		bool m_disposed = false;

		std::unique_ptr<ICaptureEngine> m_engine;
		// Lives as long as the recorder: a notification in flight would otherwise touch freed memory.
		Microsoft::WRL::ComPtr<DeviceNotificationClient> m_pRouteWatch;
		std::unique_ptr<IRecordSink> m_pSink;

		TimelineClock m_clock;

		AmplitudeTracker m_amplitude;
		DWORD            m_dataWritten = 0;

		RecordState                m_recordState = RecordState::stop;
		// The device is gone: Resume(), or a new default in `follow`, may move the take.
		bool m_pausedByRouteLoss = false;
		std::unique_ptr<RecordConfig> m_pConfig;
		// Counts takes, to drop a route loss reported by a previous one.
		uint64_t m_takeId = 0;
	};
};
