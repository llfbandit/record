package com.llfbandit.record.record.header;

import java.io.DataOutput;
import java.io.IOException;

interface HeaderWriter {
  void write(DataOutput out) throws IOException;
}
