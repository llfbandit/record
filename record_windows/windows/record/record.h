#pragma once

#include <windows.h>
#include <mfidl.h>
#include <mfapi.h>
#include <mferror.h>
#include <Mfreadwrite.h>

#include <assert.h>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "utils.h"
#include "record_config.h"
#include "encoder/stream_encoder.h"
#include "amplitude/amplitude_tracker.h"
#include "record/reader_callback.h"
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

	// Media Foundation capture. Runs on the dispatcher thread, so nothing here is locked.
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
		HRESULT CreateAudioCaptureDevice(LPCWSTR pszEndPointID);
		HRESULT CreateSourceReaderAsync();
		HRESULT CreateSinkWriter(std::wstring path);

		HRESULT InitRecording(std::unique_ptr<RecordConfig> config);
		void UpdateState(RecordState state);
		HRESULT EndRecording();

		void    OnSample(HRESULT hrStatus, DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample);
		void    RebaseTimestamp(LONGLONG& llTimestamp);
		HRESULT ProcessSample(DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample);
		HRESULT ProcessBuffer(IMFSample* pSample);

		void AssertOnDispatcher() const { assert(m_dispatcher->IsCurrentThread()); }

		std::shared_ptr<RecorderDispatcher> m_dispatcher;
		RecorderCallbacks m_callbacks;
		bool m_disposed = false;

		IMFMediaSource*            m_pSource;
		IMFPresentationDescriptor* m_pPresentationDescriptor;
		IMFSourceReader*           m_pReader;
		ReaderCallback*            m_pReaderCallback;
		IMFSinkWriter*             m_pWriter;
		IMFMediaType*              m_pMediaType;
		std::unique_ptr<IStreamEncoder> m_pStreamEncoder;
		std::wstring               m_recordingPath;

		bool     m_bFirstSample = true;
		bool     m_bResuming    = false;
		LONGLONG m_llBaseTime   = 0;
		LONGLONG m_llLastTime   = 0;

		AmplitudeTracker m_amplitude;
		DWORD            m_dataWritten = 0;

		RecordState                m_recordState = RecordState::stop;
		std::unique_ptr<RecordConfig> m_pConfig;
	};
};
