import 'package:record_platform_interface/record_platform_interface.dart';

const mimeTypes = {
  // We apply same mime types for different encoding types for AAC
  AudioEncoder.aacLc: ['audio/aac', 'audio/mp4'],
  AudioEncoder.aacEld: ['audio/aac', 'audio/mp4'],
  AudioEncoder.aacHe: ['audio/aac', 'audio/mp4'],

  AudioEncoder.amrNb: ['audio/AMR'],
  AudioEncoder.amrWb: ['audio/AMR-WB'],

  AudioEncoder.opus: [
    'audio/opus',
    'audio/opus; codecs=opus',
    'audio/webm; codecs=opus',
  ],

  AudioEncoder.vorbisOgg: [
    'audio/vorbis',
    'audio/ogg',
    'audio/ogg; codecs=vorbis',
    'audio/webm; codecs=vorbis',
  ],

  AudioEncoder.flac: ['audio/flac', 'audio/x-flac'],

  AudioEncoder.wav: ['audio/wav', 'audio/wav; codecs=1'],

  AudioEncoder.pcm16bit: ['audio/pcm', 'audio/webm; codecs=pcm'],
};
