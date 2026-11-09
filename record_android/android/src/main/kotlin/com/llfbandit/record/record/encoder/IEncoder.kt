package com.llfbandit.record.record.encoder

interface IEncoder {
  fun startEncoding()

  /** Never throws; @return the teardown error. */
  fun stopEncoding(): Exception?

  /** Never waits: what the codec can't take yet is kept, so [bytes] must not be reused. */
  fun encode(bytes: ByteArray)

  /** Feeds kept input and writes ready output; called on every read, even without new bytes. */
  fun pump() {}
}
