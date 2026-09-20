#pragma once

#include <windows.h>

#include <assert.h>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "record_config.h"
#include "amplitude/amplitude_tracker.h"
#include "record/capture_engine.h"
#include "record/sink/record_sink.h"
#include "record/timeline_clock.h"
#include "recorder_dispatcher.h"

namespace record_windows
{
	enum RecordState {
		pause, record, stop
	};

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
		Recorder(std::shared_ptr<RecorderDispatcher> dispatcher, RecorderCallbacks callbacks);

		HRESULT Start(std::unique_ptr<RecordConfig> config, std::wstring path);
		HRESULT StartStream(std::unique_ptr<RecordConfig> config);
		HRESULT Pause();
		HRESULT Resume();
		StopResult Stop();
		HRESULT Cancel();
		bool IsPaused();
		bool IsRecording();
		// Final: Start() is refused afterwards.
		HRESULT Dispose();
		std::map<std::string, double> GetAmplitude();

	private:
		HRESULT BeginTake(std::unique_ptr<RecordConfig> config, std::unique_ptr<IRecordSink> sink);
		HRESULT OpenCaptureDevice(std::unique_ptr<RecordConfig> config);
		void UpdateState(RecordState state);
		HRESULT EndRecording(bool discard = false);

		void    OnSample(HRESULT hrStatus, DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample);
		HRESULT ProcessSample(DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample);
		HRESULT TrackLevel(IMFSample* pSample);

		void AssertOnDispatcher() const { assert(m_dispatcher->IsCurrentThread()); }

		std::shared_ptr<RecorderDispatcher> m_dispatcher;
		RecorderCallbacks m_callbacks;
		bool m_disposed = false;

		CaptureEngine m_engine;
		std::unique_ptr<IRecordSink> m_pSink;

		TimelineClock m_clock;

		AmplitudeTracker m_amplitude;
		DWORD            m_dataWritten = 0;

		RecordState                m_recordState = RecordState::stop;
		std::unique_ptr<RecordConfig> m_pConfig;
	};
};
