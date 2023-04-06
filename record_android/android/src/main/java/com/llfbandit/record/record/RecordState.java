package com.llfbandit.record.record;

public enum RecordState {
  PAUSE(0),
  RECORD(1),
  STOP(2);
  final int id;

  RecordState(int id) {
    this.id = id;
  }
}