package com.llfbandit.record.record;

import androidx.annotation.NonNull;

import com.llfbandit.record.stream.RecorderRecordStreamHandler;
import com.llfbandit.record.stream.RecorderStateStreamHandler;

import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

abstract public class RecorderBase {
  protected static final int RECORD_STATE_PAUSE = 0;
  protected static final int RECORD_STATE_RECORD = 1;
  protected static final int RECORD_STATE_STOP = 2;

  // Event producer
  private final RecorderStateStreamHandler recorderStateStreamHandler;
  private final RecorderRecordStreamHandler recorderRecordStreamHandler;

  // Signals whether a recording is in progress (true) or not (false).
  protected final AtomicBoolean isRecording = new AtomicBoolean(false);
  // Signals whether a recording is in progress (true) or not (false).
  protected final AtomicBoolean isPaused = new AtomicBoolean(false);

  RecorderBase(@NonNull RecorderStateStreamHandler recorderStateStreamHandler,
               @NonNull RecorderRecordStreamHandler recorderRecordStreamHandler) {
    this.recorderStateStreamHandler = recorderStateStreamHandler;
    this.recorderRecordStreamHandler = recorderRecordStreamHandler;
  }

  /**
   * Retrieves the audio session ID.
   */
  public abstract int getInstanceId();

  /**
   * Starts the recording with the given config.
   */
  public abstract void start() throws Exception;

  /**
   * Stops the recording.
   */
  public abstract String stop();

  /**
   * Pauses the recording if currently running.
   */
  public abstract void pause() throws Exception;

  /**
   * Resumes the recording if currently paused.
   */
  public abstract void resume() throws Exception;

  /**
   * Gets the state the of recording
   *
   * @return True if recording. False otherwise.
   */
  public boolean isRecording() {
    return isRecording.get();
  }

  /**
   * Gets the state the of recording
   *
   * @return True if paused. False otherwise.
   */
  public boolean isPaused() {
    return isPaused.get();
  }

  /**
   * Gets the maximum amplitude
   *
   * @return Map with current and max amplitude values
   */
  public abstract Map<String, Object> getAmplitude();

  /**
   * Stops recording and releases all resources.
   */
  public abstract void close();

  protected void sendRecordChunkEvent(byte[] buffer) {
    recorderRecordStreamHandler.sendRecordChunkEvent(buffer);
  }

  protected void closeRecordChunkStream() {
    recorderRecordStreamHandler.closeRecordChunkStream();
  }

  protected void updateState(int state) {
    switch (state) {
      case RECORD_STATE_PAUSE:
        isRecording.set(true);
        isPaused.set(true);
        break;
      case RECORD_STATE_RECORD:
        isRecording.set(true);
        isPaused.set(false);
        break;
      default: // RECORD_STATE_STOP
        isRecording.set(false);
        isPaused.set(false);
        break;
    }

    recorderStateStreamHandler.sendStateEvent(state);
  }
}
