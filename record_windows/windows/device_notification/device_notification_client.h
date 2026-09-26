#pragma once

#include <windows.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>

#include <atomic>
#include <functional>
#include <mutex>
#include <string>

namespace record_windows
{
	// Watches the capture device in use and reports its removal once per arm.
	class DeviceNotificationClient : public IMMNotificationClient
	{
	public:
		DeviceNotificationClient();

		// Windows calls both on its notification thread: onRouteLost once per arm, with the lost
		// endpoint id, and onDefaultInputChanged on each new default capture device.
		HRESULT Start(const std::wstring& endpointId, std::function<void(const std::wstring&)> onRouteLost,
			std::function<void()> onDefaultInputChanged = nullptr);
		// Ends the take's reports; stays registered for the next Start().
		void Stop();
		// Stops and unregisters, on the thread that registered.
		void Close();
		// Follows capture to endpointId and reports its next removal.
		void Watch(const std::wstring& endpointId);
		// Holds back onRouteLost until the next Watch(), because the recorder already handles this loss.
		void Disarm() { m_armed = false; }

		// IUnknown methods
		STDMETHODIMP QueryInterface(REFIID iid, void** ppv);
		STDMETHODIMP_(ULONG) AddRef();
		STDMETHODIMP_(ULONG) Release();

		// IMMNotificationClient methods
		STDMETHODIMP OnDeviceStateChanged(LPCWSTR pwstrDeviceId, DWORD dwNewState);
		STDMETHODIMP OnDeviceAdded(LPCWSTR pwstrDeviceId);
		STDMETHODIMP OnDeviceRemoved(LPCWSTR pwstrDeviceId);
		STDMETHODIMP OnDefaultDeviceChanged(EDataFlow flow, ERole role, LPCWSTR pwstrDefaultDeviceId);
		STDMETHODIMP OnPropertyValueChanged(LPCWSTR pwstrDeviceId, const PROPERTYKEY key);

	private:
		virtual ~DeviceNotificationClient();

		bool IsWatchedEndpoint(LPCWSTR pwstrDeviceId);
		void NotifyRouteLost(LPCWSTR pwstrDeviceId);

		long m_nRefCount;
		Microsoft::WRL::ComPtr<IMMDeviceEnumerator> m_pEnumerator;
		bool m_registered = false;
		// True between Start() and Stop(), so Watch() arms nothing between takes.
		bool m_started = false;

		// Guards m_endpointId and the callbacks, which the notification thread also reads.
		std::mutex m_mutex;
		std::wstring m_endpointId;
		std::function<void(const std::wstring&)> m_onRouteLost;
		std::function<void()> m_onDefaultInputChanged;

		// Allows one onRouteLost call; the first report of a removal clears it.
		std::atomic<bool> m_armed{ false };
	};
};
