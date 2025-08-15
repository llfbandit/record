#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <iostream>
#include <comdef.h>

void PrintError(HRESULT hr, const char* operation) {
    _com_error err(hr);
    std::wcout L<< L"Error in " << operation << L": " << err.ErrorMessage() << std::endl;
}

int main() {
    std::wcout << L"Testing Windows Audio Access..." << std::endl;
    
    // Initialize COM
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hr)) {
        PrintError(hr, "CoInitializeEx");
        return -1;
    }
    
    // Create device enumerator
    IMMDeviceEnumerator* pEnumerator = nullptr;
    hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                          __uuidof(IMMDeviceEnumerator), 
                          reinterpret_cast<void**>(&pEnumerator));
    
    if (FAILED(hr)) {
        PrintError(hr, "CoCreateInstance(MMDeviceEnumerator)");
        CoUninitialize();
        return -1;
    }
    
    std::wcout << L"✓ Created device enumerator" << std::endl;
    
    // Get default capture device
    IMMDevice* pDevice = nullptr;
    hr = pEnumerator->GetDefaultAudioEndpoint(eCapture, eMultimedia, &pDevice);
    
    if (FAILED(hr)) {
        PrintError(hr, "GetDefaultAudioEndpoint");
        pEnumerator->Release();
        CoUninitialize();
        return -1;
    }
    
    std::wcout << L"✓ Got default capture device" << std::endl;
    
    // Activate audio client
    IAudioClient* pAudioClient = nullptr;
    hr = pDevice->Activate(__uuidof(IAudioClient), CLSCTX_ALL, 
                          nullptr, reinterpret_cast<void**>(&pAudioClient));
    
    if (FAILED(hr)) {
        PrintError(hr, "Device->Activate(IAudioClient)");
        pDevice->Release();
        pEnumerator->Release();
        CoUninitialize();
        return -1;
    }
    
    std::wcout << L"✓ Activated audio client" << std::endl;
    
    // Test format support
    WAVEFORMATEX format = {};
    format.wFormatTag = WAVE_FORMAT_PCM;
    format.nChannels = 2;
    format.nSamplesPerSec = 48000;
    format.wBitsPerSample = 16;
    format.nBlockAlign = format.nChannels * format.wBitsPerSample / 8;
    format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;
    
    WAVEFORMATEX* pClosestMatch = nullptr;
    hr = pAudioClient->IsFormatSupported(AUDCLNT_SHAREMODE_SHARED, &format, &pClosestMatch);
    
    if (hr == S_OK) {
        std::wcout << L"✓ 48kHz stereo PCM format is supported" << std::endl;
    } else if (hr == S_FALSE) {
        std::wcout << L"⚠ 48kHz stereo PCM not supported, but closest match available" << std::endl;
        if (pClosestMatch) {
            std::wcout << L"  Closest: " << pClosestMatch->nSamplesPerSec << L"Hz, " 
                      << pClosestMatch->nChannels << L" channels, " 
                      << pClosestMatch->wBitsPerSample << L" bits" << std::endl;
            CoTaskMemFree(pClosestMatch);
        }
    } else {
        PrintError(hr, "IsFormatSupported");
    }
    
    // Try to initialize
    hr = pAudioClient->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                 AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
                                 100000, // 10ms
                                 0,
                                 &format,
                                 nullptr);
    
    if (SUCCEEDED(hr)) {
        std::wcout << L"✓ Audio client initialized successfully" << std::endl;
    } else {
        PrintError(hr, "AudioClient->Initialize");
    }
    
    // Cleanup
    pAudioClient->Release();
    pDevice->Release();
    pEnumerator->Release();
    CoUninitialize();
    
    std::wcout << L"\nDone. Press any key to exit..." << std::endl;
    std::cin.get();
    
    return 0;
}
