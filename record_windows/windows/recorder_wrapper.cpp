#pragma once
#define NOMINMAX
#include <windows.h>
#include <future>
#include <chrono>
#include <cstdio>
#include "recorder_wrapper.h"

#include <flutter/standard_method_codec.h>

#include "utils.h"

#include <utility>

using namespace flutter;

namespace record_windows
{
    RecorderWrapper::RecorderWrapper(BinaryMessenger* messenger, const std::string& recorderId, PlatformThread& platform)
        : m_platform(platform),
        m_dispatcher(std::make_shared<RecorderDispatcher>())
    {
        m_stateEventHandler = new EventStreamHandler<>();
        m_stateEventChannel = std::make_unique<EventChannel<EncodableValue>>(
            messenger, "com.llfbandit.record/events/" + recorderId,
            &StandardMethodCodec::GetInstance());
        m_stateEventChannel->SetStreamHandler(
            std::unique_ptr<StreamHandler<EncodableValue>>(m_stateEventHandler));

        m_recordEventHandler = new EventStreamHandler<>();
        m_recordEventChannel = std::make_unique<EventChannel<EncodableValue>>(
            messenger, "com.llfbandit.record/eventsRecord/" + recorderId,
            &StandardMethodCodec::GetInstance());
        m_recordEventChannel->SetStreamHandler(
            std::unique_ptr<StreamHandler<EncodableValue>>(m_recordEventHandler));

        m_configChangedChannel = std::make_unique<MethodChannel<EncodableValue>>(
            messenger, "com.llfbandit.record/configChanged/" + recorderId,
            &StandardMethodCodec::GetInstance());

        auto alive = m_alive;
        auto* stateHandler = m_stateEventHandler;
        auto* recordHandler = m_recordEventHandler;
        auto* configChannel = m_configChangedChannel.get();

        RecorderCallbacks callbacks;
        callbacks.onState = [this, alive, stateHandler](RecordState state) {
            m_platform.Post([alive, stateHandler, state] {
                if (*alive) stateHandler->Success(std::make_unique<EncodableValue>(state));
            });
        };

        callbacks.onChunk = [this, alive, recordHandler](std::vector<uint8_t> bytes) {
            m_platform.Post([alive, recordHandler, b = std::move(bytes)]() mutable {
                if (*alive) recordHandler->Success(std::make_unique<EncodableValue>(std::move(b)));
            });
        };

        callbacks.onConfigChanged = [this, alive, configChannel](const RecordConfig& cfg) {
            EncodableMap args = cfg.rawArgs;
            args[EncodableValue("bitRate")] = EncodableValue(cfg.bitRate);
            args[EncodableValue("sampleRate")] = EncodableValue(cfg.sampleRate);
            args[EncodableValue("numChannels")] = EncodableValue(cfg.numChannels);

            m_platform.Post([alive, configChannel, args = std::move(args)]() mutable {
                if (*alive) configChannel->InvokeMethod("onConfigChanged",
                    std::make_unique<EncodableValue>(EncodableMap(std::move(args))));
            });
        };

        m_callbacks = callbacks;
        m_recorder = std::make_unique<Recorder>(m_dispatcher, std::move(callbacks));
    }

    RecorderWrapper::~RecorderWrapper()
    {
        Teardown(nullptr);
        m_dispatcher->Join();
        *m_alive = false;
    }

    // Tears down on the recorder's thread; a no-op once that already happened.
    void RecorderWrapper::Teardown(std::function<void()> done)
    {
        bool posted = m_dispatcher->Post([this, done] {
            if (m_wasapi) {
                m_wasapi->Cancel();
                m_wasapi.reset();
            }

            m_recorder->Dispose();

            // Answered once the thread has stopped, so the join that follows never waits.
            std::function<void()> onExit;
            if (done) onExit = [this, done] { m_platform.Post(done); };
            m_dispatcher->Shutdown(std::move(onExit));
        });

        // Already disposed: still answer so the Dart future settles.
        if (!posted && done) m_platform.Post(done);
    }

    // Runs block on the dispatcher; its value reaches reply on the platform thread.
    template <typename R, typename F>
    void RecorderWrapper::Run(std::function<void(R)> reply, R fallback, F&& block)
    {
        bool posted = m_dispatcher->Post([this, reply, block = std::forward<F>(block)]() mutable {
            R value = block();
            m_platform.Post([reply, value] { reply(value); });
        });

        if (!posted) m_platform.Post([reply, fallback] { reply(fallback); });
    }

    WasapiMixConfig RecorderWrapper::ToWasapiCfg(const RecordConfig& c)
    {
        WasapiMixConfig w;
        w.sampleRate = c.sampleRate;
        w.channels = static_cast<uint16_t>(c.numChannels);
        w.micGain = static_cast<float>(c.micGain);
        w.systemGain = static_cast<float>(c.systemAudioGain);
        w.micDeviceId = Utf16FromUtf8(c.deviceId);
        return w;
    }

    HRESULT RecorderWrapper::StartWasapi(const RecordConfig& c, const std::wstring& path, bool stream)
    {
        if ((m_wasapi && m_wasapi->IsRecording()) || m_recorder->IsRecording())
            return E_ILLEGAL_METHOD_CALL;

        const bool isPcm = c.encoderName == AudioEncoder::pcm16bits;
        const bool isWav = c.encoderName == AudioEncoder::wav;

        if (stream ? !isPcm : !(isPcm || isWav))
            return E_NOTIMPL;

        m_wasapi = std::make_unique<WasapiMixRecorder>();
        const auto cfg = ToWasapiCfg(c);

        HRESULT hr;
        if (stream) {
            auto onChunk = m_callbacks.onChunk;
            hr = m_wasapi->StartStream(cfg, [onChunk](const uint8_t* d, size_t n) {
                onChunk(std::vector<uint8_t>(d, d + n));
            });
        }
        else {
            hr = m_wasapi->Start(cfg, path);
        }

        if (FAILED(hr)) {
            m_wasapi.reset();
            return hr;
        }

        m_callbacks.onState(RecordState::record);
        return S_OK;
    }

    void RecorderWrapper::Start(std::unique_ptr<RecordConfig> config, std::wstring path, Reply reply)
    {
        Run(std::move(reply), E_ABORT, [this, config = std::move(config), path]() mutable -> HRESULT {
            if (config->captureSystemAudio)
                return StartWasapi(*config, path, false);

            return m_recorder->Start(std::move(config), path);
        });
    }

    void RecorderWrapper::StartStream(std::unique_ptr<RecordConfig> config, Reply reply)
    {
        Run(std::move(reply), E_ABORT, [this, config = std::move(config)]() mutable -> HRESULT {
            if (config->captureSystemAudio)
                return StartWasapi(*config, L"", true);

            return m_recorder->StartStream(std::move(config));
        });
    }

    void RecorderWrapper::Pause(Reply reply)
    {
        Run(std::move(reply), E_ABORT, [this]() -> HRESULT {
            if (m_wasapi) {
                m_wasapi->Pause();
                m_callbacks.onState(RecordState::pause); 
                return S_OK;
            }

            return m_recorder->Pause();
        });
    }

    void RecorderWrapper::Resume(Reply reply)
    {
        Run(std::move(reply), E_ABORT, [this]() -> HRESULT {
            if (m_wasapi) {
                m_wasapi->Resume();
                m_callbacks.onState(RecordState::record);
                return S_OK;
            }

            return m_recorder->Resume();
        });
    }

    void RecorderWrapper::Stop(std::function<void(StopResult)> reply)
    {
        Run(std::move(reply), StopResult{ E_ABORT, std::wstring() }, [this]() -> StopResult {
            if (m_wasapi) {
                std::wstring p;
                HRESULT hr = m_wasapi->Stop(&p);
                m_wasapi.reset();
                m_callbacks.onState(RecordState::stop);
                return StopResult{ hr, p };
            }

            return m_recorder->Stop();
        });
    }

    void RecorderWrapper::Cancel(Reply reply)
    {
        Run(std::move(reply), E_ABORT, [this]() -> HRESULT {
            if (m_wasapi) {
                m_wasapi->Cancel();
                m_wasapi.reset();
                m_callbacks.onState(RecordState::stop);
                return S_OK;
            }

            return m_recorder->Cancel();
        });
    }

    void RecorderWrapper::IsPaused(std::function<void(bool)> reply)
    {
        Run(std::move(reply), false, [this]() -> bool {
            return m_wasapi ? m_wasapi->IsPaused() : m_recorder->IsPaused();
        });
    }

    void RecorderWrapper::IsRecording(std::function<void(bool)> reply)
    {
        Run(std::move(reply), false, [this]() -> bool {
            return m_wasapi ? m_wasapi->IsRecording() : m_recorder->IsRecording();
        });
    }

    void RecorderWrapper::GetAmplitude(std::function<void(std::map<std::string, double>)> reply)
    {
        Run(std::move(reply), std::map<std::string, double>(), [this]() -> std::map<std::string, double> {
            if (m_wasapi) {
                double cur, mx;
                m_wasapi->GetAmplitude(&cur, &mx);
                return { {"current", cur}, {"max", mx} };
            }

            return m_recorder->GetAmplitude();
        });
    }

    void RecorderWrapper::Dispose(std::function<void()> reply)
    {
        auto alive = m_alive;
        Teardown([this, alive, reply] {
            // Not in the destructor: at engine shutdown the messenger is already detached.
            if (*alive)
            {
                m_stateEventChannel->SetStreamHandler(nullptr);
                m_recordEventChannel->SetStreamHandler(nullptr);
            }

            reply();
        });
    }
}
