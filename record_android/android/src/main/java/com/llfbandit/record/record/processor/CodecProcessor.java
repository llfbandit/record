package com.llfbandit.record.record.processor;

import android.media.MediaCodec;
import android.media.MediaFormat;
import android.media.MediaMuxer;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.llfbandit.record.VoidCallback;
import com.llfbandit.record.record.PCMReader;
import com.llfbandit.record.record.RecordConfig;
import com.llfbandit.record.record.RecordState;

import java.nio.ByteBuffer;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicBoolean;

abstract public class CodecProcessor implements AudioProcessor {
  protected final OnAudioProcessorListener listener;

  @Nullable
  private RecordThread recordThread;

  public CodecProcessor(@NonNull OnAudioProcessorListener listener) {
    this.listener = listener;
  }

  @Override
  public void start(RecordConfig config) throws Exception {
    stop();

    recordThread = new RecordThread(config);
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

  public abstract MediaCodec createCodec(RecordConfig config) throws Exception;

  public abstract MediaMuxer createMuxer(@NonNull String path) throws Exception;

  public abstract void onStream(byte[] buffer, @NonNull MediaCodec.BufferInfo info) throws Exception;

  private class RecordThread extends MediaCodec.Callback implements Runnable {
    // Signals whether a recording is in progress (true) or not (false).
    private final AtomicBoolean isRecording = new AtomicBoolean(false);
    // Signals whether a recording is paused (true) or not (false).
    private final AtomicBoolean isPaused = new AtomicBoolean(false);

    private PCMReader reader;

    private MediaCodec codec;

    @Nullable
    private MediaMuxer mediaMuxer;

    private int trackIndex = -1;

    private final CountDownLatch completion = new CountDownLatch(1);
    private final AtomicBoolean recordClosed = new AtomicBoolean(false);
    private VoidCallback complete;

    RecordThread(RecordConfig config) throws Exception {
      reader = new PCMReader(config);
      codec = createCodec(config);

      if (config.path != null) {
        mediaMuxer = createMuxer(config.path);
      }
    }

    boolean isRecording() {
      return isRecording.get();
    }

    boolean isPaused() {
      return isPaused.get();
    }

    void pause() {
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
      recordClosed.set(true);
    }

    @Override
    public void run() {
      codec.setCallback(this);

      try {
        codec.start();
        reader.start();
        updateState(RecordState.RECORD);

        completion.await();
      } catch (InterruptedException ignored) {
      } catch (Exception ex) {
        listener.onFailure(ex);
        complete();
      }
    }

    @Override
    public void onOutputFormatChanged(@NonNull MediaCodec codec, @NonNull MediaFormat format) {
      if (mediaMuxer != null) {
        if (trackIndex == -1) {
          trackIndex = mediaMuxer.addTrack(format);
          mediaMuxer.start();
        }
      }
    }

    @Override
    public void onInputBufferAvailable(@NonNull MediaCodec codec, int index) {
      try {
        ByteBuffer byteBuffer = codec.getInputBuffer(index);
        if (byteBuffer == null) {
          return;
        }

        int resultBytes = isPaused() ? 0 : reader.read(byteBuffer);
        codec.queueInputBuffer(
            index, 0, resultBytes, 0,
            recordClosed.get() ? MediaCodec.BUFFER_FLAG_END_OF_STREAM : 0
        );

        if (!isPaused()) {
          listener.onAmplitude(reader.getAmplitude());
        }
      } catch (Exception e) {
        listener.onFailure(e);
        complete();
      }
    }

    @Override
    public void onOutputBufferAvailable(
        @NonNull MediaCodec codec,
        int index,
        @NonNull MediaCodec.BufferInfo info
    ) {
      try {
        ByteBuffer byteBuffer = codec.getOutputBuffer(index);

        if (byteBuffer != null) {
          if (mediaMuxer != null) {
            mediaMuxer.writeSampleData(trackIndex, byteBuffer, info);
          } else {
            byte[] buffer = new byte[info.size];
            byteBuffer.get(buffer, info.offset, info.size);
            onStream(buffer, info);
          }
        }

        codec.releaseOutputBuffer(index, false);

        if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
          complete();
        }
      } catch (Exception e) {
        listener.onFailure(e);
        complete();
      }
    }

    @Override
    public void onError(@NonNull MediaCodec codec, @NonNull MediaCodec.CodecException e) {
      listener.onFailure(e);
      complete();
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

    private void complete() {
      if (codec != null) {
        codec.stop();
        codec.release();
        codec = null;
      }

      if (reader != null) {
        reader.stop();
        reader.release();
        reader = null;
      }

      if (mediaMuxer != null) {
        mediaMuxer.stop();
        mediaMuxer.release();
        mediaMuxer = null;
      }

      trackIndex = -1;

      updateState(RecordState.STOP);

      completion.countDown();

      if (complete != null) {
        complete.call();
        complete = null;
      }
    }
  }
}
