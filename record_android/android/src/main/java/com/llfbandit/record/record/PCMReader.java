package com.llfbandit.record.record;

import static android.media.AudioRecord.ERROR;
import static android.media.AudioRecord.ERROR_BAD_VALUE;
import static android.media.AudioRecord.RECORDSTATE_RECORDING;

import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.media.audiofx.AutomaticGainControl;
import android.media.audiofx.NoiseSuppressor;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.concurrent.atomic.AtomicInteger;

public class PCMReader {
  // Config to setup the recording
  private final RecordConfig config;
  // Recorder & features
  private AudioRecord reader;
  private NoiseSuppressor noiseSuppressor;
  private AutomaticGainControl automaticGainControl;
  // Min size of the buffer for writings
  private int bufferSize;
  // Last acquired amplitude
  private final AtomicInteger amplitude = new AtomicInteger(-160);

  public PCMReader(RecordConfig config) throws Exception {
    this.config = config;

    createReader();
    enableNoiseSuppressor();
    enableAutomaticGainControl();
  }

  public int getBufferSize() {
    return bufferSize;
  }

  public void start() {
    reader.startRecording();
  }

  public int read(ByteBuffer audioBuffer) throws Exception {
    int resultBytes = reader.read(audioBuffer, bufferSize);
    if (resultBytes < 0) {
      throw new Exception(getReadFailureReason(resultBytes));
    }

    byte[] buffer = new byte[resultBytes];
    audioBuffer.get(buffer, 0, resultBytes);

    // Update amplitude
    amplitude.set(getAmplitude(
        buffer,
        resultBytes,
        reader.getAudioFormat() == AudioFormat.ENCODING_PCM_8BIT ? 1 : 2
    ));

    return resultBytes;
  }

  public void stop() {
    if (reader != null) {
      try {
        if (reader.getRecordingState() == RECORDSTATE_RECORDING) {
          reader.stop();
        }
      } catch (IllegalStateException ex) {
        // Mute this exception, this should never happen
      }
    }
  }

  public int getAmplitude() {
    return amplitude.get();
  }

  private void createReader() throws Exception {
    final int audioFormat = getAudioFormat();
    final int channelConfig = getChannels();
    bufferSize = getMinBufferSize(config.samplingRate, channelConfig, audioFormat);

    try {
      reader = new AudioRecord(
          MediaRecorder.AudioSource.DEFAULT,
          config.samplingRate,
          channelConfig,
          audioFormat,
          bufferSize);
    } catch (IllegalArgumentException e) {
      throw new Exception("Unable to instantiate PCM reader.", e);
    }

    if (reader.getState() != AudioRecord.STATE_INITIALIZED) {
      release();
      throw new Exception("PCM reader failed to initialize.");
    }
  }

  private Integer getAudioFormat() {
    if ("pcm8bit".equals(config.encoder)) {
      return AudioFormat.ENCODING_PCM_8BIT;
    }
    return AudioFormat.ENCODING_PCM_16BIT;
  }

  private int getChannels() {
    return config.numChannels == 1
        ? AudioFormat.CHANNEL_IN_MONO
        : AudioFormat.CHANNEL_IN_STEREO;
  }

  private int getMinBufferSize(int samplingRate, int channelConfig, int audioFormat) throws Exception {
    // Get min size of the buffer for writings
    final int bufferSize = AudioRecord.getMinBufferSize(
        samplingRate,
        channelConfig,
        audioFormat
    );
    if (bufferSize == ERROR_BAD_VALUE || bufferSize == ERROR) {
      throw new Exception("Recording config is not supported by the hardware, or an invalid config was provided.");
    }

    // Stay away from minimal buffer
    return bufferSize * 4;
  }

  private void enableNoiseSuppressor() {
    if (config.noiseCancel && NoiseSuppressor.isAvailable()) {
      noiseSuppressor = NoiseSuppressor.create(reader.getAudioSessionId());
      if (noiseSuppressor != null) {
        noiseSuppressor.setEnabled(true);
      }
    }
  }

  private void enableAutomaticGainControl() {
    if (config.autoGain && AutomaticGainControl.isAvailable()) {
      automaticGainControl = AutomaticGainControl.create(reader.getAudioSessionId());
      if (automaticGainControl != null) {
        automaticGainControl.setEnabled(true);
      }
    }
  }

  private String getReadFailureReason(int errorCode) {
    StringBuilder str = new StringBuilder("Error when reading audio data:\n");

    switch (errorCode) {
      case AudioRecord.ERROR_INVALID_OPERATION:
        str.append("ERROR_INVALID_OPERATION: Failure due to the improper use of a method.");
        break;
      case ERROR_BAD_VALUE:
        str.append("ERROR_BAD_VALUE: Failure due to the use of an invalid value.");
        break;
      case AudioRecord.ERROR_DEAD_OBJECT:
        str.append("ERROR_DEAD_OBJECT: Object is no longer valid and needs to be recreated.");
        break;
      case ERROR:
        str.append("ERROR: Generic operation failure");
        break;
      default:
        str.append("Unknown errorCode: (").append(errorCode).append(")");
        break;
    }

    return str.toString();
  }

  public void release() {
    if (reader != null) {
      reader.release();
      reader = null;
    }

    if (noiseSuppressor != null) {
      noiseSuppressor.release();
      noiseSuppressor = null;
    }
    if (automaticGainControl != null) {
      automaticGainControl.release();
      automaticGainControl = null;
    }
  }

  private int getAmplitude(byte[] chunk, int size, int bytesPerSample) {
    int maxSample = -160;

    if (bytesPerSample == 2) { // PCM 16 bits
      final ByteBuffer byteBuffer = ByteBuffer.wrap(chunk, 0, size);
      final short[] buf = new short[size / 2];
      byteBuffer.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(buf);

      for (short b : buf) {
        int curSample = Math.abs(b);
        if (curSample > maxSample) {
          maxSample = curSample;
        }
      }

      return (int) (20 * Math.log10(maxSample / 32768.0)); // 16 signed bits 2^15
    } else /* if (bytesPerSample == 1) */ { // PCM 8 bits
      for (int i = 0; i < size; i++) {
        int curSample = Math.abs(chunk[i]);
        if (curSample > maxSample) {
          maxSample = curSample;
        }
      }

      return (int) (20 * Math.log10(maxSample / 127.0)); // 8 signed bits 2^7
    }
  }
}
