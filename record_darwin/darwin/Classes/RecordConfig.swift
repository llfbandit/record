enum AudioEncoder: String {
  case aacLc = "aacLc"
  case aacEld = "aacEld"
  case aacHe = "aacHe"
  case amrNb = "amrNb"
  case amrWb = "amrWb"
  case opus = "opus"
  case flac = "flac"
  case pcm16bits = "pcm16bits"
  case wav = "wav"
}


class RecordConfig {
  let encoder: String
  let bitRate: Int
  let sampleRate: Int
  let numChannels: Int
  let device: [String: Any]?
  let autoGain: Bool
  let echoCancel: Bool
  let noiseSuppress: Bool

  init(encoder: String,
       bitRate: Int,
       sampleRate: Int,
       numChannels: Int,
       device: [String : Any]? = nil,
       autoGain: Bool = false,
       echoCancel: Bool = false,
       noiseSuppress: Bool = false
  ) {
    self.encoder = encoder
    self.bitRate = bitRate
    self.sampleRate = sampleRate
    self.numChannels = numChannels
    self.device = device
    self.autoGain = autoGain
    self.echoCancel = echoCancel
    self.noiseSuppress = noiseSuppress
  }
}
