import 'package:web/web.dart' as web;

import 'package:record_platform_interface/record_platform_interface.dart';

const mimeTypes = {
  // We apply same mime types for different encoding types for AAC
  AudioEncoder.aacLc: ['audio/mp4;codecs=mp4a', 'audio/aac'],
  AudioEncoder.aacEld: ['audio/mp4;codecs=mp4a', 'audio/aac'],
  AudioEncoder.aacHe: ['audio/mp4;codecs=mp4a', 'audio/aac'],

  AudioEncoder.amrNb: ['audio/AMR'],
  AudioEncoder.amrWb: ['audio/AMR-WB'],

  AudioEncoder.opus: [
    'audio/webm; codecs=opus',
    'audio/opus; codecs=opus',
    'audio/opus',
  ],

  AudioEncoder.flac: ['audio/flac', 'audio/x-flac'],

  AudioEncoder.wav: [
    'audio/wav',
    'audio/wav; codecs=1',
    'audio/vnd.wave; codec=1',
  ],

  AudioEncoder.pcm16bits: ['audio/pcm', 'audio/webm; codecs=pcm'],
};

String? getSupportedMimeType(AudioEncoder encoder) {
  final types = mimeTypes[encoder];
  if (types == null) return null;

  for (var type in types) {
    if (web.MediaRecorder.isTypeSupported(type)) {
      return type;
    }
  }

  return null;
}
