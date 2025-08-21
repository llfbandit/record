#include <flutter/event_channel.h>
#include <flutter/encodable_value.h>

using namespace flutter;

template <typename T = EncodableValue>
class EventStreamHandler : public StreamHandler<T> {
public:
    EventStreamHandler() = default;

    virtual ~EventStreamHandler() = default;

    void Success(std::unique_ptr<T> _data) {
        auto sink = m_sink.get();
        if (sink && _data) {
            sink->Success(*_data.get());
        }
    }

    void Error(const std::string& error_code, const std::string& error_message,
        const T& error_details) {
        if (m_sink.get())
            m_sink.get()->Error(error_code, error_message, error_details);
    }

protected:
    std::unique_ptr<StreamHandlerError<T>> OnListenInternal(
        const T* arguments, std::unique_ptr<EventSink<T>>&& events) override {
        m_sink = std::move(events);
        return nullptr;
    }

    std::unique_ptr<StreamHandlerError<T>> OnCancelInternal(
        const T* arguments) override {
        m_sink.reset();
        return nullptr;
    }

private:
    std::unique_ptr<EventSink<T>> m_sink;
};