package com.llfbandit.record;

import static android.os.SystemClock.sleep;

import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Build;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;

import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

import io.flutter.plugin.common.MethodChannel;

public class AudioRecorder implements RecorderBase {
  private static final String LOG_TAG = "Record - AR";

  // Signals whether a recording is in progress (true) or not (false).
  private final AtomicBoolean isRecording = new AtomicBoolean(false);
  // Signals whether a recording is in progress (true) or not (false).
  private final AtomicBoolean isPaused = new AtomicBoolean(false);
  // Signals whether a recording is in progress (true) or not (false).
  private final AtomicInteger amplitude = new AtomicInteger(-160);
  // Our recorder
  private AudioRecord recorder = null;
  // Thread to offload the writings from the UI thread
  private RecordDataWriter recordDataWriter = null;
  // Audio file path
  private String path;
  // Max amplitude recorded
  private double maxAmplitude = -100.0;

  @Override
  public void start(
      @NonNull String path,
      String encoder,
      int bitRate,
      int samplingRate,
      @NonNull MethodChannel.Result result) {

    stopRecording();

    this.path = path;

    Integer audioFormat = getAudioFormat(encoder);
    if (audioFormat == null) {
      Log.d(LOG_TAG, "Audio format is not supported.\nFalling back to PCM 16bits");
      audioFormat = AudioFormat.ENCODING_PCM_16BIT;
    }

    // Get min size of the buffer for writings * factor
    final int bufferSize = AudioRecord.getMinBufferSize(samplingRate,
        AudioFormat.CHANNEL_IN_MONO, audioFormat) * 2;

    recorder = new AudioRecord(MediaRecorder.AudioSource.DEFAULT, samplingRate,
        AudioFormat.CHANNEL_IN_MONO, audioFormat, bufferSize);

    isRecording.set(true);

    recordDataWriter = new RecordDataWriter(path, encoder, samplingRate, bufferSize);
    new Thread(recordDataWriter).start();

    recorder.startRecording();

    result.success(null);
  }

  @Override
  public void stop(@NonNull MethodChannel.Result result) {
    stopRecording();
    result.success(path);
  }

  @Override
  public void pause(@NonNull MethodChannel.Result result) {
    isPaused.set(true);
    result.success(null);
  }

  @RequiresApi(api = Build.VERSION_CODES.N)
  @Override
  public void resume(@NonNull MethodChannel.Result result) {
    isPaused.set(false);
    result.success(null);
  }

  @Override
  public void isRecording(@NonNull MethodChannel.Result result) {
    result.success(isRecording.get());
  }

  @Override
  public void isPaused(@NonNull MethodChannel.Result result) {
    result.success(isPaused.get());
  }

  @Override
  public void getAmplitude(@NonNull MethodChannel.Result result) {
    Map<String, Object> amp = new HashMap<>();

    final double currentAmplitude = (double) amplitude.get();

    if (currentAmplitude > maxAmplitude) {
      maxAmplitude = currentAmplitude;
    }

    amp.put("current", currentAmplitude);
    amp.put("max", maxAmplitude);

    result.success(amp);
  }

  @Override
  public boolean isEncoderSupported(String encoder) {
    Integer audioFormat = getAudioFormat(encoder);
    return audioFormat != null;
  }

  @Override
  public void close() {
    stopRecording();
  }

  private void stopRecording() {
    if (recorder != null) {
      try {
        if (isRecording.get() || isPaused.get()) {
          Log.d(LOG_TAG, "Stop recording");

          isRecording.set(false);
          isPaused.set(false);
          closeDataWriter();

          recorder.stop();
        }
      } catch (IllegalStateException ex) {
        // Mute this exception since 'isRecording' can't be 100% sure
      } finally {
        recorder.release();
        recorder = null;
      }
    }

    isRecording.set(false);
    isPaused.set(false);

    amplitude.set(-100);
    maxAmplitude = -100;

    closeDataWriter();
  }

  private void closeDataWriter() {
    if (recordDataWriter != null) {
      try {
        recordDataWriter.close();
      } catch (InterruptedException e) {
        e.printStackTrace();
      } finally {
        recordDataWriter = null;
      }
    }
  }

  private Integer getAudioFormat(String encoder) {
    switch (encoder) {
      case "wav":
      case "pcm16bit":
        return AudioFormat.ENCODING_PCM_16BIT;
      case "pcm8bit":
        return AudioFormat.ENCODING_PCM_8BIT;
    }

    return null;
  }

  private class RecordDataWriter implements Runnable {
    final String path;
    final String encoder;
    final int samplingRate;
    final int bufferSize;
    private int audioDataLength = 0;
    // Flag for completion
    CountDownLatch completion = new CountDownLatch(1);

    RecordDataWriter(String path, String encoder, int samplingRate, int bufferSize) {
      this.path = path;
      this.encoder = encoder;
      this.samplingRate = samplingRate;
      this.bufferSize = bufferSize;
    }

    void close() throws InterruptedException {
      completion.await();
    }

    @Override
    public void run() {
      try (final RandomAccessFile out = new RandomAccessFile(path, "rw")) {
        final ByteBuffer buffer = ByteBuffer.allocateDirect(bufferSize);

        // Clears file content. Prevents wrong output if file was existing.
        out.setLength(0);

        while (isRecording.get()) {
          if (isPaused.get()) {
            sleep(100);
          }

          buffer.clear();
          int result = recorder.read(buffer, bufferSize);
          if (result < 0) {
            throw new RuntimeException(getFailureReason(result));
          } else if (result > 0) {
            audioDataLength += result;

            byte[] bytes = buffer.array();
            // Update amplitude
            updateAmplitude(bytes, result);
            // Write to file
            out.write(bytes, 0, result);
          }
        }

        if (encoder.equals("wav")) {
          writeWavHeader(out);
        }
      } catch (IOException e) {
        throw new RuntimeException("Writing of recorded audio failed", e);
      } finally {
        completion.countDown();
      }
    }

    private void updateAmplitude(byte[] bytes, int nbBytes) {
      int maxSample = 0;
      for (int i = 0; i < nbBytes / 2; i++) {
        int curSample = Math.abs(bytes[i * 2] | (bytes[i * 2 + 1] << 8));
        if (curSample > maxSample) {
          maxSample = curSample;
        }
      }
      amplitude.set((int) ((int) 20 * Math.log10(maxSample / 32768.0)));
    }

    private String getFailureReason(int errorCode) {
      StringBuilder str = new StringBuilder("Reading of audio buffer failed: ");

      switch (errorCode) {
        case AudioRecord.ERROR_INVALID_OPERATION:
          str.append("AudioRecord.ERROR_INVALID_OPERATION");
          break;
        case AudioRecord.ERROR_BAD_VALUE:
          str.append("AudioRecord.ERROR_BAD_VALUE");
          break;
        case AudioRecord.ERROR_DEAD_OBJECT:
          str.append("AudioRecord.ERROR_DEAD_OBJECT");
          break;
        case AudioRecord.ERROR:
          str.append("AudioRecord.ERROR");
          break;
        default:
          str.append("Unknown (").append(errorCode).append(")");
          break;
      }

      return str.toString();
    }

    private void writeWavHeader(RandomAccessFile out) throws IOException {
      final short channels = 1;
      final byte bitsPerSample = 16;

//      Bytes	Content	                                    Offset
//      4	    Magic number: RIFF/RIFX                  	0
//      4	    WAVE chunk size = file size - 8             4
//      4	    WAVE identifier: WAVE                       8
//      4	    Format chunk identifier: fmt<space>	        12
//      4	    Format chunk size: 16 	                    16
//      2	    Sound format code	                        20
//      2	    Number of channels	                        22
//      4	    Sampling rate	                            24
//      4	    Average data rate in bytes per second       28
//      2	    Bytes per sample*	                        32
//      2	    Bits per sample*	                        34
//      4	    Chunk identifier: data	                    36
//      4	    Chunk length in bytes: N	                40
//      N	    Audio data	                                44
//
//      * For 16 bit PCM data the bytes per sample value is two for monaural but four for stereo.

      // write file header
      out.seek(0);
      out.writeBytes("RIFF");
      out.writeInt(Integer.reverseBytes(36 + audioDataLength)); // data length
      out.writeBytes("WAVE");
      out.writeBytes("fmt ");
      out.writeInt(Integer.reverseBytes(16)); // size of 'fmt ' chunk
      out.writeShort(Short.reverseBytes((short) 1)); // AudioFormat, 1 for PCM
      out.writeShort(Short.reverseBytes(channels));// Number of channels
      out.writeInt(Integer.reverseBytes(samplingRate)); // Sampling rate
      out.writeInt(Integer.reverseBytes(samplingRate * channels * bitsPerSample / 8)); // Byte rate
      out.writeShort(Short.reverseBytes((short) (channels * bitsPerSample / 8))); // Bytes per sample
      out.writeShort(Short.reverseBytes((short) bitsPerSample)); // Bits per sample
      out.writeBytes("data");
      out.writeInt(Integer.reverseBytes(audioDataLength)); // audio length
    }
  }
}
