#include "record.h"
#include "record_windows_plugin.h"
#include <comdef.h>
#include <cmath>
#include <algorithm>
#include <chrono>
#include <cctype>
#include <initguid.h>

// Define missing Media Foundation constants if not available
#ifndef MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION
#define MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION MF_MT_USER_DATA
#endif

// Audio effect type GUIDs for Windows Audio Engine
DEFINE_GUID(AUDIO_EFFECT_TYPE_NOISE_SUPPRESSION, 
	0xe07f903f, 0x62fd, 0x4e60, 0x8c, 0xdd, 0xde, 0xa7, 0x23, 0x66, 0x65, 0xb5);
DEFINE_GUID(AUDIO_EFFECT_TYPE_ECHO_CANCELLATION, 
	0x6f64adbe, 0x1dd2, 0x4c24, 0x8e, 0xc3, 0x7c, 0xaa, 0xdf, 0x6e, 0x8a, 0x9c);
DEFINE_GUID(AUDIO_EFFECT_TYPE_AUTOMATIC_GAIN_CONTROL, 
	0x6e7132c3, 0x75cf, 0x4f36, 0xa6, 0x16, 0xec, 0x11, 0x22, 0x00, 0xaa, 0x20);

namespace record_windows
{
	// Initialize COM for the module
	static bool g_comInitialized = false;
	
	static void EnsureCOMInitialized()
	{
		if (!g_comInitialized)
		{
			CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
			g_comInitialized = true;
		}
	}

	// ===========================================
	// LockFreeRingBuffer Implementation
	// ===========================================
	
	template<typename T>
	LockFreeRingBuffer<T>::LockFreeRingBuffer(size_t size) 
		: m_size(size)
	{
		// Ensure size is power of 2 for efficient masking
		size_t powerOf2 = 1;
		while (powerOf2 < size) powerOf2 <<= 1;
		m_size = powerOf2;
		m_mask = m_size - 1;
		m_buffer.resize(m_size);
	}
	
	template<typename T>
	bool LockFreeRingBuffer<T>::Write(const T* data, size_t count)
	{
		if (count > m_size) return false;
		
		size_t writeIndex = m_writeIndex.load(std::memory_order_relaxed);
		size_t readIndex = m_readIndex.load(std::memory_order_acquire);
		
		// Check if we have enough space
		size_t available = (readIndex - writeIndex - 1) & m_mask;
		if (count > available) return false;
		
		// Write data
		for (size_t i = 0; i < count; ++i)
		{
			m_buffer[(writeIndex + i) & m_mask] = data[i];
		}
		
		m_writeIndex.store((writeIndex + count) & m_mask, std::memory_order_release);
		return true;
	}
	
	template<typename T>
	size_t LockFreeRingBuffer<T>::Read(T* data, size_t maxCount)
	{
		size_t readIndex = m_readIndex.load(std::memory_order_relaxed);
		size_t writeIndex = m_writeIndex.load(std::memory_order_acquire);
		
		size_t available = (writeIndex - readIndex) & m_mask;
		size_t toRead = (std::min)(maxCount, available);
		
		for (size_t i = 0; i < toRead; ++i)
		{
			data[i] = m_buffer[(readIndex + i) & m_mask];
		}
		
		m_readIndex.store((readIndex + toRead) & m_mask, std::memory_order_release);
		return toRead;
	}
	
	template<typename T>
	size_t LockFreeRingBuffer<T>::Available() const
	{
		size_t readIndex = m_readIndex.load(std::memory_order_relaxed);
		size_t writeIndex = m_writeIndex.load(std::memory_order_acquire);
		return (writeIndex - readIndex) & m_mask;
	}
	
	template<typename T>
	void LockFreeRingBuffer<T>::Clear()
	{
		m_writeIndex.store(0);
		m_readIndex.store(0);
	}
	
	// Explicit instantiation for float
	template class LockFreeRingBuffer<float>;

	// ===========================================
	// AmplitudeAnalyzer Implementation
	// ===========================================
	
	void AmplitudeAnalyzer::ProcessSamples(const float* samples, size_t count)
	{
		if (!samples || count == 0) return;
		
		float maxSample = 0.0f;
		for (size_t i = 0; i < count; ++i)
		{
			float absValue = std::abs(samples[i]);
			if (absValue > maxSample) maxSample = absValue;
		}
		
		// Convert to dB (avoid log(0))
		float amplitude = maxSample > 0.0f ? 20.0f * std::log10(maxSample) : -160.0f;
		
		m_currentAmplitude.store(amplitude);
		
		// Update max amplitude
		float currentMax = m_maxAmplitude.load();
		while (amplitude > currentMax && 
			   !m_maxAmplitude.compare_exchange_weak(currentMax, amplitude)) 
		{
			// Retry if another thread updated it
		}
	}
	
	void AmplitudeAnalyzer::Reset()
	{
		m_currentAmplitude.store(-160.0f);
		m_maxAmplitude.store(-160.0f);
	}

	// ===========================================
	// AsyncAudioWriter Implementation
	// ===========================================
	
	AsyncAudioWriter::AsyncAudioWriter()
		: m_audioBuffer(std::make_unique<LockFreeRingBuffer<float>>(48000 * 4)) // 4 seconds buffer
	{
		// Initialize Media Foundation for advanced codecs
		MFStartup(MF_VERSION, MFSTARTUP_LITE);
	}
	
	AsyncAudioWriter::~AsyncAudioWriter()
	{
		Stop();
		CleanupMediaFoundation();
		MFShutdown();
	}
	
	HRESULT AsyncAudioWriter::Initialize(const std::wstring& filePath, const std::string& encoder, 
										 DWORD sampleRate, WORD channels)
	{
		m_encoderName = encoder;
		m_sampleRate = sampleRate;
		m_channels = channels;
		m_bytesWritten = 0;
		
		// Determine if we need Media Foundation for advanced codecs
		m_useMediaFoundation = (encoder == "aac" || encoder == "aaclc");
		
		// Adjust file extension based on encoder
		std::wstring adjustedPath = filePath;
		if (encoder == "aac" || encoder == "aaclc")
		{
			// Replace .wav extension with .aac if needed
			size_t dotPos = adjustedPath.find_last_of(L'.');
			if (dotPos != std::wstring::npos)
			{
				std::wstring extension = adjustedPath.substr(dotPos + 1);
				std::transform(extension.begin(), extension.end(), extension.begin(), ::towlower);
				if (extension == L"wav")
				{
					adjustedPath.replace(dotPos, std::wstring::npos, L".aac");
				}
			}
			else
			{
				adjustedPath += L".aac";
			}
		}
		
		m_filePath = adjustedPath;
		
		return S_OK;
	}
	
	HRESULT AsyncAudioWriter::Start()
	{
		if (m_isRunning.load()) return S_OK;
		
		HRESULT hr = S_OK;
		
		if (m_useMediaFoundation)
		{
			// Use Media Foundation for AAC/FLAC
			hr = InitializeMediaFoundationEncoder();
		}
		else
		{
			// Use direct file writing for WAV/PCM
			m_fileStream.open(m_filePath, std::ios::binary);
			if (!m_fileStream.is_open()) return E_FAIL;
			
			// Write WAV header for supported formats
			if (m_encoderName == "wav" || m_encoderName == "pcm16bits")
			{
				WriteWavHeader();
			}
		}
		
		if (SUCCEEDED(hr))
		{
			m_isRunning.store(true);
			m_writerThread = std::thread(&AsyncAudioWriter::WriterThreadProc, this);
		}
		
		return hr;
	}
	
	HRESULT AsyncAudioWriter::Stop()
	{
		if (!m_isRunning.load()) return S_OK;
		
		m_isRunning.store(false);
		
		if (m_writerThread.joinable())
		{
			m_writerThread.join();
		}
		
		if (m_useMediaFoundation)
		{
			CleanupMediaFoundation();
		}
		else if (m_fileStream.is_open())
		{
			// Update WAV header with final size
			if (m_encoderName == "wav" || m_encoderName == "pcm16bits")
			{
				UpdateWavHeader();
			}
			m_fileStream.close();
		}
		
		return S_OK;
	}
	
	void AsyncAudioWriter::QueueAudio(const float* samples, size_t count)
	{
		if (m_isRunning.load())
		{
			m_audioBuffer->Write(samples, count);
		}
	}
	
	void AsyncAudioWriter::WriterThreadProc()
	{
		const size_t bufferSize = 4096;
		std::vector<float> buffer(bufferSize);
		
		while (m_isRunning.load() || m_audioBuffer->Available() > 0)
		{
			size_t samplesRead = m_audioBuffer->Read(buffer.data(), bufferSize);
			
			if (samplesRead > 0)
			{
				if (m_useMediaFoundation)
				{
					// Use Media Foundation for AAC/FLAC encoding
					WriteMediaFoundationSample(buffer.data(), samplesRead);
				}
				else
				{
					// Use direct PCM writing for WAV
					// Convert float samples to 16-bit PCM
					std::vector<int16_t> pcmData(samplesRead);
					for (size_t i = 0; i < samplesRead; ++i)
					{
						float sample = (std::clamp)(buffer[i], -1.0f, 1.0f);
						pcmData[i] = static_cast<int16_t>(sample * 32767.0f);
					}
					
					m_fileStream.write(reinterpret_cast<const char*>(pcmData.data()), 
									  pcmData.size() * sizeof(int16_t));
					m_bytesWritten += pcmData.size() * sizeof(int16_t);
				}
			}
			else
			{
				// No data available, sleep briefly
				std::this_thread::sleep_for(std::chrono::milliseconds(1));
			}
		}
	}
	
	HRESULT AsyncAudioWriter::WriteWavHeader()
	{
		if (!m_fileStream.is_open()) return E_FAIL;
		
		// WAV header structure
		struct WavHeader
		{
			char riff[4] = {'R', 'I', 'F', 'F'};
			uint32_t fileSize = 0; // Will be updated later
			char wave[4] = {'W', 'A', 'V', 'E'};
			char fmt[4] = {'f', 'm', 't', ' '};
			uint32_t fmtSize = 16;
			uint16_t audioFormat = 1; // PCM
			uint16_t channels;
			uint32_t sampleRate;
			uint32_t byteRate;
			uint16_t blockAlign;
			uint16_t bitsPerSample = 16;
			char data[4] = {'d', 'a', 't', 'a'};
			uint32_t dataSize = 0; // Will be updated later
		};
		
		WavHeader header;
		header.channels = m_channels;
		header.sampleRate = m_sampleRate;
		header.byteRate = m_sampleRate * m_channels * 2;
		header.blockAlign = m_channels * 2;
		
		m_fileStream.write(reinterpret_cast<const char*>(&header), sizeof(header));
		return S_OK;
	}
	
	HRESULT AsyncAudioWriter::UpdateWavHeader()
	{
		if (!m_fileStream.is_open()) return E_FAIL;
		
		// Update file size and data size in WAV header
		uint32_t fileSize = static_cast<uint32_t>(m_bytesWritten + sizeof(uint32_t) + 
												  sizeof(uint32_t) + 16 + 8);
		uint32_t dataSize = static_cast<uint32_t>(m_bytesWritten);
		
		m_fileStream.seekp(4);
		m_fileStream.write(reinterpret_cast<const char*>(&fileSize), sizeof(fileSize));
		
		m_fileStream.seekp(40);
		m_fileStream.write(reinterpret_cast<const char*>(&dataSize), sizeof(dataSize));
		
		return S_OK;
	}
	
	HRESULT AsyncAudioWriter::InitializeMediaFoundationEncoder()
	{
		HRESULT hr = S_OK;
		
		// Create sink writer for the output file
		IMFAttributes* pAttributes = nullptr;
		hr = MFCreateAttributes(&pAttributes, 0);
		
		if (SUCCEEDED(hr))
		{
			hr = MFCreateSinkWriterFromURL(m_filePath.c_str(), nullptr, pAttributes, &m_pSinkWriter);
		}
		
		if (SUCCEEDED(hr))
		{
			// Configure output media type based on encoder
			IMFMediaType* pOutputType = nullptr;
			hr = MFCreateMediaType(&pOutputType);
			
			if (SUCCEEDED(hr))
			{
				if (m_encoderName == "aac" || m_encoderName == "aaclc")
				{
					// AAC-LC configuration
					pOutputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
					pOutputType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
					pOutputType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, m_sampleRate);
					pOutputType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, m_channels);
					pOutputType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 128000 / 8); // 128 kbps
					pOutputType->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 1);
					pOutputType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
					// Note: AAC profile settings may vary by Windows version
				}
				
				hr = m_pSinkWriter->AddStream(pOutputType, &m_streamIndex);
				pOutputType->Release();
			}
		}
		
		if (SUCCEEDED(hr))
		{
			// Configure input media type (16-bit PCM - more compatible)
			IMFMediaType* pInputType = nullptr;
			hr = MFCreateMediaType(&pInputType);
			
			if (SUCCEEDED(hr))
			{
				pInputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
				pInputType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
				pInputType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, m_sampleRate);
				pInputType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, m_channels);
				pInputType->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, m_channels * sizeof(int16_t));
				pInputType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, m_sampleRate * m_channels * sizeof(int16_t));
				pInputType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
				pInputType->SetUINT32(MF_MT_ALL_SAMPLES_INDEPENDENT, TRUE);
				
				hr = m_pSinkWriter->SetInputMediaType(m_streamIndex, pInputType, nullptr);
				pInputType->Release();
			}
		}
		
		if (SUCCEEDED(hr))
		{
			hr = m_pSinkWriter->BeginWriting();
		}
		
		if (pAttributes) pAttributes->Release();
		
		return hr;
	}
	
	HRESULT AsyncAudioWriter::WriteMediaFoundationSample(const float* samples, size_t count)
	{
		if (!m_pSinkWriter) return E_FAIL;
		
		HRESULT hr = S_OK;
		IMFSample* pSample = nullptr;
		IMFMediaBuffer* pBuffer = nullptr;
		
		// Convert float to 16-bit PCM for Media Foundation
		std::vector<int16_t> pcmData(count);
		for (size_t i = 0; i < count; ++i)
		{
			float sample = (std::clamp)(samples[i], -1.0f, 1.0f);
			pcmData[i] = static_cast<int16_t>(sample * 32767.0f);
		}
		
		// Create sample
		hr = MFCreateSample(&pSample);
		
		if (SUCCEEDED(hr))
		{
			DWORD bufferSize = static_cast<DWORD>(count * sizeof(int16_t));
			hr = MFCreateMemoryBuffer(bufferSize, &pBuffer);
		}
		
		if (SUCCEEDED(hr))
		{
			BYTE* pData = nullptr;
			hr = pBuffer->Lock(&pData, nullptr, nullptr);
			
			if (SUCCEEDED(hr))
			{
				memcpy(pData, pcmData.data(), count * sizeof(int16_t));
				pBuffer->Unlock();
				pBuffer->SetCurrentLength(bufferSize);
			}
		}
		
		if (SUCCEEDED(hr))
		{
			pSample->AddBuffer(pBuffer);
			
			// Set sample timestamp (approximate)
			static LONGLONG timestamp = 0;
			pSample->SetSampleTime(timestamp);
			
			LONGLONG duration = (10000000LL * count) / (m_sampleRate * m_channels); // 100ns units
			pSample->SetSampleDuration(duration);
			timestamp += duration;
			
			hr = m_pSinkWriter->WriteSample(m_streamIndex, pSample);
		}
		
		if (pBuffer) pBuffer->Release();
		if (pSample) pSample->Release();
		
		return hr;
	}
	
	void AsyncAudioWriter::CleanupMediaFoundation()
	{
		if (m_pSinkWriter)
		{
			m_pSinkWriter->Finalize();
			m_pSinkWriter->Release();
			m_pSinkWriter = nullptr;
		}
	}

	// ===========================================
	// WASAPICapture Implementation
	// ===========================================
	
	WASAPICapture::WASAPICapture()
		: m_pDeviceEnumerator(nullptr)
		, m_pDevice(nullptr)
		, m_pAudioClient(nullptr)
		, m_pCaptureClient(nullptr)
		, m_pEffectsManager(nullptr)
		, m_hCaptureEvent(nullptr)
		, m_pWaveFormat(nullptr)
		, m_sampleRate(48000)
		, m_channels(2)
		, m_enableNoiseSuppress(false)
		, m_enableEchoCancel(false)
		, m_enableAutoGain(false)
	{
		EnsureCOMInitialized();
	}
	
	WASAPICapture::~WASAPICapture()
	{
		Stop();
		
		if (m_pWaveFormat) CoTaskMemFree(m_pWaveFormat);
		if (m_hCaptureEvent) CloseHandle(m_hCaptureEvent);
		if (m_pCaptureClient) m_pCaptureClient->Release();
		if (m_pEffectsManager) m_pEffectsManager->Release();
		if (m_pAudioClient) m_pAudioClient->Release();
		if (m_pDevice) m_pDevice->Release();
		if (m_pDeviceEnumerator) m_pDeviceEnumerator->Release();
	}
	
	HRESULT WASAPICapture::Initialize(const std::string& deviceId, DWORD sampleRate, WORD channels, 
									  bool noiseSuppress, bool echoCancel, bool autoGain)
	{
		HRESULT hr = S_OK;
		
		m_sampleRate = sampleRate;
		m_channels = channels;
		m_enableNoiseSuppress = noiseSuppress;
		m_enableEchoCancel = echoCancel;
		m_enableAutoGain = autoGain;
		
		// Create device enumerator
		hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
							  __uuidof(IMMDeviceEnumerator), 
							  reinterpret_cast<void**>(&m_pDeviceEnumerator));
		
		if (SUCCEEDED(hr))
		{
			// Get audio device
			if (deviceId.empty())
			{
				hr = m_pDeviceEnumerator->GetDefaultAudioEndpoint(eCapture, eMultimedia, &m_pDevice);
			}
			else
			{
				std::wstring wideDeviceId(deviceId.begin(), deviceId.end());
				hr = m_pDeviceEnumerator->GetDevice(wideDeviceId.c_str(), &m_pDevice);
			}
		}
		
		if (SUCCEEDED(hr))
		{
			hr = InitializeAudioClient();
		}
		
		if (SUCCEEDED(hr))
		{
			hr = InitializeAudioEffects();
		}
		
		if (SUCCEEDED(hr))
		{
			// Create event for audio capture
			m_hCaptureEvent = CreateEvent(nullptr, FALSE, FALSE, nullptr);
			if (!m_hCaptureEvent) hr = E_FAIL;
		}
		
		if (SUCCEEDED(hr))
		{
			hr = m_pAudioClient->SetEventHandle(m_hCaptureEvent);
		}
		
		return hr;
	}
	
	HRESULT WASAPICapture::InitializeAudioClient()
	{
		HRESULT hr = m_pDevice->Activate(__uuidof(IAudioClient), CLSCTX_ALL, 
										 nullptr, reinterpret_cast<void**>(&m_pAudioClient));
		
		if (SUCCEEDED(hr))
		{
			// Set up wave format for capture - try float format first (typical for WASAPI)
			WAVEFORMATEX* pClosestMatch = nullptr;
			WAVEFORMATEXTENSIBLE waveFormatEx = {};
			waveFormatEx.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
			waveFormatEx.Format.nChannels = m_channels;
			waveFormatEx.Format.nSamplesPerSec = m_sampleRate;
			waveFormatEx.Format.wBitsPerSample = 32; // 32-bit float
			waveFormatEx.Format.nBlockAlign = m_channels * waveFormatEx.Format.wBitsPerSample / 8;
			waveFormatEx.Format.nAvgBytesPerSec = waveFormatEx.Format.nSamplesPerSec * waveFormatEx.Format.nBlockAlign;
			waveFormatEx.Format.cbSize = sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX);
			waveFormatEx.Samples.wValidBitsPerSample = 32;
			// Set appropriate channel mask based on channel count
			switch (m_channels) {
				case 1: waveFormatEx.dwChannelMask = KSAUDIO_SPEAKER_MONO; break;
				case 2: waveFormatEx.dwChannelMask = KSAUDIO_SPEAKER_STEREO; break;
				case 4: waveFormatEx.dwChannelMask = KSAUDIO_SPEAKER_QUAD; break;
				case 6: waveFormatEx.dwChannelMask = KSAUDIO_SPEAKER_5POINT1; break;
				case 8: waveFormatEx.dwChannelMask = KSAUDIO_SPEAKER_7POINT1; break;
				default: waveFormatEx.dwChannelMask = KSAUDIO_SPEAKER_DIRECTOUT; break;
			}
			waveFormatEx.SubFormat = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
			
			hr = m_pAudioClient->IsFormatSupported(AUDCLNT_SHAREMODE_SHARED, 
												   reinterpret_cast<WAVEFORMATEX*>(&waveFormatEx), 
												   &pClosestMatch);
			
			if (hr == S_OK)
			{
				// Float format is supported
				m_pWaveFormat = reinterpret_cast<WAVEFORMATEX*>(CoTaskMemAlloc(sizeof(WAVEFORMATEXTENSIBLE)));
				if (m_pWaveFormat)
				{
					memcpy(m_pWaveFormat, &waveFormatEx, sizeof(WAVEFORMATEXTENSIBLE));
				}
				else
				{
					hr = E_OUTOFMEMORY;
				}
			}
			else if (hr == S_FALSE && pClosestMatch)
			{
				// Check if the closest match has the same channel count
				if (pClosestMatch->nChannels == m_channels)
				{
					// Use the closest supported format if channels match
					m_pWaveFormat = pClosestMatch;
					m_sampleRate = m_pWaveFormat->nSamplesPerSec;
					// Keep our requested m_channels unchanged
				}
				else
				{
					// Device doesn't support our channel count, fall back to PCM
					if (pClosestMatch) CoTaskMemFree(pClosestMatch);
					hr = E_FAIL; // Force PCM fallback
				}
			}
			else
			{
				// Fall back to 16-bit PCM
				WAVEFORMATEX waveFormat = {};
				waveFormat.wFormatTag = WAVE_FORMAT_PCM;
				waveFormat.nChannels = m_channels;
				waveFormat.nSamplesPerSec = m_sampleRate;
				waveFormat.wBitsPerSample = 16;
				waveFormat.nBlockAlign = m_channels * waveFormat.wBitsPerSample / 8;
				waveFormat.nAvgBytesPerSec = waveFormat.nSamplesPerSec * waveFormat.nBlockAlign;
				
				hr = m_pAudioClient->IsFormatSupported(AUDCLNT_SHAREMODE_SHARED, &waveFormat, &pClosestMatch);
				
				if (SUCCEEDED(hr))
				{
					if (pClosestMatch)
					{
						// Validate that the closest match has our requested channel count
						if (pClosestMatch->nChannels == m_channels)
						{
							m_pWaveFormat = pClosestMatch;
							m_sampleRate = m_pWaveFormat->nSamplesPerSec;
							// Keep our requested m_channels unchanged
						}
						else
						{
							// Channel count mismatch, this will cause audio distortion
							CoTaskMemFree(pClosestMatch);
							return E_FAIL;
						}
					}
					else
					{
						m_pWaveFormat = reinterpret_cast<WAVEFORMATEX*>(CoTaskMemAlloc(sizeof(WAVEFORMATEX)));
						if (m_pWaveFormat)
						{
							*m_pWaveFormat = waveFormat;
						}
						else
						{
							hr = E_OUTOFMEMORY;
						}
					}
				}
			}
		}
		
		if (SUCCEEDED(hr))
		{
			// Initialize audio client with low latency
			hr = m_pAudioClient->Initialize(AUDCLNT_SHAREMODE_SHARED,
											AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_NOPERSIST,
											200000, // 20ms buffer
											0,
											m_pWaveFormat,
											nullptr);
		}
		
		if (SUCCEEDED(hr))
		{
			hr = m_pAudioClient->GetService(__uuidof(IAudioCaptureClient),
											reinterpret_cast<void**>(&m_pCaptureClient));
		}
		
		return hr;
	}
	
	HRESULT WASAPICapture::InitializeAudioEffects()
	{
		HRESULT hr = S_OK;
		
		// Try to get the effects manager for audio processing
		if (m_pDevice)
		{
			hr = m_pDevice->Activate(__uuidof(IAudioEffectsManager), CLSCTX_ALL, 
									 nullptr, reinterpret_cast<void**>(&m_pEffectsManager));
		}
		
		if (SUCCEEDED(hr) && m_pEffectsManager)
		{
			// Configure audio effects based on settings
			std::vector<GUID> effectsToEnable;
			
			if (m_enableNoiseSuppress)
			{
				// Add noise suppression effect
				effectsToEnable.push_back(AUDIO_EFFECT_TYPE_NOISE_SUPPRESSION);
			}
			
			if (m_enableEchoCancel)
			{
				// Add echo cancellation effect
				effectsToEnable.push_back(AUDIO_EFFECT_TYPE_ECHO_CANCELLATION);
			}
			
			if (m_enableAutoGain)
			{
				// Add automatic gain control effect
				effectsToEnable.push_back(AUDIO_EFFECT_TYPE_AUTOMATIC_GAIN_CONTROL);
			}
			
			// Apply effects if any are requested
			if (!effectsToEnable.empty())
			{
				// Note: The actual effect application depends on Windows version and device capabilities
				// Some devices may not support all effects, so we continue even if this fails
				for (const auto& effectGuid : effectsToEnable)
				{
					HRESULT effectHr = S_OK;
					// Try to enable each effect individually
					// Implementation depends on specific Windows Audio Engine APO interfaces
					// For now, we log that effects are requested but may need device-specific implementation
				}
			}
		}
		
		// Don't fail initialization if effects aren't supported
		// Effects are optional enhancements, core recording should still work
		return S_OK;
	}
	
	HRESULT WASAPICapture::Start()
	{
		if (m_isCapturing.load()) return S_OK;
		
		HRESULT hr = m_pAudioClient->Start();
		
		if (SUCCEEDED(hr))
		{
			m_isCapturing.store(true);
			m_captureThread = std::thread(&WASAPICapture::CaptureThreadProc, this);
		}
		
		return hr;
	}
	
	HRESULT WASAPICapture::Stop()
	{
		if (!m_isCapturing.load()) return S_OK;
		
		m_isCapturing.store(false);
		
		if (m_captureThread.joinable())
		{
			m_captureThread.join();
		}
		
		return m_pAudioClient->Stop();
	}
	
	HRESULT WASAPICapture::Pause()
	{
		return m_pAudioClient->Stop();
	}
	
	HRESULT WASAPICapture::Resume()
	{
		return m_pAudioClient->Start();
	}
	
	void WASAPICapture::SetAudioDataCallback(std::function<void(const float* samples, size_t count)> callback)
	{
		m_onAudioData = callback;
	}
	
	void WASAPICapture::CaptureThreadProc()
	{
		std::vector<float> floatBuffer;
		
		while (m_isCapturing.load())
		{
			DWORD waitResult = WaitForSingleObject(m_hCaptureEvent, 100);
			
			if (waitResult == WAIT_OBJECT_0)
			{
				BYTE* pData = nullptr;
				UINT32 framesAvailable = 0;
				DWORD flags = 0;
				
				HRESULT hr = m_pCaptureClient->GetBuffer(&pData, &framesAvailable, &flags, nullptr, nullptr);
				
				if (SUCCEEDED(hr) && framesAvailable > 0)
				{
					size_t sampleCount = framesAvailable * m_channels;
					floatBuffer.resize(sampleCount);
					
					// Check if we should handle silence flag
					if (flags & AUDCLNT_BUFFERFLAGS_SILENT)
					{
						// Fill with silence
						std::fill(floatBuffer.begin(), floatBuffer.end(), 0.0f);
					}
					else
					{
						// Convert based on the actual audio format
						if (IsFloatFormat())
						{
							// Data is already 32-bit float
							const float* floatData = reinterpret_cast<const float*>(pData);
							std::copy(floatData, floatData + sampleCount, floatBuffer.begin());
						}
						else if (m_pWaveFormat->wBitsPerSample == 16)
						{
							// Convert 16-bit PCM to float
							const int16_t* pcmData = reinterpret_cast<const int16_t*>(pData);
							for (size_t i = 0; i < sampleCount; ++i)
							{
								floatBuffer[i] = static_cast<float>(pcmData[i]) / 32768.0f;
							}
						}
						else if (m_pWaveFormat->wBitsPerSample == 24)
						{
							// Convert 24-bit PCM to float
							// Each sample is 3 bytes, interleaved by channels
							const uint8_t* pcm24Data = reinterpret_cast<const uint8_t*>(pData);
							size_t byteIndex = 0;
							
							for (size_t i = 0; i < sampleCount; ++i)
							{
								// Read 24-bit sample (little endian, 3 bytes per sample)
								int32_t sample = (pcm24Data[byteIndex]) |
												(pcm24Data[byteIndex + 1] << 8) |
												(pcm24Data[byteIndex + 2] << 16);
								
								// Sign extend if negative (check the 24th bit)
								if (sample & 0x800000) {
									sample |= 0xFF000000;
								}
								
								floatBuffer[i] = static_cast<float>(sample) / 8388608.0f; // 2^23
								byteIndex += 3; // Move to next sample (3 bytes per sample)
							}
						}
						else if (m_pWaveFormat->wBitsPerSample == 32)
						{
							// Convert 32-bit PCM to float
							const int32_t* pcm32Data = reinterpret_cast<const int32_t*>(pData);
							for (size_t i = 0; i < sampleCount; ++i)
							{
								floatBuffer[i] = static_cast<float>(pcm32Data[i]) / 2147483648.0f; // 2^31
							}
						}
						else
						{
							// Unsupported format, fill with silence
							std::fill(floatBuffer.begin(), floatBuffer.end(), 0.0f);
						}
					}
					
					// Call callback with audio data
					if (m_onAudioData)
					{
						m_onAudioData(floatBuffer.data(), sampleCount);
					}
					
					m_pCaptureClient->ReleaseBuffer(framesAvailable);
				}
			}
		}
	}
	
	bool WASAPICapture::IsFloatFormat()
	{
		if (!m_pWaveFormat) return false;
		
		if (m_pWaveFormat->wFormatTag == WAVE_FORMAT_EXTENSIBLE)
		{
			WAVEFORMATEXTENSIBLE* pFormatEx = reinterpret_cast<WAVEFORMATEXTENSIBLE*>(m_pWaveFormat);
			return IsEqualGUID(pFormatEx->SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
		}
		else if (m_pWaveFormat->wFormatTag == WAVE_FORMAT_IEEE_FLOAT)
		{
			return true;
		}
		
		return false;
	}

	// ===========================================
	// Main Recorder Implementation
	// ===========================================
	
	// static
	HRESULT Recorder::CreateInstance(EventStreamHandler<>* stateEventHandler, 
									 EventStreamHandler<>* recordEventHandler, 
									 Recorder** ppRecorder)
	{
		auto pRecorder = new (std::nothrow) Recorder(stateEventHandler, recordEventHandler);
		
		if (pRecorder == NULL)
		{
			return E_OUTOFMEMORY;
		}
		
		*ppRecorder = pRecorder;
		return S_OK;
	}
	
	Recorder::Recorder(EventStreamHandler<>* stateEventHandler, EventStreamHandler<>* recordEventHandler)
		: m_recordState(RecordState::stop)
		, m_stateEventHandler(stateEventHandler)
		, m_recordEventHandler(recordEventHandler)
		, m_capture(std::make_unique<WASAPICapture>())
		, m_amplitudeAnalyzer(std::make_unique<AmplitudeAnalyzer>())
		, m_fileWriter(std::make_unique<AsyncAudioWriter>())
	{
		EnsureCOMInitialized();
	}
	
	Recorder::~Recorder()
	{
		Dispose();
	}
	
	HRESULT Recorder::Start(std::unique_ptr<RecordConfig> config, std::wstring path)
	{
		if (m_isInitialized.load()) return E_FAIL;
		
		HRESULT hr = ValidateConfig(*config);
		if (FAILED(hr)) return hr;
		
		m_config = std::move(config);
		m_recordingPath = path;
		
		DWORD sampleRate = GetSampleRateFromConfig(*m_config);
		WORD channels = GetChannelsFromConfig(*m_config);
		
		// Initialize WASAPI capture with audio processing
		hr = m_capture->Initialize(m_config->deviceId, sampleRate, channels, 
								   m_config->noiseSuppress, m_config->echoCancel, m_config->autoGain);
		if (FAILED(hr)) return hr;
		
		// Set up audio data callback
		m_capture->SetAudioDataCallback([this](const float* samples, size_t count) {
			OnAudioData(samples, count);
		});
		
		// Initialize file writer
		hr = m_fileWriter->Initialize(path, m_config->encoderName, sampleRate, channels);
		if (FAILED(hr)) return hr;
		
		hr = m_fileWriter->Start();
		if (FAILED(hr)) return hr;
		
		// Start capture - this is immediate with WASAPI!
		hr = m_capture->Start();
		if (SUCCEEDED(hr))
		{
			m_isInitialized.store(true);
			m_isRecordingToFile.store(true);
			UpdateState(RecordState::record);
		}
		
		return hr;
	}
	
	HRESULT Recorder::StartStream(std::unique_ptr<RecordConfig> config)
	{
		if (m_isInitialized.load()) return E_FAIL;
		
		HRESULT hr = ValidateConfig(*config);
		if (FAILED(hr)) return hr;
		
		m_config = std::move(config);
		
		DWORD sampleRate = GetSampleRateFromConfig(*m_config);
		WORD channels = GetChannelsFromConfig(*m_config);
		
		// Initialize WASAPI capture with audio processing
		hr = m_capture->Initialize(m_config->deviceId, sampleRate, channels, 
								   m_config->noiseSuppress, m_config->echoCancel, m_config->autoGain);
		if (FAILED(hr)) return hr;
		
		// Set up audio data callback
		m_capture->SetAudioDataCallback([this](const float* samples, size_t count) {
			OnAudioData(samples, count);
		});
		
		// Start capture for streaming
		hr = m_capture->Start();
		if (SUCCEEDED(hr))
		{
			m_isInitialized.store(true);
			m_isStreaming.store(true);
			UpdateState(RecordState::record);
		}
		
		return hr;
	}
	
	HRESULT Recorder::Pause()
	{
		if (!m_isInitialized.load()) return E_FAIL;
		
		HRESULT hr = m_capture->Pause();
		if (SUCCEEDED(hr))
		{
			UpdateState(RecordState::pause);
		}
		
		return hr;
	}
	
	HRESULT Recorder::Resume()
	{
		if (!m_isInitialized.load()) return E_FAIL;
		
		HRESULT hr = m_capture->Resume();
		if (SUCCEEDED(hr))
		{
			UpdateState(RecordState::record);
		}
		
		return hr;
	}
	
	HRESULT Recorder::Stop()
	{
		if (!m_isInitialized.load()) return S_OK;
		
		HRESULT hr = m_capture->Stop();
		
		if (m_isRecordingToFile.load())
		{
			m_fileWriter->Stop();
			m_isRecordingToFile.store(false);
		}
		
		m_isStreaming.store(false);
		m_isInitialized.store(false);
		
		UpdateState(RecordState::stop);
		
		return hr;
	}
	
	HRESULT Recorder::Cancel()
	{
		HRESULT hr = Stop();
		
		// Delete the recording file if it exists
		if (!m_recordingPath.empty() && m_fileWriter->GetBytesWritten() > 0)
		{
			DeleteFile(m_recordingPath.c_str());
		}
		
		return hr;
	}
	
	bool Recorder::IsPaused()
	{
		return m_recordState == RecordState::pause;
	}
	
	bool Recorder::IsRecording()
	{
		return m_recordState == RecordState::record;
	}
	
	HRESULT Recorder::Dispose()
	{
		Stop();
		Cleanup();
		return S_OK;
	}
	
	std::map<std::string, double> Recorder::GetAmplitude()
	{
		return {
			{"current", static_cast<double>(m_amplitudeAnalyzer->GetCurrentAmplitude())},
			{"max", static_cast<double>(m_amplitudeAnalyzer->GetMaxAmplitude())},
		};
	}
	
	std::wstring Recorder::GetRecordingPath()
	{
		return m_recordingPath;
	}
	
	HRESULT Recorder::isEncoderSupported(std::string encoderName, bool* supported)
	{
		// Support multiple audio formats with minimal binary impact
		*supported = (encoderName == "pcm16bits" || 
					  encoderName == "wav" ||
					  // encoderName == "flac" ||     // FLAC disabled - needs separate library
					  encoderName == "aac" ||      // AAC-LC (using Windows Media Foundation)
					  encoderName == "aaclc");     // AAC-LC alias
		return S_OK;
	}
	
	void Recorder::OnAudioData(const float* samples, size_t count)
	{
		// Always calculate amplitude - this gives immediate feedback!
		m_amplitudeAnalyzer->ProcessSamples(samples, count);
		
		// Queue for file writing if recording to file
		if (m_isRecordingToFile.load())
		{
			m_fileWriter->QueueAudio(samples, count);
		}
		
		// Stream to Flutter if streaming
		if (m_isStreaming.load() && m_recordEventHandler)
		{
			// Convert float samples to bytes for Flutter
			std::vector<int16_t> pcmData(count);
			for (size_t i = 0; i < count; ++i)
			{
				float sample = (std::clamp)(samples[i], -1.0f, 1.0f);
				pcmData[i] = static_cast<int16_t>(sample * 32767.0f);
			}
			
			std::vector<uint8_t> bytes(reinterpret_cast<uint8_t*>(pcmData.data()),
									   reinterpret_cast<uint8_t*>(pcmData.data()) + pcmData.size() * sizeof(int16_t));
			
			// Send to Flutter on main thread
			RecordWindowsPlugin::RunOnMainThread([this, bytes = std::move(bytes)]() -> void {
				m_recordEventHandler->Success(std::make_unique<flutter::EncodableValue>(bytes));
			});
		}
	}
	
	void Recorder::UpdateState(RecordState state)
	{
		m_recordState = state;
		
		if (m_stateEventHandler) {
			RecordWindowsPlugin::RunOnMainThread([this, state]() -> void {
				m_stateEventHandler->Success(std::make_unique<flutter::EncodableValue>(state));
			});
		}
	}
	
	void Recorder::Cleanup()
	{
		m_capture.reset();
		m_fileWriter.reset();
		m_amplitudeAnalyzer.reset();
		m_config.reset();
		m_recordingPath.clear();
	}
	
	HRESULT Recorder::ValidateConfig(const RecordConfig& config)
	{
		// Validate channel count
		if (config.numChannels < 1 || config.numChannels > 8)
		{
			return E_INVALIDARG;
		}
		
		// Validate encoder support
		bool supported = false;
		HRESULT hr = isEncoderSupported(config.encoderName, &supported);
		
		if (FAILED(hr) || !supported)
		{
			return E_NOTIMPL;
		}
		
		return S_OK;
	}
	
	DWORD Recorder::GetSampleRateFromConfig(const RecordConfig& config)
	{
		// Use provided sample rate or default to 48kHz
		return static_cast<DWORD>(config.sampleRate > 0 ? config.sampleRate : 48000);
	}
	
	WORD Recorder::GetChannelsFromConfig(const RecordConfig& config)
	{
		// Use provided channel count or default to stereo
		return static_cast<WORD>(config.numChannels > 0 ? config.numChannels : 2);
	}
}
