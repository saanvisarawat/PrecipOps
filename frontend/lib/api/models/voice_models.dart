import 'dart:typed_data';

/// Result of a single POST /api/voice/agent round trip. The real backend
/// returns raw WAV audio bytes with no transcript field — [transcript] and
/// [replyText] are populated by the mock (for a believable demo) but stay
/// null against the real backend; the Voice Agent screen shows
/// "Transcript unavailable" rather than fabricating text when they're
/// null but [audioBytes] came back successfully.
class VoiceAgentResult {
  final String? transcript;
  final String? replyText;
  final Uint8List? audioBytes;
  final String? errorMessage;

  const VoiceAgentResult({this.transcript, this.replyText, this.audioBytes, this.errorMessage});

  bool get hasAudio => audioBytes != null && audioBytes!.isNotEmpty;
  bool get isError => errorMessage != null;
}
