import Foundation

// The level we report when we capture nothing.
let silenceDb: Float = -160.0

// Current and max input level, in dB.
struct Amplitude {
  let current: Float
  let max: Float
}
