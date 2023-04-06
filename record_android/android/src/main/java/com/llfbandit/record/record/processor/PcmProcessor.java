package com.llfbandit.record.record.processor;

import static android.os.SystemClock.sleep;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.llfbandit.record.VoidCallback;
import com.llfbandit.record.record.PCMReader;
import com.llfbandit.record.record.RecordConfig;
import com.llfbandit.record.record.RecordState;

import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.util.concurrent.atomic.AtomicBoolean;

public class PcmProcessor implements AudioProcessor {
  protected RecordConfig config;
  @NonNull
  protected final OnAudioProcessorListener listener;

  @Nullable
  private RecordThread recordThread;

  @Nullable
  protected RandomAccessFile out;

  public PcmProcessor(@NonNull OnAudioProcessorListener listener) {
    this.listener = listener;
  }

  @Override
  public void start(RecordConfig config) throws Exception {
    stop();

    this.config = config;

    if (config.path != null) {
      out = new RandomAccessFile(config.path, "rw");
      // Clears file content. Prevents wrong output if file was existing.
      out.setLength(0);
    } else {
      out = null;
    }

    recordThread = new RecordThread();
    new Thread(recordThread).start();
  }

  @Override
  public void stop() {
    if (recordThread != null) {
      recordThread.stop(() -> recordThread = null);
    }
  }

  @Override
  public void pause() {
    if (recordThread != null) {
      recordThread.pause();
    }
  }

  @Override
  public void resume() {
    if (recordThread != null) {
      recordThread.resume();
    }
  }

  @Override
  public boolean isRecording() {
    return recordThread != null && recordThread.isRecording();
  }

  @Override
  public boolean isPaused() {
    return recordThread != null && recordThread.isPaused();
  }

  protected void onAudioChunk(byte[] chunk, int length) throws Exception {
    if (out != null) {
      // Write to file
      out.write(chunk, 0, length);
    } else {
      listener.onAudioChunk(chunk);
    }
  }

  protected void onBegin(RecordConfig config) throws Exception {}

  protected void onEnd() throws Exception {}

  private class RecordThread implements Runnable {
    // Signals whether a recording is in progress (true) or not (false).
    private final AtomicBoolean isRecording = new AtomicBoolean(false);
    // Signals whether a recording is paused (true) or not (false).
    private final AtomicBoolean isPaused = new AtomicBoolean(false);
    private VoidCallback complete;

    private final PCMReader reader;

    RecordThread() throws Exception {
      reader = new PCMReader(config);
    }

    boolean isRecording() {
      return isRecording.get();
    }

    boolean isPaused() {
      return isPaused.get();
    }

    public void pause() {
      if (isRecording()) {
        updateState(RecordState.PAUSE);
      }
    }

    void resume() {
      if (isPaused()) {
        updateState(RecordState.RECORD);
      }
    }

    void stop(VoidCallback complete) {
      this.complete = complete;
      isRecording.set(false);
    }

    private void complete() {
      if (out != null) {
        try {
          out.close();
        } catch (Exception e) {
          listener.onFailure(e);
        }
      }

      try {
        reader.stop();
        reader.release();
      } catch (Exception e) {
        listener.onFailure(e);
      }

      updateState(RecordState.STOP);

      if (complete != null) {
        complete.call();
      }
    }

    private void updateState(RecordState state) {
      switch (state) {
        case PAUSE:
          isRecording.set(true);
          isPaused.set(true);
          listener.onPause();
          break;
        case RECORD:
          isRecording.set(true);
          isPaused.set(false);
          listener.onRecord();
          break;
        case STOP:
          isRecording.set(false);
          isPaused.set(false);
          listener.onStop();
          break;
      }
    }

    @Override
    public void run() {
      try {
        final ByteBuffer buffer = ByteBuffer.allocateDirect(reader.getBufferSize());

        onBegin(config);

        updateState(RecordState.RECORD);

        while (isRecording.get()) {
          while (isPaused.get()) {
            sleep(100);
          }

          if (isRecording.get()) {
            buffer.clear();
            int resultBytes = reader.read(buffer);

            if (resultBytes > 0) {
              byte[] bytes = new byte[resultBytes];
              buffer.get(bytes, 0, resultBytes);

              onAudioChunk(bytes, resultBytes);

              listener.onAmplitude(reader.getAmplitude());
            }
          }
        }

        onEnd();
      } catch (Exception e) {
        listener.onFailure(e);
      } finally {
        complete();
      }
    }
  }
}