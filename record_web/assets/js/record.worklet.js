class RecorderProcessor extends AudioWorkletProcessor {
  // Buffer size compromise between size and process call frequency
  bufferSize = 4096
  // The current buffer fill level
  _bytesWritten = 0

  // Create a buffer of fixed size
  _buffer = new Float32Array(this.bufferSize)

  constructor() {
    super()
    this.initBuffer()
  }

  initBuffer() {
    this._bytesWritten = 0
  }

  /**
   * @returns {boolean}
   */
  isBufferEmpty() {
    return this._bytesWritten === 0
  }

  /**
   * @returns {boolean}
   */
  isBufferFull() {
    return this._bytesWritten === this.bufferSize
  }

  /**
   * @param {Float32Array[][]} inputs
   * @returns {boolean}
   */
  process(inputs) {
    const input = inputs[0]

    input.forEach((channelData) => {
      this.append(channelData)
    })

    return true
  }

  /**
   * @param {Float32Array} channelData
   */
  append(channelData) {
    if (!channelData) return

    if (this.isBufferFull()) {
      this.flush()
    }

    for (let i = 0; i < channelData.length; i++) {
      this._buffer[this._bytesWritten++] = channelData[i]
    }
  }

  flush() {
    // trim the buffer if ended prematurely
    this.port.postMessage(
      this._bytesWritten < this.bufferSize
        ? this._buffer.slice(0, this._bytesWritten)
        : this._buffer
    )
    
    this.initBuffer()
  }

}

registerProcessor("recorder.worklet", RecorderProcessor)