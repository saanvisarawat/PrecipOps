import 'dart:typed_data';

/// Wraps raw 16-bit PCM samples (what the `record` package's cross-platform
/// `startStream` produces) in a standard 44-byte WAV header — no extra
/// package needed, and it keeps every mic-capture screen's audio pipeline
/// entirely in-memory (`Uint8List` in, `Uint8List` out), which is what
/// makes it work the same way on Web as on native.
Uint8List wrapPcm16AsWav(Uint8List pcm, {required int sampleRate, required int numChannels}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
  final blockAlign = numChannels * bitsPerSample ~/ 8;
  final buffer = Uint8List(44 + pcm.length);
  final bd = ByteData.sublistView(buffer);

  void writeAscii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      buffer[offset + i] = s.codeUnitAt(i);
    }
  }

  writeAscii(0, 'RIFF');
  bd.setUint32(4, 36 + pcm.length, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little); // PCM
  bd.setUint16(22, numChannels, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, byteRate, Endian.little);
  bd.setUint16(32, blockAlign, Endian.little);
  bd.setUint16(34, bitsPerSample, Endian.little);
  writeAscii(36, 'data');
  bd.setUint32(40, pcm.length, Endian.little);
  buffer.setRange(44, 44 + pcm.length, pcm);
  return buffer;
}
