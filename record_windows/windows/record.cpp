#include "record.h"
#include "record_windows_plugin.h"
#include <comdef.h>
#include <cmath>
#include <algorithm>
#include <chrono>
#include <cctype>

// Define missing Media Foundation constants if not available
#ifndef MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION
#define MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION MF_MT_USER_DATA
#endif

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
		: m_audioBuffer(std::make_unique<LockFreeRingBuffer<float>>(48000 * 2)) // 2 seconds buffer for lower delay
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
										 DWORD sampleRate, WORD channels, UINT32 bitRate)
	{
		// NOTE: sampleRate/channels should already reflect the negotiated device format
		// (not merely the originally requested values) to avoid distortion.
		m_encoderName = encoder;
		m_sampleRate = sampleRate;
		m_channels = channels;
		m_bitRate = bitRate;
		m_bytesWritten = 0;
		m_totalSamplesWritten = 0;
		m_startTime = std::chrono::steady_clock::now();
		
		// Determine if we need Media Foundation for advanced codecs
		m_useMediaFoundation = (encoder == "aac" || encoder == "aaclc" || 
								encoder == "aac_lc" || encoder == "m4a" || encoder == "mp4");
		
		// Fallback for unknown encoders - default to WAV
		if (!m_useMediaFoundation && 
			encoder != "pcm16bits" && encoder != "wav" && 
			encoder != "pcm" && encoder != "linear16")
		{
			// Unknown encoder - default to WAV
			m_encoderName = "wav";
		}
		
		// Adjust file extension based on encoder
		std::wstring adjustedPath = filePath;
		if (encoder == "aac" || encoder == "aaclc" || encoder == "aac_lc" || 
			encoder == "m4a" || encoder == "mp4")
		{
			// Replace .wav extension with .m4a for AAC files
			size_t dotPos = adjustedPath.find_last_of(L'.');
			if (dotPos != std::wstring::npos)
			{
				std::wstring extension = adjustedPath.substr(dotPos + 1);
				std::transform(extension.begin(), extension.end(), extension.begin(), ::towlower);
				if (extension == L"wav" || extension == L"aac")
				{
					adjustedPath.replace(dotPos, std::wstring::npos, L".m4a");
				}
			}
			else
			{
				adjustedPath += L".m4a";
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
		const size_t bufferSize = 2048; // Smaller buffer for lower latency
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
		hr = MFCreateAttributes(&pAttributes, 1);
		
		if (SUCCEEDED(hr))
		{
			// Enable hardware transforms for better performance
			hr = pAttributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
		}
		
		if (SUCCEEDED(hr))
		{
			// Enable low latency mode for real-time recording
			hr = pAttributes->SetUINT32(MF_READWRITE_MMCSS_CLASS, MF_READWRITE_MMCSS_CLASS_AUDIO);
		}
		
		if (SUCCEEDED(hr))
		{
			// Set priority for audio processing
			hr = pAttributes->SetUINT32(MF_READWRITE_MMCSS_PRIORITY_AUDIO, 6);
		}
		
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
				if (m_encoderName == "aac" || m_encoderName == "aaclc" || 
					m_encoderName == "aac_lc" || m_encoderName == "m4a" || m_encoderName == "mp4")
				{
					// AAC-LC configuration with optimized Media Foundation settings
					hr = pOutputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
					if (SUCCEEDED(hr)) hr = pOutputType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
					if (SUCCEEDED(hr)) hr = pOutputType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, m_sampleRate);
					if (SUCCEEDED(hr)) hr = pOutputType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, m_channels);
					
					// Use the configured bitrate, with intelligent defaults based on sample rate and channels
					UINT32 bitrate = m_bitRate > 0 ? m_bitRate : CalculateOptimalBitrate(m_sampleRate, m_channels);
					
					// Clamp bitrate to reasonable AAC-LC ranges
					if (bitrate < 8000) bitrate = 8000;       // Minimum practical AAC bitrate
					if (bitrate > 320000) bitrate = 320000;   // Maximum typical AAC bitrate
					
					if (SUCCEEDED(hr)) hr = pOutputType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, bitrate / 8);
					
					// Set compression quality - use variable bitrate mode for better quality
					if (SUCCEEDED(hr)) hr = pOutputType->SetUINT32(MF_MT_AUDIO_PREFER_WAVEFORMATEX, 0);
					
					// AAC-specific optimizations
					if (SUCCEEDED(hr)) hr = pOutputType->SetUINT32(MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION, 0x29); // AAC-LC Profile
					if (SUCCEEDED(hr)) hr = pOutputType->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 1);
					
					// Enable AAC spectral band replication for better efficiency at low bitrates
					if (bitrate < 64000 && m_channels <= 2) {
						// Use HE-AAC (AAC+SBR) for very low bitrates
						if (SUCCEEDED(hr)) hr = pOutputType->SetUINT32(MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION, 0x2A);
					}
					
					// Set optimal frame size for AAC (1024 samples is standard)
					if (SUCCEEDED(hr)) hr = pOutputType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_BLOCK, 1024);
					
					// Configure advanced AAC encoding parameters
					ConfigureAACQuality(pOutputType, bitrate);
					
					// Enable constant quality mode if available
					if (SUCCEEDED(hr)) hr = pOutputType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
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
				hr = pInputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
				if (SUCCEEDED(hr)) hr = pInputType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
				if (SUCCEEDED(hr)) hr = pInputType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, m_sampleRate);
				if (SUCCEEDED(hr)) hr = pInputType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, m_channels);
				if (SUCCEEDED(hr)) hr = pInputType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
				if (SUCCEEDED(hr)) hr = pInputType->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, m_channels * sizeof(int16_t));
				if (SUCCEEDED(hr)) hr = pInputType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, m_sampleRate * m_channels * sizeof(int16_t));
				if (SUCCEEDED(hr)) hr = pInputType->SetUINT32(MF_MT_ALL_SAMPLES_INDEPENDENT, TRUE);
				
				if (SUCCEEDED(hr))
				{
					hr = m_pSinkWriter->SetInputMediaType(m_streamIndex, pInputType, nullptr);
				}
				
				if (pInputType) pInputType->Release();
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
		
		// Calculate buffer size once
		DWORD bufferSize = static_cast<DWORD>(count * sizeof(int16_t));
		
		// Create sample
		hr = MFCreateSample(&pSample);
		
		if (SUCCEEDED(hr))
		{
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
			
			// Calculate precise timestamp based on sample count for better accuracy
			LONGLONG timestamp = (10000000LL * m_totalSamplesWritten) / (m_sampleRate * m_channels);
			pSample->SetSampleTime(timestamp);
			
			LONGLONG duration = (10000000LL * count) / (m_sampleRate * m_channels); // 100ns units
			pSample->SetSampleDuration(duration);
			
			// Update total samples written for next timestamp calculation
			m_totalSamplesWritten += count;
			
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
	
	UINT32 AsyncAudioWriter::CalculateOptimalBitrate(DWORD sampleRate, WORD channels)
	{
		// Calculate optimal bitrate based on sample rate and channel count
		// These values are based on audio engineering best practices for AAC-LC
		
		UINT32 baseBitrate;
		
		// Base bitrate per channel based on sample rate
		if (sampleRate >= 48000) {
			baseBitrate = 64000; // High quality for 48kHz+
		} else if (sampleRate >= 44100) {
			baseBitrate = 60000; // Standard quality for CD-quality
		} else if (sampleRate >= 32000) {
			baseBitrate = 48000; // Good quality for 32kHz
		} else if (sampleRate >= 22050) {
			baseBitrate = 32000; // Acceptable for voice/podcast
		} else {
			baseBitrate = 24000; // Minimum for speech
		}
		
		// Adjust for channel count
		UINT32 totalBitrate = baseBitrate;
		if (channels == 1) {
			totalBitrate = baseBitrate * 0.75f; // Mono needs less bitrate
		} else if (channels == 2) {
			totalBitrate = baseBitrate; // Stereo baseline
		} else if (channels <= 6) {
			totalBitrate = baseBitrate * 1.5f; // Surround sound
		} else {
			totalBitrate = baseBitrate * 2.0f; // High channel count
		}
		
		return totalBitrate;
	}
	
	HRESULT AsyncAudioWriter::ConfigureAACQuality(IMFMediaType* pOutputType, UINT32 bitrate)
	{
		HRESULT hr = S_OK;
		
		// Configure AAC encoder parameters based on quality setting and bitrate
		switch (m_aacQuality) {
			case AACQuality::Low:
				// Optimize for smallest file size
				if (SUCCEEDED(hr)) hr = pOutputType->SetUINT32(MF_MT_AAC_PAYLOAD_TYPE, 0); // Raw AAC
				break;
				
			case AACQuality::Medium:
				// Balanced quality/size (default)
				if (SUCCEEDED(hr)) hr = pOutputType->SetUINT32(MF_MT_AAC_PAYLOAD_TYPE, 1); // ADTS
				break;
				
			case AACQuality::High:
				// Optimize for quality
				if (SUCCEEDED(hr)) hr = pOutputType->SetUINT32(MF_MT_AAC_PAYLOAD_TYPE, 1); // ADTS
				// Enable higher quality encoding if available
				if (SUCCEEDED(hr)) hr = pOutputType->SetUINT32(MF_MT_AUDIO_CHANNEL_MASK, KSAUDIO_SPEAKER_STEREO);
				break;
				
			case AACQuality::VBR:
				// Variable bitrate for best quality
				if (SUCCEEDED(hr)) hr = pOutputType->SetUINT32(MF_MT_AAC_PAYLOAD_TYPE, 1); // ADTS
				// Note: Windows Media Foundation AAC encoder has limited VBR support
				// The bitrate setting acts more as a target/maximum in this mode
				break;
		}
		
		return hr;
	}

	// ===========================================
	// WASAPICapture Implementation
	// ===========================================
	
	WASAPICapture::WASAPICapture()
		: m_pDeviceEnumerator(nullptr)
		, m_pDevice(nullptr)
		, m_pAudioClient(nullptr)
		, m_pCaptureClient(nullptr)
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
		
		if (FAILED(hr))
		{
			// Common cause: COM not initialized or audio service not running
			return hr;
		}
		
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
		
		if (FAILED(hr))
		{
			// Common cause: No microphone available or no default capture device
			return hr;
		}
		
		if (SUCCEEDED(hr))
		{
			hr = InitializeAudioClient();
		}
		
		if (FAILED(hr))
		{
			// Common cause: Audio client initialization failed - could be permissions or device busy
			return hr;
		}
		
		// Initialize audio effects after audio client is set up
		// This configures the audio processing pipeline
		HRESULT effectsHr = InitializeAudioEffects();
		if (FAILED(effectsHr))
		{
			// Audio effects initialization failed - continue without effects
			// This is not critical, so we don't return failure
			// Effects might not be supported by all devices/drivers
		}
		
		// Create event for audio capture
		m_hCaptureEvent = CreateEvent(nullptr, FALSE, FALSE, nullptr);
		if (!m_hCaptureEvent) 
		{
			return E_FAIL;
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
		
		// First, try to set up audio effects using IAudioClient2 if available
		if (SUCCEEDED(hr) && (m_enableNoiseSuppress || m_enableEchoCancel || m_enableAutoGain))
		{
			IAudioClient2* pAudioClient2 = nullptr;
			HRESULT hrEffects = m_pAudioClient->QueryInterface(__uuidof(IAudioClient2), 
											 reinterpret_cast<void**>(&pAudioClient2));
			
			if (SUCCEEDED(hrEffects) && pAudioClient2)
			{
				// Set audio client properties for voice processing.
				// IMPORTANT: We intentionally do NOT request RAW here because RAW bypasses
				// the audio processing (AGC / Echo Cancellation / Noise Suppression) we want
				// when the user enabled those flags. So we keep the stream options at NONE.
				AudioClientProperties clientProperties = {};
				clientProperties.cbSize = sizeof(AudioClientProperties);
				clientProperties.bIsOffload = FALSE;
				clientProperties.eCategory = AudioCategory_Communications; // Enables voice processing
#if defined(AUDCLNT_STREAMOPTIONS_NONE)
				clientProperties.Options = AUDCLNT_STREAMOPTIONS_NONE; // Allow processing
#elif defined(AUDCLNT_STREAMOPTIONS_RAW)
				clientProperties.Options = static_cast<AUDCLNT_STREAMOPTIONS>(0); // Avoid RAW to keep processing
#else
				clientProperties.Options = static_cast<AUDCLNT_STREAMOPTIONS>(0); // Older SDK: safe default
#endif
				
				hrEffects = pAudioClient2->SetClientProperties(&clientProperties);
				pAudioClient2->Release();
				
				// If effects setup succeeded, continue with normal initialization
				// If failed, continue without effects (not critical)
			}
		}
		
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
					// Device doesn't support requested channel count in float format.
					// Attempt an immediate fallback to 16-bit PCM with requested channel count.
					if (pClosestMatch) CoTaskMemFree(pClosestMatch);
					WAVEFORMATEX waveFormat = {};
					waveFormat.wFormatTag = WAVE_FORMAT_PCM;
					waveFormat.nChannels = m_channels;
					waveFormat.nSamplesPerSec = m_sampleRate;
					waveFormat.wBitsPerSample = 16;
					waveFormat.nBlockAlign = m_channels * waveFormat.wBitsPerSample / 8;
					waveFormat.nAvgBytesPerSec = waveFormat.nSamplesPerSec * waveFormat.nBlockAlign;
					WAVEFORMATEX* pPcmClosest = nullptr;
					HRESULT hrPcm = m_pAudioClient->IsFormatSupported(AUDCLNT_SHAREMODE_SHARED, &waveFormat, &pPcmClosest);
					if (hrPcm == S_OK)
					{
						m_pWaveFormat = reinterpret_cast<WAVEFORMATEX*>(CoTaskMemAlloc(sizeof(WAVEFORMATEX)));
						if (m_pWaveFormat)
						{
							*m_pWaveFormat = waveFormat;
							hr = S_OK;
						}
						else
						{
							hr = E_OUTOFMEMORY;
						}
					}
					else if (hrPcm == S_FALSE && pPcmClosest)
					{
						// Accept closest PCM match only if channel count matches
						if (pPcmClosest->nChannels == m_channels)
						{
							m_pWaveFormat = pPcmClosest;
							m_sampleRate = m_pWaveFormat->nSamplesPerSec;
							hr = S_OK;
						}
						else
						{
							CoTaskMemFree(pPcmClosest);
							hr = AUDCLNT_E_UNSUPPORTED_FORMAT; // propagate meaningful error
						}
					}
					else
					{
						// PCM unsupported entirely
						hr = AUDCLNT_E_UNSUPPORTED_FORMAT;
					}
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
		
		// Prepare stream flags (event driven, no persistence)
		DWORD streamFlags = AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_NOPERSIST;
		if (SUCCEEDED(hr))
		{
			// Initialize audio client with effects support
			// NOTE:
			// There is no AUDCLNT_STREAMFLAGS_RAW flag in the Windows SDK. The RAW option is
			// configured via AudioClientProperties.Options = AUDCLNT_STREAMOPTIONS_RAW, which actually
			// DISABLES all audio processing (gives you raw audio). Because we want optional voice
			// processing (noise suppression / echo cancellation / AGC) when requested, we should NOT
			// force RAW here. Keeping just EVENTCALLBACK + NOPERSIST allows the Windows audio engine
			// to apply communications category processing we set earlier through AudioClientProperties.
			// If a future "raw" mode is desired, gate AUDCLNT_STREAMOPTIONS_RAW assignment on a
			// dedicated user flag instead of a (non‑existent) stream flag.
		}

		// Final fallback: if format negotiation failed, use the device's mix format
		if (FAILED(hr))
		{
			WAVEFORMATEX* pMix = nullptr;
			HRESULT hrMix = m_pAudioClient->GetMixFormat(&pMix);
			if (SUCCEEDED(hrMix) && pMix)
			{
				if (m_pWaveFormat) { CoTaskMemFree(m_pWaveFormat); }
				m_pWaveFormat = pMix; // take ownership
				m_sampleRate = m_pWaveFormat->nSamplesPerSec;
				m_channels = m_pWaveFormat->nChannels; // adapt to device
				hr = S_OK;
			}
		}

		if (SUCCEEDED(hr))
		{
			
			hr = m_pAudioClient->Initialize(AUDCLNT_SHAREMODE_SHARED,
											streamFlags,
											200000, // 20ms buffer duration
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
		// Audio effects are now primarily handled during audio client initialization
		// using AudioCategory_Communications which automatically enables:
		// - Noise suppression
		// - Echo cancellation  
		// - Automatic gain control
		// when supported by the audio driver and hardware
		
		// Additional effect configuration could be added here if needed
		// for specific device or driver requirements
		
		// For now, effects are handled automatically by Windows Audio Engine
		// when using AudioCategory_Communications
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
		if (FAILED(hr)) 
		{
			// Return specific error code for better debugging
			return hr; 
		}
		// IMPORTANT: The device may not support the requested sample rate / channels.
		// After initialization, query the actual negotiated format to avoid distortion
		// caused by feeding data captured at one rate into a writer tagged with another.
		sampleRate = m_capture->GetSampleRate();
		channels = m_capture->GetChannels();
		
		// Set up audio data callback
		m_capture->SetAudioDataCallback([this](const float* samples, size_t count) {
			OnAudioData(samples, count);
		});
		
	// Initialize file writer
	hr = m_fileWriter->Initialize(path, m_config->encoderName, sampleRate, channels, m_config->bitRate);
	if (FAILED(hr)) 
	{
		// Return specific error code for file writer issues
		return hr;
	}		hr = m_fileWriter->Start();
		if (FAILED(hr)) 
		{
			// Return specific error code for file writer start issues
			return hr;
		}
		
		// Start capture - this is immediate with WASAPI!
		hr = m_capture->Start();
		if (SUCCEEDED(hr))
		{
			m_isInitialized.store(true);
			m_isRecordingToFile.store(true);
			UpdateState(RecordState::record);
		}
		else
		{
			// Clean up if capture start failed
			m_fileWriter->Stop();
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
		// Adjust to actual negotiated format to prevent sample rate mismatch distortion
		sampleRate = m_capture->GetSampleRate();
		channels = m_capture->GetChannels();
		
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
		// Also include common aliases that Flutter might use
		*supported = (encoderName == "pcm16bits" || 
					  encoderName == "wav" ||
					  encoderName == "pcm" ||          // Common PCM alias
					  encoderName == "linear16" ||     // Another PCM alias
					  // encoderName == "flac" ||     // FLAC disabled - needs separate library
					  encoderName == "aac" ||          // AAC-LC (using Windows Media Foundation)
					  encoderName == "aaclc" ||        // AAC-LC alias
					  encoderName == "aac_lc" ||       // AAC-LC alias with underscore
					  encoderName == "m4a" ||          // AAC container format
					  encoderName == "mp4");           // MP4 audio container
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
		
		// For now, accept all encoder names and handle them gracefully in the writer
		// This prevents "not implemented" errors and allows fallback to supported formats
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
