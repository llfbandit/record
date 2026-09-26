#include "device_notification/device_notification_client.h"

#include <shlwapi.h>

namespace record_windows
{
	DeviceNotificationClient::DeviceNotificationClient() : m_nRefCount(1)
	{
	}

	DeviceNotificationClient::~DeviceNotificationClient()
	{
		Close();
	}

	HRESULT DeviceNotificationClient::Start(const std::wstring& endpointId, std::function<void()> onRouteLost)
	{
		// Registers once: later takes only turn reports back on.
		if (!m_pEnumerator)
		{
			HRESULT hr = CoCreateInstance(
				__uuidof(MMDeviceEnumerator), NULL,
				CLSCTX_ALL, IID_PPV_ARGS(&m_pEnumerator)
			);
			if (FAILED(hr)) return hr;
		}

		if (!m_registered)
		{
			HRESULT hr = m_pEnumerator->RegisterEndpointNotificationCallback(this);
			if (FAILED(hr)) return hr;

			m_registered = true;
		}

		{
			std::lock_guard<std::mutex> lock(m_mutex);
			m_endpointId = endpointId;
			m_onRouteLost = std::move(onRouteLost);
		}

		m_started = true;
		m_armed = true;
		return S_OK;
	}

	void DeviceNotificationClient::Stop()
	{
		m_started = false;
		m_armed = false;

		std::lock_guard<std::mutex> lock(m_mutex);
		m_endpointId.clear();
		m_onRouteLost = nullptr;
	}

	void DeviceNotificationClient::Close()
	{
		Stop();

		if (m_registered && m_pEnumerator)
		{
			m_pEnumerator->UnregisterEndpointNotificationCallback(this);
			m_registered = false;
		}

		m_pEnumerator.Reset();
	}

	void DeviceNotificationClient::Watch(const std::wstring& endpointId)
	{
		{
			std::lock_guard<std::mutex> lock(m_mutex);
			m_endpointId = endpointId;
		}

		// Between takes, no recorder would handle the report.
		if (m_started)
		{
			m_armed = true;
		}
	}

	bool DeviceNotificationClient::IsWatchedEndpoint(LPCWSTR pwstrDeviceId)
	{
		if (!pwstrDeviceId) return false;

		std::lock_guard<std::mutex> lock(m_mutex);
		return !m_endpointId.empty() && m_endpointId.compare(pwstrDeviceId) == 0;
	}

	void DeviceNotificationClient::NotifyRouteLost()
	{
		// Windows reports one unplug more than once (unplugged, then not present): only the first goes through.
		bool expected = true;
		if (!m_armed.compare_exchange_strong(expected, false))
		{
			return;
		}

		std::function<void()> callback;
		{
			std::lock_guard<std::mutex> lock(m_mutex);
			callback = m_onRouteLost;
		}

		if (callback) callback();
	}

	// IUnknown methods

	STDMETHODIMP DeviceNotificationClient::QueryInterface(REFIID iid, void** ppv)
	{
		static const QITAB qit[] =
		{
			QITABENT(DeviceNotificationClient, IMMNotificationClient),
			{ 0 },
		};
		return QISearch(this, qit, iid, ppv);
	}

	STDMETHODIMP_(ULONG) DeviceNotificationClient::AddRef()
	{
		return InterlockedIncrement(&m_nRefCount);
	}

	STDMETHODIMP_(ULONG) DeviceNotificationClient::Release()
	{
		ULONG uCount = InterlockedDecrement(&m_nRefCount);
		if (uCount == 0)
		{
			delete this;
		}
		return uCount;
	}

	// IMMNotificationClient methods

	STDMETHODIMP DeviceNotificationClient::OnDeviceStateChanged(LPCWSTR pwstrDeviceId, DWORD dwNewState)
	{
		// Any state but active leaves nothing to capture, so treat it as a removal.
		if (dwNewState != DEVICE_STATE_ACTIVE && IsWatchedEndpoint(pwstrDeviceId))
		{
			NotifyRouteLost();
		}

		return S_OK;
	}

	STDMETHODIMP DeviceNotificationClient::OnDeviceAdded(LPCWSTR)
	{
		return S_OK;
	}

	STDMETHODIMP DeviceNotificationClient::OnDeviceRemoved(LPCWSTR pwstrDeviceId)
	{
		if (IsWatchedEndpoint(pwstrDeviceId))
		{
			NotifyRouteLost();
		}

		return S_OK;
	}

	STDMETHODIMP DeviceNotificationClient::OnDefaultDeviceChanged(EDataFlow, ERole, LPCWSTR)
	{
		return S_OK;
	}

	STDMETHODIMP DeviceNotificationClient::OnPropertyValueChanged(LPCWSTR, const PROPERTYKEY)
	{
		return S_OK;
	}
};
