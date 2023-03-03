package com.llfbandit.record.record;

import static android.media.AudioRecord.ERROR;
import static android.media.AudioRecord.ERROR_BAD_VALUE;
import static android.media.AudioRecord.RECORDSTATE_RECORDING;
import static android.os.SystemClock.sleep;

import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.media.audiofx.AutomaticGainControl;
import android.media.audiofx.NoiseSuppressor;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.llfbandit.record.stream.RecorderRecordStreamHandler;
import com.llfbandit.record.stream.RecorderStateStreamHandler;

import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicInteger;

public class AudioRecorder extends RecorderBase {
  private static final String TAG = "Record";

  // Recording config
  private final RecordConfig mConfig;
  // Our recorder
  private AudioRecord mRecorder;
  // Recorder features
  private NoiseSuppressor mNoiseSuppressor = null;
  private AutomaticGainControl mAutomaticGainControl = null;

  // Signals whether a recording is in progress (true) or not (false).
  private final AtomicInteger amplitude = new AtomicInteger(-160);
  // Max amplitude recorded
  private double maxAmplitude = -100.0;

  public AudioRecorder(
      @NonNull RecordConfig config,
      @NonNull RecorderStateStreamHandler recorderStateStreamHandler,
      @NonNull RecorderRecordStreamHandler recorderRecordStreamHandler
  ) throws Exception {
    super(recorderStateStreamHandler, recorderRecordStreamHandler);
    this.mConfig = config;

    mRecorder = createAudioRecord(mConfig);

    if (mConfig.noiseCancel) {
      mNoiseSuppressor = enableNoiseSuppressor(mRecorder);
    }
    if (mConfig.autoGain) {
      mAutomaticGainControl = enableAutomaticGainControl(mRecorder);
    }
  }

  @Override
  public int getInstanceId() {
    return mRecorder.getAudioSessionId();
  }

  @Override
  public void start() {
    mRecorder.startRecording();

    updateState(RECORD_STATE_RECORD);
  }

  @Override
  public String stop() {
    stopRecording();
    return mConfig.path;
  }

  @Override
  public void pause() {
    updateState(RECORD_STATE_PAUSE);
  }

  @Override
  public void resume() {
    updateState(RECORD_STATE_RECORD);
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

  public static boolean isEncoderSupported(String encoder) {
    return getAudioFormat(encoder) != null;
  }

  @Override
  public void close() {
    stopRecording();
  }

  private void stopRecording() {
    if (mRecorder != null) {
      try {
        if (mRecorder.getRecordingState() == RECORDSTATE_RECORDING) {
          mRecorder.stop();
        }
      } catch (IllegalStateException ex) {
        // Mute this exception, this should never happen
      } finally {
        // TODO stop encoding & muxing
      }
    }

    updateState(RECORD_STATE_STOP);
    release();

    amplitude.set(-100);
    maxAmplitude = -100;
  }

  private static Integer getAudioFormat(String encoder) {
    switch (encoder) {
      case "wav":
      case "pcm16bit":
        return AudioFormat.ENCODING_PCM_16BIT;
      case "pcm8bit":
        return AudioFormat.ENCODING_PCM_8BIT;
    }

    return null;
  }

  private AudioRecord createAudioRecord(RecordConfig config) throws Exception {
    final int audioFormat = getAudioFormat(config);
    final int channelConfig = getChannels(config);
    final int bufferSize = getBufferSize(config.samplingRate, channelConfig, audioFormat);

    AudioRecord recorder;
    try {
      recorder = new AudioRecord(
          MediaRecorder.AudioSource.DEFAULT,
          config.samplingRate,
          channelConfig,
          audioFormat,
          bufferSize);
    } catch (IllegalArgumentException e) {
      Log.d(TAG, e.getMessage());
      throw new Exception(e);
    }

    if (recorder.getState() != AudioRecord.STATE_INITIALIZED) {
      Log.d(TAG, "Unable to initialize AudioRecord");
      throw new Exception("Unable to initialize AudioRecord");
    }

    return recorder;
  }

  private int getAudioFormat(RecordConfig config) {
    Integer audioFormat = getAudioFormat(config.encoder);
    if (audioFormat == null) {
      Log.d(TAG, "Audio format is not supported.\nFalling back to PCM 16bits");
      audioFormat = AudioFormat.ENCODING_PCM_16BIT;
    }

    return audioFormat;
  }

  private int getChannels(RecordConfig config) {
    return config.numChannels == 1
        ? AudioFormat.CHANNEL_IN_MONO
        : AudioFormat.CHANNEL_IN_STEREO;
  }

  private int getBufferSize(int samplingRate, int channelConfig, int audioFormat) throws Exception {
    // Get min size of the buffer for writings
    final int bufferSize = AudioRecord.getMinBufferSize(
        samplingRate,
        channelConfig,
        audioFormat
    );
    if (bufferSize == ERROR_BAD_VALUE || bufferSize == ERROR) {
      Log.d(TAG, "Recording config is not supported by the hardware, or an invalid config was provided.");
      throw new Exception("Recording config is not supported by the hardware, or an invalid config was provided.");
    }

    return bufferSize;
  }

  @Nullable
  private NoiseSuppressor enableNoiseSuppressor(AudioRecord recorder) {
    NoiseSuppressor noiseSuppressor = null;

    if (NoiseSuppressor.isAvailable()) {
      noiseSuppressor = NoiseSuppressor.create(recorder.getAudioSessionId());
      if (noiseSuppressor != null) {
        noiseSuppressor.setEnabled(true);
      }
    }

    return noiseSuppressor;
  }

  @Nullable
  private AutomaticGainControl enableAutomaticGainControl(AudioRecord recorder) {
    AutomaticGainControl automaticGainControl = null;

    if (AutomaticGainControl.isAvailable()) {
      automaticGainControl = AutomaticGainControl.create(recorder.getAudioSessionId());
      if (automaticGainControl != null) {
        automaticGainControl.setEnabled(true);
      }
    }

    return automaticGainControl;
  }

  private void release() {
    if (mNoiseSuppressor != null) {
      mNoiseSuppressor.release();
      mNoiseSuppressor = null;
    }
    if (mAutomaticGainControl != null) {
      mAutomaticGainControl.release();
      mAutomaticGainControl = null;
    }

    if (mRecorder != null) {
      mRecorder.release();
      mRecorder = null;
    }
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
    private final CountDownLatch completion = new CountDownLatch(1);

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
        case ERROR_BAD_VALUE:
          str.append("AudioRecord.ERROR_BAD_VALUE");
          break;
        case AudioRecord.ERROR_DEAD_OBJECT:
          str.append("AudioRecord.ERROR_DEAD_OBJECT");
          break;
        case ERROR:
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
