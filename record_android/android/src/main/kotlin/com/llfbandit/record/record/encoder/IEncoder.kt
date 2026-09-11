package com.llfbandit.record.record.encoder

interface IEncoder {
  /**
   * Start the encoder process.
   *
   * Can only be called if the encoder process is not already started.
   */
  fun startEncoding()

  /** Releases the encoder and answers with the failure that ended it; never throws. */
  fun stopEncoding(done: (Exception?) -> Unit)

  /**
   * Encode bytes of audio to file
   *
   * @param bytes - PCM input buffer
   */
  fun encode(bytes: ByteArray)
}