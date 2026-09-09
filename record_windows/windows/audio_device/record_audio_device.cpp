#include "audio_device/record_audio_device.h"
#include "encoder/codec_caps.h"
#include "record_config.h"
#include "utils.h"

#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mftransform.h>
#include <mmdeviceapi.h>
#include <functiondiscoverykeys_devpkey.h>
#include <propidl.h>
#include <devicetopology.h>
#include <vector>
#include <mutex>
#include <thread>
#include <unordered_map>

namespace record_windows {
namespace AudioDevice {

// Avoids linking PKEY_AudioEngine_DeviceFormat from propsys.lib (LNK2001)
static const PROPERTYKEY kAudioEngineDeviceFormat = {
    {0xf19f064d, 0x082c, 0x4e27, {0xbc,0x73,0x68,0x82,0xa1,0xbb,0x8e,0x4c}}, 0
};

static std::mutex                                                    gCapsMutex;
static std::unordered_map<std::string, std::vector<CodecCapsEntry>> gCapsCache;

static std::vector<CodecCapsEntry> FetchCodecCaps(GUID subtypeGuid)
{
    std::vector<CodecCapsEntry> caps;

    IMFActivate** ppMFTActivate  = NULL;
    UINT32        numMFTActivate = 0;

    MFT_REGISTER_TYPE_INFO typeInfo = { MFMediaType_Audio, subtypeGuid };
    DWORD dwFlags = (MFT_ENUM_FLAG_ALL & (~MFT_ENUM_FLAG_FIELDOFUSE)) | MFT_ENUM_FLAG_SORTANDFILTER;

    if (FAILED(MFTEnumEx(MFT_CATEGORY_AUDIO_ENCODER, dwFlags, NULL, &typeInfo, &ppMFTActivate, &numMFTActivate)))
        return caps;

    if (numMFTActivate > 0)
    {
        IMFTransform* pMFT = NULL;
        if (SUCCEEDED(ppMFTActivate[0]->ActivateObject(IID_PPV_ARGS(&pMFT))))
        {
            for (DWORD i = 0; ; i++)
            {
                IMFMediaType* pType = NULL;
                if (FAILED(pMFT->GetOutputAvailableType(0, i, &pType))) break;

                CodecCapsEntry e = {};
                pType->GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, &e.sampleRate);
                pType->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS,       &e.channels);
                pType->GetUINT32(MF_MT_AVG_BITRATE,              &e.bitRate);
                SafeRelease(&pType);

                if (e.sampleRate > 0 && e.channels > 0) caps.push_back(e);
            }

            ppMFTActivate[0]->ShutdownObject();
            SafeRelease(&pMFT);
        }
    }

    for (UINT32 i = 0; i < numMFTActivate; i++) SafeRelease(ppMFTActivate[i]);
    CoTaskMemFree(ppMFTActivate);

    return caps;
}

static std::string DeviceTypeFromInstanceId(LPCWSTR id)
{
    const wchar_t* p = id;
    if (wcslen(p) > 4 && p[0]==L'\\' && p[1]==L'\\' && p[2]==L'?' && p[3]==L'\\')
        p += 4;

    if (wcsstr(p, L"HDAUDIO"))      return "builtIn";
    if (wcsstr(p, L"USB"))          return "usb";
    if (wcsstr(p, L"BTHLEDevice"))  return "bluetoothLe";
    if (wcsstr(p, L"BTHLE"))        return "bluetoothLe";
    if (wcsstr(p, L"BTHENUM"))      return "bluetoothSco";
    return "unknown";
}

static std::string GetDeviceTypeViaTopology(IMMDevice* pDevice)
{
    IDeviceTopology* pTopology = NULL;
    IConnector*      pConn     = NULL;
    IConnector*      pConnTo   = NULL;
    IPart*           pPart     = NULL;
    std::string      result    = "unknown";

    HRESULT hr = pDevice->Activate(__uuidof(IDeviceTopology), CLSCTX_ALL, NULL, (void**)&pTopology);
    if (SUCCEEDED(hr))
    {
			hr = pTopology->GetConnector(0, &pConn);
		}
    if (SUCCEEDED(hr))
		{
        hr = pConn->GetConnectedTo(&pConnTo);
		}
    if (SUCCEEDED(hr))
		{
        hr = pConnTo->QueryInterface(IID_PPV_ARGS(&pPart));
		}
    if (SUCCEEDED(hr))
    {
        IDeviceTopology* pHwTopo = NULL;
        if (SUCCEEDED(pPart->GetTopologyObject(&pHwTopo)))
        {
            LPWSTR pwszDevId = NULL;
            if (SUCCEEDED(pHwTopo->GetDeviceId(&pwszDevId)) && pwszDevId)
            {
                result = DeviceTypeFromInstanceId(pwszDevId);
                CoTaskMemFree(pwszDevId);
            }
            SafeRelease(&pHwTopo);
        }
    }

    SafeRelease(&pPart);
    SafeRelease(&pConnTo);
    SafeRelease(&pConn);
    SafeRelease(&pTopology);
    return result;
}

HRESULT ListInputDevices(flutter::EncodableList& devices)
{
	IMMDeviceEnumerator* pEnumerator = NULL;
	IMMDeviceCollection* pCollection = NULL;

	HRESULT hr = CoCreateInstance(
		__uuidof(MMDeviceEnumerator), NULL,
		CLSCTX_ALL, IID_PPV_ARGS(&pEnumerator)
	);
	if (SUCCEEDED(hr))
		hr = pEnumerator->EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE, &pCollection);

	if (SUCCEEDED(hr))
	{
		UINT count = 0;
		pCollection->GetCount(&count);

		for (UINT i = 0; i < count; i++)
		{
			IMMDevice*      pDevice = NULL;
			IPropertyStore* pProps  = NULL;

			if (FAILED(pCollection->Item(i, &pDevice))) continue;

			LPWSTR pwszId = NULL;
			if (FAILED(pDevice->GetId(&pwszId)) || !pwszId)
			{
				SafeRelease(&pDevice);
				continue;
			}

			if (SUCCEEDED(pDevice->OpenPropertyStore(STGM_READ, &pProps)))
			{
				PROPVARIANT varName, varFormat;
				PropVariantInit(&varName);
				PropVariantInit(&varFormat);

				pProps->GetValue(PKEY_Device_FriendlyName, &varName);
				pProps->GetValue(kAudioEngineDeviceFormat, &varFormat);

				std::string label = (varName.vt == VT_LPWSTR) ? Utf8FromUtf16(varName.pwszVal) : "";
				std::string type  = GetDeviceTypeViaTopology(pDevice);

				flutter::EncodableList rateList;
				if (varFormat.vt == VT_BLOB && varFormat.blob.cbSize >= sizeof(WAVEFORMATEX))
				{
					auto* wf = reinterpret_cast<const WAVEFORMATEX*>(varFormat.blob.pBlobData);
					if (wf->nSamplesPerSec > 0)
						rateList.push_back(flutter::EncodableValue((int)wf->nSamplesPerSec));
				}

				devices.push_back(flutter::EncodableMap({
					{flutter::EncodableValue("id"),          flutter::EncodableValue(Utf8FromUtf16(pwszId))},
					{flutter::EncodableValue("label"),       flutter::EncodableValue(label)},
					{flutter::EncodableValue("type"),        flutter::EncodableValue(type)},
					{flutter::EncodableValue("sampleRates"), flutter::EncodableValue(std::move(rateList))},
				}));

				PropVariantClear(&varName);
				PropVariantClear(&varFormat);
				SafeRelease(&pProps);
			}

			CoTaskMemFree(pwszId);
			SafeRelease(&pDevice);
		}
	}

	SafeRelease(&pCollection);
	SafeRelease(&pEnumerator);

	return SUCCEEDED(hr) ? S_OK : hr;
}

HRESULT IsEncoderSupported(const std::string& encoderName, bool* supported)
{
	MFT_REGISTER_TYPE_INFO typeLookup = {};
	typeLookup.guidMajorType = MFMediaType_Audio;

	if      (encoderName == AudioEncoder::aacLc)   typeLookup.guidSubtype = MFAudioFormat_AAC;
	else if (encoderName == AudioEncoder::amrNb)   typeLookup.guidSubtype = MFAudioFormat_AMR_NB;
	else if (encoderName == AudioEncoder::amrWb)   typeLookup.guidSubtype = MFAudioFormat_AMR_WB;
	else if (encoderName == AudioEncoder::opus)    typeLookup.guidSubtype = MFAudioFormat_Opus;
	else if (encoderName == AudioEncoder::flac)    typeLookup.guidSubtype = MFAudioFormat_FLAC;
	else if (encoderName == AudioEncoder::pcm16bits ||
	         encoderName == AudioEncoder::wav) {
		*supported = true;
		return S_OK;
	}
	else {
		*supported = false;
		return S_OK;
	}

	DWORD dwFlags =
		(MFT_ENUM_FLAG_ALL & (~MFT_ENUM_FLAG_FIELDOFUSE)) |
		MFT_ENUM_FLAG_SORTANDFILTER;

	IMFActivate** ppMFTActivate = NULL;
	UINT32        numMFTActivate = 0;

	HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET);
	if (FAILED(hr)) return hr;

	hr = MFTEnumEx(
		MFT_CATEGORY_AUDIO_ENCODER,
		dwFlags,
		NULL,
		&typeLookup,
		&ppMFTActivate,
		&numMFTActivate
	);

	if (SUCCEEDED(hr))
	{
		*supported = numMFTActivate != 0;
	}

	for (UINT32 i = 0; i < numMFTActivate; i++)
	{
		SafeRelease(ppMFTActivate[i]);
	}
	CoTaskMemFree(ppMFTActivate);

	MFShutdown();
	return hr;
}

HRESULT AdjustConfigToDeviceCaps(RecordConfig& config)
{
	IMMDeviceEnumerator* pEnumerator = NULL;
	IMMDevice*           pDevice     = NULL;
	IPropertyStore*      pProps      = NULL;

	HRESULT hr = CoCreateInstance(
		__uuidof(MMDeviceEnumerator), NULL,
		CLSCTX_ALL, IID_PPV_ARGS(&pEnumerator)
	);

	if (SUCCEEDED(hr))
	{
		if (config.deviceId.empty())
			hr = pEnumerator->GetDefaultAudioEndpoint(eCapture, eCommunications, &pDevice);
		else
		{
			auto deviceId = std::wstring(config.deviceId.begin(), config.deviceId.end());
			hr = pEnumerator->GetDevice(deviceId.c_str(), &pDevice);
		}
	}

	if (SUCCEEDED(hr))
		hr = pDevice->OpenPropertyStore(STGM_READ, &pProps);

	if (SUCCEEDED(hr))
	{
		PROPVARIANT varFormat;
		PropVariantInit(&varFormat);

		if (SUCCEEDED(pProps->GetValue(kAudioEngineDeviceFormat, &varFormat)) &&
		    varFormat.vt == VT_BLOB && varFormat.blob.cbSize >= sizeof(WAVEFORMATEX))
		{
			auto* wf = reinterpret_cast<const WAVEFORMATEX*>(varFormat.blob.pBlobData);
			if (config.numChannels > (int)wf->nChannels)
				config.numChannels = (int)wf->nChannels;
		}

		PropVariantClear(&varFormat);
	}

	SafeRelease(&pProps);
	SafeRelease(&pDevice);
	SafeRelease(&pEnumerator);

	return S_OK; // non-fatal
}

HRESULT AdjustConfigToCodecCaps(RecordConfig& config)
{
	if (config.encoderName == AudioEncoder::amrNb) {
		config.sampleRate  = 8000;
		config.numChannels = 1;
		return S_OK;
	}
	if (config.encoderName == AudioEncoder::amrWb) {
		config.sampleRate  = 16000;
		config.numChannels = 1;
		return S_OK;
	}
	if (config.encoderName == AudioEncoder::pcm16bits ||
	    config.encoderName == AudioEncoder::wav) {
		return S_OK;
	}

	GUID subtypeGuid = GUID_NULL;
	if (config.encoderName == AudioEncoder::aacLc ||
	    config.encoderName == AudioEncoder::aacEld ||
	    config.encoderName == AudioEncoder::aacHe) {
		subtypeGuid = MFAudioFormat_AAC;
	} else if (config.encoderName == AudioEncoder::flac) {
		subtypeGuid = MFAudioFormat_FLAC;
	} else {
		return S_OK;
	}

	std::vector<CodecCapsEntry> caps;
	{
		std::lock_guard<std::mutex> lock(gCapsMutex);
		auto it = gCapsCache.find(config.encoderName);
		if (it != gCapsCache.end())
			caps = it->second;
	}

	if (caps.empty())
	{
		auto fetched = FetchCodecCaps(subtypeGuid);
		std::lock_guard<std::mutex> lock(gCapsMutex);
		// Another thread may have populated the cache while we were fetching.
		auto result = gCapsCache.emplace(config.encoderName, std::move(fetched));
		caps = result.first->second;
	}

	if (caps.empty())
		return MF_E_NOT_FOUND;

	size_t idx = SelectBestCaps(caps, (UINT32)config.numChannels, (UINT32)config.sampleRate, (UINT32)config.bitRate);
	if (idx != SIZE_MAX)
	{
		config.numChannels = (int)caps[idx].channels;
		config.sampleRate  = (int)caps[idx].sampleRate;
		if (caps[idx].bitRate > 0) config.bitRate = (int)caps[idx].bitRate;
	}

	return S_OK;
}

void WarmCodecCapsAsync()
{
	std::thread([]() {
		// Fresh thread: nobody else initializes COM here.
		CoInitializeEx(nullptr, COINIT_MULTITHREADED);

		if (SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET)))
		{
			static const struct { const char* name; GUID guid; } kEncoders[] = {
				{AudioEncoder::aacLc,  MFAudioFormat_AAC},
				{AudioEncoder::aacEld, MFAudioFormat_AAC},
				{AudioEncoder::aacHe,  MFAudioFormat_AAC},
				{AudioEncoder::flac,   MFAudioFormat_FLAC},
			};

			for (const auto& enc : kEncoders)
			{
				auto caps = FetchCodecCaps(enc.guid);
				std::lock_guard<std::mutex> lock(gCapsMutex);
				gCapsCache.emplace(enc.name, std::move(caps));
			}

			MFShutdown();
		}

		CoUninitialize();
	}).detach();
}

} // namespace AudioDevice
} // namespace record_windows
