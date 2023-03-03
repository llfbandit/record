package com.llfbandit.record.record;

import static android.os.SystemClock.sleep;

import android.content.Context;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.os.Build;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;

import com.llfbandit.record.RecorderBase;
import com.llfbandit.record.stream.RecorderRecordStreamHandler;
import com.llfbandit.record.stream.RecorderStateStreamHandler;

import java.io.Closeable;
import java.io.FileDescriptor;
import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.util.HashMap;
import java.util.Map;
import java.util.Random;
import java.util.concurrent.CountDownLatch;

class MediaRecorder extends RecorderBase {
  private static final String LOG_TAG = "Record - MR";

  private android.media.MediaRecorder recorder = null;
  // Recording config
  private final RecordConfig config;
  private Double maxAmplitude = -160.0;
  private final Context context;
  // Recording outputs
  private RandomAccessFile outputFile;
  private RecordChunkWriter recordChunkWriter;

  MediaRecorder(
      @NonNull Context context,
      @NonNull RecordConfig config,
      @NonNull RecorderStateStreamHandler recorderStateStreamHandler,
      @NonNull RecorderRecordStreamHandler recorderRecordStreamHandler
  ) {
    super(recorderStateStreamHandler, recorderRecordStreamHandler);
    this.context = context;
    this.config = config;
  }

  @Override
  public void start() throws Exception {
    stopRecording();

    outputFile = new RandomAccessFile(config.path, "rw");
    startRecording(outputFile.getFD());
  }

  @Override
  void startStream() throws Exception {
    stopRecording();

    recordChunkWriter = new RecordChunkWriter();
    new Thread(recordChunkWriter).start();

    FileDescriptor fd = recordChunkWriter.getFileDescriptor();
    if (fd == null) {
      throw new Exception("Unable to start stream loopback server.");
    }

    startRecording(fd);
  }

  @Override
  public String stop() {
    stopRecording();
    return config.path;
  }

  @Override
  @RequiresApi(api = Build.VERSION_CODES.N)
  public void pause() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      pauseRecording();
    }
  }

  @Override
  @RequiresApi(api = Build.VERSION_CODES.N)
  public void resume() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      resumeRecording();
    }
  }

  @Override
  public Map<String, Object> getAmplitude() {
    Map<String, Object> amp = new HashMap<>();

    double current = -160.0;

    if (isRecording.get()) {
      current = 20 * Math.log10(recorder.getMaxAmplitude() / 32768.0);

      if (current > maxAmplitude) {
        maxAmplitude = current;
      }
    }

    amp.put("current", current);
    amp.put("max", maxAmplitude);

    return amp;
  }

  public static boolean isEncoderSupported(String encoder) {
    return getEncoder(encoder) != null;
  }

  @Override
  public void close() {
    stopRecording();
  }

  @SuppressWarnings("deprecation")
  private void startRecording(@NonNull FileDescriptor file) throws Exception {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      recorder = new android.media.MediaRecorder(context);
    } else {
      recorder = new android.media.MediaRecorder();
    }

    recorder.setAudioSource(android.media.MediaRecorder.AudioSource.DEFAULT);
    recorder.setAudioEncodingBitRate(config.bitRate);
    recorder.setAudioSamplingRate(config.samplingRate);
    recorder.setAudioChannels(config.numChannels);
    recorder.setOutputFormat(getOutputFormat(config.encoder));

    // must be set after output format
    Integer format = getEncoder(config.encoder);
    if (format == null) {
      Log.d(LOG_TAG, "Falling back to AAC LC");
      format = android.media.MediaRecorder.AudioEncoder.AAC;
    }

    recorder.setAudioEncoder(format);
    recorder.setOutputFile(file);

    try {
      recorder.prepare();
      recorder.start();
      updateState(RECORD_STATE_RECORD);
    } catch (IOException | IllegalStateException e) {
      recorder.release();
      recorder = null;
      throw new Exception(e);
    }
  }

  private void stopRecording() {
    if (recorder != null) {
      try {
        if (isRecording.get() || isPaused.get()) {
          recorder.stop();
        }
      } catch (RuntimeException ex) {
        // Mute this exception since 'isRecording' can't be 100% sure
      } finally {
        recorder.reset();
        recorder.release();
        recorder = null;
      }
    }

    closeFile();
    closeStreamWriter();

    updateState(RECORD_STATE_STOP);
    maxAmplitude = -160.0;
  }

  @RequiresApi(api = Build.VERSION_CODES.N)
  private void pauseRecording() {
    if (recorder != null) {
      try {
        if (isRecording.get()) {
          recorder.pause();
          updateState(RECORD_STATE_PAUSE);
        }
      } catch (IllegalStateException ex) {
        Log.d(LOG_TAG, "Did you call pause() before before start() or after stop()?\n" + ex.getMessage());
      }
    }
  }

  @RequiresApi(api = Build.VERSION_CODES.N)
  private void resumeRecording() {
    if (recorder != null) {
      try {
        if (isPaused.get()) {
          recorder.resume();
          updateState(RECORD_STATE_RECORD);
        }
      } catch (IllegalStateException ex) {
        Log.d(LOG_TAG, "Did you call resume() before before start() or after stop()?\n" + ex.getMessage());
      }
    }
  }

  private void closeFile() {
    closeClosable(outputFile);
    outputFile = null;
  }

  private void closeClosable(Closeable closeable) {
    if (closeable == null) {
      return;
    }

    try {
      closeable.close();
    } catch (Exception e) {
      e.printStackTrace();
    }
  }

  private int getOutputFormat(String encoder) {
    switch (encoder) {
      case "aacLc":
      case "aacEld":
      case "aacHe":
        return android.media.MediaRecorder.OutputFormat.DEFAULT;
      case "amrNb":
      case "amrWb":
        return android.media.MediaRecorder.OutputFormat.THREE_GPP;
      case "opus":
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
          return android.media.MediaRecorder.OutputFormat.OGG;
        }
      case "vorbisOgg":
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
          return android.media.MediaRecorder.OutputFormat.OGG;
        }
        return android.media.MediaRecorder.OutputFormat.MPEG_4;
    }

    return android.media.MediaRecorder.OutputFormat.DEFAULT;
  }

  // https://developer.android.com/reference/android/media/MediaRecorder.AudioEncoder
  private static Integer getEncoder(String encoder) {
    switch (encoder) {
      case "aacLc":
        return android.media.MediaRecorder.AudioEncoder.AAC;
      case "aacEld":
        return android.media.MediaRecorder.AudioEncoder.AAC_ELD;
      case "aacHe":
        return android.media.MediaRecorder.AudioEncoder.HE_AAC;
      case "amrNb":
        return android.media.MediaRecorder.AudioEncoder.AMR_NB;
      case "amrWb":
        return android.media.MediaRecorder.AudioEncoder.AMR_WB;
      case "opus":
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
          return android.media.MediaRecorder.AudioEncoder.OPUS;
        }
      case "vorbisOgg":
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
          return android.media.MediaRecorder.AudioEncoder.VORBIS;
        }
    }

    return null;
  }

  /////////////////////////////////////////////////////////////////////////////////////////////
  /// STREAM
  /////////////////////////////////////////////////////////////////////////////////////////////
  private void closeStreamWriter() {
    if (recordChunkWriter != null) {
      try {
        recordChunkWriter.close();
      } catch (InterruptedException e) {
        e.printStackTrace();
      } finally {
        recordChunkWriter = null;
      }
    }
  }

  private class RecordChunkWriter implements Runnable {
    private final CountDownLatch connectionOpened = new CountDownLatch(1);
    // Flag for completion
    private final CountDownLatch completion = new CountDownLatch(1);

    private LocalServerSocket streamServer;
    private LocalSocket streamSender;
    private LocalSocket streamReceiver;

    void close() throws InterruptedException {
      completion.await();
    }

    FileDescriptor getFileDescriptor() throws Exception {
      connectionOpened.await();

      if (streamSender == null) {
        return null;
      }
      return streamSender.getFileDescriptor();
    }

    @Override
    public void run() {
      final byte[] buffer = new byte[16384];

      try {
        openLoopbackConnection();
      } catch (Exception e) {
        throw new RuntimeException(e);
      } finally {
        connectionOpened.countDown();
      }

      try {
        final InputStream reader = streamReceiver.getInputStream();

        // While recording or pending data to send
        while (isRecording.get() || reader.available() > 0) {
          // While paused or waiting for data
          while (isPaused.get() || reader.available() == 0) {
            sleep(100);
          }

          int read = reader.read(buffer);
          if (read > 0) {
            sendRecordChunkEvent(buffer);
          }
        }

        closeRecordChunkStream();
      } catch (Exception e) {
        throw new RuntimeException("Writing of recorded audio failed", e);
      } finally {
        closeLoopbackConnection();
        completion.countDown();
      }
    }

    private void openLoopbackConnection() throws Exception {
      final String LOCAL_ADDR = "com.llfbandit.record.loopback-";

      final Random rand = new Random();
      int senderId = 0;

      for (int i = 0; i < 10; ++i) {
        try {
          streamServer = new LocalServerSocket(LOCAL_ADDR + senderId);
          break;
        } catch (IOException e) {
          senderId = rand.nextInt();
        }
      }

      if (streamServer == null) {
        throw new Exception("Unable to start stream loopback server.");
      }

      streamReceiver = new LocalSocket();
      streamReceiver.connect(new LocalSocketAddress(LOCAL_ADDR + senderId));
      streamReceiver.setReceiveBufferSize(16384);
      streamReceiver.setSoTimeout(3000);

      streamSender = streamServer.accept();
      streamSender.setSendBufferSize(16384);

      connectionOpened.countDown();
    }

    private void closeLoopbackConnection() {
      closeClosable(streamReceiver);
      closeClosable(streamSender);

      if (streamServer != null) {
        try {
          streamServer.close();
        } catch (Exception e) {
          e.printStackTrace();
        }
      }

      streamReceiver = null;
      streamSender = null;
      streamServer = null;
    }
  }
}