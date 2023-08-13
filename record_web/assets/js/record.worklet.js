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
    if (this.isBufferFull()) {
      this.flush()
    }

    if (!channelData) return

    for (let i = 0; i < channelData.length; i++) {
      this._buffer[this._bytesWritten++] = channelData[i]
    }
  }

  flush() {
    const inputData = this._bytesWritten < this.bufferSize
      ? this._buffer.slice(0, this._bytesWritten)
      : this._buffer

    // Converts samples to 16-bit signed range is -32768 to 32767
    let output = new DataView(new ArrayBuffer(inputData.length * 2));
    for (let i = 0; i < inputData.length; i++) {
      let multiplier = inputData[i] < 0 ? 0x8000 : 0x7fff;
      output.setInt16(i * 2, inputData[i] * multiplier | 0, true); // index, value as int, little edian
    }

    let intData = new Int16Array(output.buffer);
    let index = intData.length;
    while (index-- && intData[index] === 0 && index > 0) { }

    this.port.postMessage(intData.slice(0, index + 1))

    this.initBuffer()
  }
}

registerProcessor("recorder.worklet", RecorderProcessor)