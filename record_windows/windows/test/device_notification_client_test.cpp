#include "device_notification/device_notification_client.h"

#include <gtest/gtest.h>
#include <objbase.h>

#include <string>

namespace record_windows
{
	namespace
	{
		constexpr const wchar_t* kWatchedId = L"{0.0.1.00000000}.{watched-endpoint}";
		constexpr const wchar_t* kOtherId   = L"{0.0.1.00000000}.{other-endpoint}";
	}

	// Sends notifications by hand: a test can't remove a real device.
	class DeviceNotificationClientTest : public ::testing::Test
	{
	protected:
		void SetUp() override
		{
			ASSERT_HRESULT_SUCCEEDED(CoInitializeEx(nullptr, COINIT_MULTITHREADED));

			m_client = new DeviceNotificationClient();
			ASSERT_HRESULT_SUCCEEDED(
				m_client->Start(kWatchedId, [this] { m_calls++; }));
		}

		void TearDown() override
		{
			if (m_client)
			{
				m_client->Close();
				m_client->Release();
			}
			CoUninitialize();
		}

		DeviceNotificationClient* m_client = nullptr;
		int m_calls = 0;
	};

	TEST_F(DeviceNotificationClientTest, ReportsTheWatchedDeviceRemoval)
	{
		m_client->OnDeviceRemoved(kWatchedId);

		EXPECT_EQ(m_calls, 1);
	}

	TEST_F(DeviceNotificationClientTest, ReportsOnlyOnce)
	{
		m_client->OnDeviceRemoved(kWatchedId);
		m_client->OnDeviceRemoved(kWatchedId);

		EXPECT_EQ(m_calls, 1);
	}

	TEST_F(DeviceNotificationClientTest, ReportsAgainAfterWatch)
	{
		m_client->OnDeviceRemoved(kWatchedId);
		m_client->Watch(kWatchedId);
		m_client->OnDeviceRemoved(kWatchedId);

		EXPECT_EQ(m_calls, 2);
	}

	// The reader saw the loss first: the notification adds nothing.
	TEST_F(DeviceNotificationClientTest, DoesNotReportAfterDisarm)
	{
		m_client->Disarm();

		m_client->OnDeviceRemoved(kWatchedId);

		EXPECT_EQ(m_calls, 0);
	}

	TEST_F(DeviceNotificationClientTest, ReportsAgainAfterDisarmAndWatch)
	{
		m_client->Disarm();
		m_client->Watch(kWatchedId);

		m_client->OnDeviceRemoved(kWatchedId);

		EXPECT_EQ(m_calls, 1);
	}

	TEST_F(DeviceNotificationClientTest, WatchCanWatchAnotherDevice)
	{
		m_client->Watch(kOtherId);

		m_client->OnDeviceRemoved(kWatchedId);
		EXPECT_EQ(m_calls, 0);

		m_client->OnDeviceRemoved(kOtherId);
		EXPECT_EQ(m_calls, 1);
	}

	TEST_F(DeviceNotificationClientTest, IgnoresAnotherDeviceRemoval)
	{
		m_client->OnDeviceRemoved(kOtherId);

		EXPECT_EQ(m_calls, 0);
	}

	TEST_F(DeviceNotificationClientTest, IgnoresANullDeviceId)
	{
		m_client->OnDeviceRemoved(nullptr);

		EXPECT_EQ(m_calls, 0);
	}

	// The device in use is still there, so the recording can go on.
	TEST_F(DeviceNotificationClientTest, IgnoresDefaultDeviceChange)
	{
		m_client->OnDefaultDeviceChanged(eCapture, eMultimedia, kOtherId);

		EXPECT_EQ(m_calls, 0);
	}

	TEST_F(DeviceNotificationClientTest, ReportsTheWatchedDeviceUnplugged)
	{
		m_client->OnDeviceStateChanged(kWatchedId, DEVICE_STATE_UNPLUGGED);

		EXPECT_EQ(m_calls, 1);
	}

	TEST_F(DeviceNotificationClientTest, ReportsTheWatchedDeviceDisabled)
	{
		m_client->OnDeviceStateChanged(kWatchedId, DEVICE_STATE_DISABLED);

		EXPECT_EQ(m_calls, 1);
	}

	TEST_F(DeviceNotificationClientTest, IgnoresTheWatchedDeviceStillActive)
	{
		m_client->OnDeviceStateChanged(kWatchedId, DEVICE_STATE_ACTIVE);

		EXPECT_EQ(m_calls, 0);
	}

	TEST_F(DeviceNotificationClientTest, IgnoresAnotherDeviceStateChange)
	{
		m_client->OnDeviceStateChanged(kOtherId, DEVICE_STATE_UNPLUGGED);

		EXPECT_EQ(m_calls, 0);
	}

	TEST_F(DeviceNotificationClientTest, DoesNotReportAfterStop)
	{
		m_client->Stop();

		m_client->OnDeviceRemoved(kWatchedId);

		EXPECT_EQ(m_calls, 0);
	}

	// Between takes, nobody would take the report.
	TEST_F(DeviceNotificationClientTest, WatchDoesNothingAfterStop)
	{
		m_client->Stop();
		m_client->Watch(kWatchedId);

		m_client->OnDeviceRemoved(kWatchedId);

		EXPECT_EQ(m_calls, 0);
	}

	// Stays registered between takes: the next one only turns reports back on.
	TEST_F(DeviceNotificationClientTest, ReportsAgainForTheNextTake)
	{
		m_client->Stop();
		ASSERT_HRESULT_SUCCEEDED(m_client->Start(kOtherId, [this] { m_calls++; }));

		m_client->OnDeviceRemoved(kWatchedId);
		m_client->OnDeviceRemoved(kOtherId);

		EXPECT_EQ(m_calls, 1);
	}

	TEST_F(DeviceNotificationClientTest, DoesNotReportAfterClose)
	{
		m_client->Close();

		m_client->OnDeviceRemoved(kWatchedId);

		EXPECT_EQ(m_calls, 0);
	}

	TEST_F(DeviceNotificationClientTest, StartsAgainAfterClose)
	{
		m_client->Close();
		ASSERT_HRESULT_SUCCEEDED(m_client->Start(kWatchedId, [this] { m_calls++; }));

		m_client->OnDeviceRemoved(kWatchedId);

		EXPECT_EQ(m_calls, 1);
	}
}
