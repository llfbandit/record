#pragma once

#include <windows.h>
#include <mfidl.h>
#include <mfapi.h>
#include <mferror.h>
#include <shlwapi.h>
#include <Mfreadwrite.h>

#include <assert.h>

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

	class Recorder : public IMFSourceReaderCallback
	{
	public:
		static HRESULT CreateInstance(EventStreamHandler<>* stateEventHandler, EventStreamHandler<>* recordEventHandler, Recorder** recorder);

		Recorder(EventStreamHandler<>* stateEventHandler, EventStreamHandler<>* recordEventHandler);
		virtual ~Recorder();

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
		
		// IUnknown methods
		STDMETHODIMP QueryInterface(REFIID iid, void** ppv);
		STDMETHODIMP_(ULONG) AddRef();
		STDMETHODIMP_(ULONG) Release();

		// IMFSourceReaderCallback methods
		STDMETHODIMP OnReadSample(HRESULT hrStatus, DWORD dwStreamIndex, DWORD dwStreamFlags, LONGLONG llTimestamp, IMFSample* pSample);
		STDMETHODIMP OnEvent(DWORD, IMFMediaEvent*);
		STDMETHODIMP OnFlush(DWORD);

	private:
		HRESULT CreateAudioCaptureDevice(LPCWSTR pszEndPointID);
		HRESULT CreateSourceReaderAsync();
		HRESULT CreateSinkWriter(std::wstring path);
		HRESULT CreateAudioProfileIn( IMFMediaType** ppMediaType);
		HRESULT CreateAudioProfileOut( IMFMediaType** ppMediaType);

		HRESULT CreateACCProfile( IMFMediaType* pMediaType);
		HRESULT CreateFlacProfile( IMFMediaType* pMediaType);
		HRESULT CreateAmrNbProfile( IMFMediaType* pMediaType);
		HRESULT CreatePcmProfile( IMFMediaType* pMediaType);
		HRESULT FillWavHeader();

		HRESULT InitRecording(std::unique_ptr<RecordConfig> config);
		void UpdateState(RecordState state);
		HRESULT EndRecording();
		void GetAmplitude(BYTE* chunk, DWORD size, int bytesPerSample);
		std::vector<int16_t> convertBytesToInt16(BYTE* bytes, DWORD size);

		long                m_nRefCount;        // Reference count.
		CritSec				m_critsec;

		IMFMediaSource* m_pSource;
		IMFPresentationDescriptor* m_pPresentationDescriptor;
		IMFSourceReader* m_pReader;
		IMFSinkWriter* m_pWriter;
		std::wstring m_recordingPath;
		bool m_mfStarted = false;
		IMFMediaType* m_pMediaType;

		bool m_bFirstSample = true;
		LONGLONG m_llBaseTime = 0;
		LONGLONG m_llLastTime = 0;

		double m_amplitude = -160;
		double m_maxAmplitude = -160;
		DWORD m_dataWritten = 0;

		EventStreamHandler<>* m_stateEventHandler;
		EventStreamHandler<>* m_recordEventHandler;

		RecordState m_recordState = RecordState::stop;
		std::unique_ptr<RecordConfig> m_pConfig;
	};
};