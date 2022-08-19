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
      int numChannels,
      Map<String, Object> device
  ) throws Exception {
    stopRecording();

    this.path = path;

    Integer audioFormat = getAudioFormat(encoder);
    if (audioFormat == null) {
      Log.d(LOG_TAG, "Audio format is not supported.\nFalling back to PCM 16bits");
      audioFormat = AudioFormat.ENCODING_PCM_16BIT;
    }

    // clamp channels
    numChannels = Math.min(2, Math.max(1, numChannels));

    final int channelConfig = numChannels == 1
        ? AudioFormat.CHANNEL_IN_MONO
        : AudioFormat.CHANNEL_IN_STEREO;

    // Get min size of the buffer for writings * factor
    final int bufferSize = AudioRecord.getMinBufferSize(samplingRate, channelConfig, audioFormat) * 2;

    try {

      recorder = new AudioRecord(MediaRecorder.AudioSource.DEFAULT, samplingRate, channelConfig, audioFormat, bufferSize);

      isRecording.set(true);

      recordDataWriter = new RecordDataWriter(
          path, encoder, samplingRate, bufferSize, (short) numChannels,
          (audioFormat == AudioFormat.ENCODING_PCM_16BIT) ? (short) 16 : (short) 8
      );
      new Thread(recordDataWriter).start();

      recorder.startRecording();
    } catch (IllegalArgumentException | IllegalStateException e) {
      throw new Exception(e);
    }
  }

  @Override
  public String stop() {
    stopRecording();
    return path;
  }

  @Override
  public void pause() {
    isPaused.set(true);
  }

  @RequiresApi(api = Build.VERSION_CODES.N)
  @Override
  public void resume() {
    isPaused.set(false);
  }

  @Override
  public boolean isRecording() {
    return isRecording.get();
  }

  @Override
  public boolean isPaused() {
    return isPaused.get();
  }

  @Override
  public Map<String, Object> getAmplitude() {
    Map<String, Object> amp = new HashMap<>();

    final double currentAmplitude = amplitude.get();

    if (currentAmplitude > maxAmplitude) {
      maxAmplitude = currentAmplitude;
    }

    amp.put("current", currentAmplitude);
    amp.put("max", maxAmplitude);

    return amp;
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
    final short channels;
    final short bitsPerSample;
    private int audioDataLength = 0;
    // Flag for completion
    CountDownLatch completion = new CountDownLatch(1);

    RecordDataWriter(
        String path,
        String encoder,
        int samplingRate,
        int bufferSize,
        short channels,
        short bitsPerSample) {
      this.path = path;
      this.encoder = encoder;
      this.samplingRate = samplingRate;
      this.bufferSize = bufferSize;
      this.channels = channels;
      this.bitsPerSample = bitsPerSample;
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
        // Prepares WAV header & avoids data overwrites.
        if (encoder.equals("wav")) {
          writeWavHeader(out);
        }

        while (isRecording.get()) {
          while (isPaused.get()) {
            sleep(100);
          }

          if (isRecording.get()) {
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
      amplitude.set((int) (20 * Math.log10(maxSample / 32768.0)));
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
// Offset  Size  Name             Description

// The canonical WAVE format starts with the RIFF header:

// 0         4   ChunkID          Contains the letters "RIFF" in ASCII form
//                                (0x52494646 big-endian form).
// 4         4   ChunkSize        36 + SubChunk2Size, or more precisely:
//                                4 + (8 + SubChunk1Size) + (8 + SubChunk2Size)
//                                This is the size of the rest of the chunk 
//                                following this number.  This is the size of the 
//                                entire file in bytes minus 8 bytes for the
//                                two fields not included in this count:
//                                ChunkID and ChunkSize.
// 8         4   Format           Contains the letters "WAVE"
//                                (0x57415645 big-endian form).

// The "WAVE" format consists of two subchunks: "fmt " and "data":
// The "fmt " subchunk describes the sound data's format:

// 12        4   Subchunk1ID      Contains the letters "fmt "
//                                (0x666d7420 big-endian form).
// 16        4   Subchunk1Size    16 for PCM.  This is the size of the
//                                rest of the Subchunk which follows this number.
// 20        2   AudioFormat      PCM = 1 (i.e. Linear quantization)
//                                Values other than 1 indicate some
//                                form of compression.
// 22        2   NumChannels      Mono = 1, Stereo = 2, etc.
// 24        4   SampleRate       8000, 44100, etc.
// 28        4   ByteRate         == SampleRate * NumChannels * BitsPerSample/8
// 32        2   BlockAlign       == NumChannels * BitsPerSample/8
//                                The number of bytes for one sample including
//                                all channels. I wonder what happens when
//                                this number isn't an integer?
// 34        2   BitsPerSample    8 bits = 8, 16 bits = 16, etc.
//           2   ExtraParamSize   if PCM, then doesn't exist
//           X   ExtraParams      space for extra parameters

// The "data" subchunk contains the size of the data and the actual sound:

// 36        4   Subchunk2ID      Contains the letters "data"
//                                (0x64617461 big-endian form).
// 40        4   Subchunk2Size    == NumSamples * NumChannels * BitsPerSample/8
//                                This is the number of bytes in the data.
//                                You can also think of this as the size
//                                of the read of the subchunk following this 
//                                number.
// 44        *   Data             The actual sound data.

      out.seek(0);
      out.writeBytes("RIFF"); // ChunkID
      out.writeInt(Integer.reverseBytes(36 + audioDataLength)); // ChunkSize
      out.writeBytes("WAVE"); // Format
      out.writeBytes("fmt "); // Subchunk1ID
      out.writeInt(Integer.reverseBytes(16)); // Subchunk1Size
      out.writeShort(Short.reverseBytes((short) 1)); // AudioFormat, 1 for PCM
      out.writeShort(Short.reverseBytes(channels)); // NumChannels
      out.writeInt(Integer.reverseBytes(samplingRate)); // SampleRate
      out.writeInt(Integer.reverseBytes(samplingRate * channels * bitsPerSample / 8)); // ByteRate
      out.writeShort(Short.reverseBytes((short) (channels * bitsPerSample / 8))); // BlockAlign
      out.writeShort(Short.reverseBytes(bitsPerSample)); // BitsPerSample
      out.writeBytes("data"); // Subchunk2ID
      out.writeInt(Integer.reverseBytes(audioDataLength)); // Subchunk2Size
    }
  }
}
