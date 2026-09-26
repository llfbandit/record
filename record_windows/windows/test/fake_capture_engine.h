#pragma once

#include "record/capture_engine.h"

#include <string>
#include <vector>

namespace record_windows
{
	// Stands in for Media Foundation: opens no device and fails on demand.
	class FakeCaptureEngine : public ICaptureEngine
	{
	public:
		HRESULT Open(const RecordConfig& config, const std::string& deviceId) override
		{
			m_openedDeviceIds.push_back(deviceId);
			m_config = config;
			m_open = false;

			if (m_openFailures > 0)
			{
				m_openFailures--;
				return E_FAIL;
			}

			m_open = true;
			return S_OK;
		}

		void Close() override { m_open = false; }
		bool IsOpen() const override { return m_open; }

		HRESULT GetDefaultDeviceId(std::string& deviceId) const override
		{
			deviceId = m_defaultDeviceId;
			return S_OK;
		}

		// A reader hands back a complete PCM type, not just the one asked for.
		HRESULT GetInputType(IMFMediaType** ppType) const override
		{
			if (!m_open) return E_NOT_VALID_STATE;

			WAVEFORMATEX wf{};
			wf.wFormatTag      = WAVE_FORMAT_PCM;
			wf.nChannels       = static_cast<WORD>(m_config.numChannels);
			wf.nSamplesPerSec  = static_cast<DWORD>(m_config.sampleRate);
			wf.wBitsPerSample  = 16;
			wf.nBlockAlign     = wf.nChannels * wf.wBitsPerSample / 8;
			wf.nAvgBytesPerSec = wf.nSamplesPerSec * wf.nBlockAlign;

			Microsoft::WRL::ComPtr<IMFMediaType> type;
			HRESULT hr = MFCreateMediaType(&type);
			if (SUCCEEDED(hr)) hr = MFInitMediaTypeFromWaveFormatEx(type.Get(), &wf, sizeof(wf));
			if (SUCCEEDED(hr)) *ppType = type.Detach();

			return hr;
		}

		HRESULT RequestSample() override { return m_open ? S_OK : E_NOT_VALID_STATE; }
		HRESULT Pause() override { return m_open ? S_OK : E_NOT_VALID_STATE; }

		HRESULT Start() override
		{
			if (!m_open) return E_NOT_VALID_STATE;

			if (m_startFailures > 0)
			{
				m_startFailures--;
				return E_FAIL;
			}

			return S_OK;
		}

		// Fails the next `count` Open() calls.
		void FailOpens(int count) { m_openFailures = count; }
		// Fails the next `count` Start() calls.
		void FailStarts(int count) { m_startFailures = count; }
		// Sets what Windows reports as the default input device.
		void SetDefaultDeviceId(std::string deviceId) { m_defaultDeviceId = std::move(deviceId); }

		// Every deviceId Open() was asked for, in order.
		const std::vector<std::string>& OpenedDeviceIds() const { return m_openedDeviceIds; }

	private:
		RecordConfig m_config;
		bool m_open = false;
		int  m_openFailures = 0;
		int  m_startFailures = 0;
		std::string m_defaultDeviceId = "default-device";
		std::vector<std::string> m_openedDeviceIds;
	};
}
