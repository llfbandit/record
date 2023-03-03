package com.llfbandit.record.record.processing;

import android.media.AudioRecord;

public class AudioProcessor implements Runnable {
  private volatile boolean mPauseFlag;
  private volatile boolean mStopFlag;
  private volatile boolean mMute;
  private AudioRecord mAudioRecord;
  private AudioEncoder mAudioEncoder;
  private byte[] mRecordBuffer;
  private int mRecordBufferSize;

  public AudioProcessor(AudioRecord audioRecord, AudioConfiguration audioConfiguration) {
    mRecordBufferSize = AudioUtils.getRecordBufferSize(audioConfiguration);
    mRecordBuffer =  new byte[mRecordBufferSize];
    mAudioRecord = audioRecord;
    mAudioEncoder = new AudioEncoder(audioConfiguration);
    mAudioEncoder.prepareEncoder();
  }

  public void setAudioHEncodeListener(OnAudioEncodeListener listener) {
    mAudioEncoder.setOnAudioEncodeListener(listener);
  }

  public void stopEncode() {
    mStopFlag = true;
    if(mAudioEncoder != null) {
      mAudioEncoder.stop();
      mAudioEncoder = null;
    }
  }

  public void pauseEncode(boolean pause) {
    mPauseFlag = pause;
  }

  public void setMute(boolean mute) {
    mMute = mute;
  }

  public void run() {
    while (!mStopFlag) {
      while (mPauseFlag) {
        try {
          Thread.sleep(1000);
        } catch (InterruptedException e) {
          e.printStackTrace();
        }
      }
      int readLen = mAudioRecord.read(mRecordBuffer, 0, mRecordBufferSize);
      if (readLen > 0) {
        if (mMute) {
          byte clearM = 0;
          Arrays.fill(mRecordBuffer, clearM);
        }
        if(mAudioEncoder != null) {
          mAudioEncoder.offerEncoder(mRecordBuffer);
        }
      }
    }
  }
}