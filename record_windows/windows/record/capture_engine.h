#pragma once

#include <windows.h>
#include <audioclient.h>
#include <mfidl.h>
#include <mfapi.h>
#include <mferror.h>
#include <Mfreadwrite.h>
#include <wrl/client.h>

#include <functional>
#include <memory>
#include <string>

#include "record_config.h"
#include "record/reader_callback.h"
#include "recorder_dispatcher.h"

namespace record_windows
{
	// Returns true for the read errors a removed device causes, from Media Foundation or WASAPI.
	constexpr bool IsDeviceLost(HRESULT hr)
	{
		return hr == MF_E_AUDIO_RECORDING_DEVICE_INVALIDATED || hr == AUDCLNT_E_DEVICE_INVALIDATED;
	}

	// Captures from one input device for the recorder.
	class ICaptureEngine
	{
	public:
		using SampleHandler = std::function<void(HRESULT hrStatus, DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample)>;

		virtual ~ICaptureEngine() = default;

		// An empty deviceId takes the current default device. Closes first,
		// so the same engine can move from one device to another.
		virtual HRESULT Open(const RecordConfig& config, const std::string& deviceId) = 0;
		virtual void Close() = 0;
		virtual bool IsOpen() const = 0;

		// Returns the id Open() picks for an empty deviceId.
		virtual HRESULT GetDefaultDeviceId(std::string& deviceId) const = 0;

		// The media type the reader delivers, for the sink to accept.
		virtual HRESULT GetInputType(IMFMediaType** ppType) const = 0;

		// Asks for one sample unless one is in flight; the handler answers on the dispatcher thread.
		virtual HRESULT RequestSample() = 0;
		// Starts, or restarts after a pause.
		virtual HRESULT Start() = 0;
		virtual HRESULT Pause() = 0;
	};

	// Builds the engine a recorder drives. Tests pass a fake one instead.
	using CaptureEngineFactory = std::function<std::unique_ptr<ICaptureEngine>(
		std::shared_ptr<RecorderDispatcher>, ICaptureEngine::SampleHandler)>;

	// Captures with Media Foundation on the dispatcher thread, so nothing here needs a lock.
	class CaptureEngine : public ICaptureEngine
	{
	public:
		CaptureEngine(std::shared_ptr<RecorderDispatcher> dispatcher, SampleHandler onSample);
		~CaptureEngine() override;

		CaptureEngine(const CaptureEngine&) = delete;
		CaptureEngine& operator=(const CaptureEngine&) = delete;

		HRESULT Open(const RecordConfig& config, const std::string& deviceId) override;
		void Close() override;
		// A source without a reader delivers nothing, so it doesn't count as open.
		bool IsOpen() const override { return m_pSource != nullptr && m_pReader != nullptr; }

		HRESULT GetDefaultDeviceId(std::string& deviceId) const override;

		HRESULT GetInputType(IMFMediaType** ppType) const override;
		HRESULT RequestSample() override;
		HRESULT Start() override;
		HRESULT Pause() override;

	private:
		HRESULT CreateSource(LPCWSTR deviceId);
		HRESULT CreateReaderAsync(const RecordConfig& config);

		template <typename T> using ComPtr = Microsoft::WRL::ComPtr<T>;

		std::shared_ptr<RecorderDispatcher> m_dispatcher;
		SampleHandler m_onSample;

		ComPtr<IMFMediaSource>            m_pSource;
		ComPtr<IMFPresentationDescriptor> m_pPresentationDescriptor;
		ComPtr<IMFSourceReader>           m_pReader;
		ComPtr<ReaderCallback>            m_pReaderCallback;

		// RequestSample() sets it and the sample callback clears it, so reads never stack up.
		bool m_readPending = false;
	};

	std::unique_ptr<ICaptureEngine> MakeCaptureEngine(
		std::shared_ptr<RecorderDispatcher> dispatcher, ICaptureEngine::SampleHandler onSample);
}
