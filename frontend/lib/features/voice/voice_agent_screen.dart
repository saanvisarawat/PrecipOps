import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';

import '../../api/floodops_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/api_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_toast.dart';

enum _VoiceState { idle, listening, thinking, speaking, error }

/// Premium iOS-style voice interface for POST /api/voice/agent — press and
/// hold the mic to ask a question, release to send. A central waveform
/// reflects Listening/Thinking/Speaking, with the transcript and AI
/// response surfaced as text alongside the spoken reply.
class VoiceAgentScreen extends ConsumerStatefulWidget {
  const VoiceAgentScreen({super.key});

  @override
  ConsumerState<VoiceAgentScreen> createState() => _VoiceAgentScreenState();
}

class _VoiceAgentScreenState extends ConsumerState<VoiceAgentScreen> with SingleTickerProviderStateMixin {
  static const _sampleRate = 16000;

  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _tts = FlutterTts();
  final BytesBuilder _pcmBuffer = BytesBuilder();
  StreamSubscription<Uint8List>? _recordSub;
  Completer<void>? _streamDone;
  late final AnimationController _waveController;

  _VoiceState _state = _VoiceState.idle;
  String? _transcript;
  String? _replyText;
  String? _errorText;
  bool _hasAudio = false;
  bool _speakingViaTts = false;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
    _tts.setLanguage('en-IN');
    _tts.setSpeechRate(0.48);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speakingViaTts = false);
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _recordSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (_state == _VoiceState.thinking || _state == _VoiceState.listening) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        AppToast.show(context, 'Microphone permission is needed for the Voice Agent.', kind: AppToastKind.error);
      }
      return;
    }
    _pcmBuffer.clear();
    // Streamed raw PCM (not `.start(..., path: ...)`) so this works
    // identically on native platforms and Flutter Web — web has no real
    // filesystem path to read the recording back from afterwards.
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
    ));
    _streamDone = Completer<void>();
    _recordSub = stream.listen(
      _pcmBuffer.add,
      // The record package's own docs: "you must rely on stream close
      // event to get full recorded data" — the last chunk can still be
      // in flight when `stop()` returns, so `_stopAndSend` waits on this
      // completer (Dart stream ordering guarantees `onDone` only fires
      // after every preceding `data` event has been delivered).
      onDone: () {
        if (!(_streamDone?.isCompleted ?? true)) _streamDone!.complete();
      },
    );
    setState(() {
      _state = _VoiceState.listening;
      _transcript = null;
      _replyText = null;
      _errorText = null;
      _hasAudio = false;
    });
  }

  Future<void> _stopAndSend() async {
    if (_state != _VoiceState.listening) return;
    await _recorder.stop();
    await _streamDone?.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    await _recordSub?.cancel();
    _recordSub = null;
    final pcm = _pcmBuffer.takeBytes();
    if (pcm.isEmpty) {
      setState(() => _state = _VoiceState.idle);
      return;
    }
    final wavBytes = _wrapPcm16AsWav(pcm, sampleRate: _sampleRate, numChannels: 1);
    setState(() => _state = _VoiceState.thinking);

    double lat = 9.9816, lng = 76.2999; // Ernakulam fallback if GPS unavailable
    try {
      final pos = await ref.read(locationServiceProvider).getCurrentPosition();
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      // Proceed with the fallback center — the voice agent still answers
      // general safety questions without a precise fix.
    }

    VoiceAgentResult result;
    try {
      result = await ref.read(preciopsApiProvider).sendVoiceQuery(lat: lat, lng: lng, audioBytes: wavBytes);
    } catch (e) {
      result = const VoiceAgentResult(errorMessage: 'Could not reach the Voice Agent. Please try again.');
    }
    if (!mounted) return;

    if (result.isError) {
      setState(() {
        _state = _VoiceState.error;
        _errorText = result.errorMessage;
      });
      return;
    }

    setState(() {
      _state = _VoiceState.speaking;
      _transcript = result.transcript;
      _replyText = result.replyText;
      _hasAudio = result.hasAudio;
    });

    if (result.hasAudio) {
      // Real backend audio always wins when present.
      try {
        await _player.play(BytesSource(result.audioBytes!));
      } catch (_) {
        // Playback failure still leaves the transcript/response visible.
      }
    } else if ((result.replyText ?? '').trim().isNotEmpty) {
      // No audio came back (this is always true in mock mode, and would
      // also be true if the real backend ever added a text-only reply
      // path) — read the reply aloud on-device instead of leaving the
      // Voice Agent silent, which defeats the point of a voice interface.
      setState(() => _speakingViaTts = true);
      try {
        await _tts.speak(result.replyText!);
      } catch (_) {
        if (mounted) setState(() => _speakingViaTts = false);
      }
    }
  }

  Future<void> _cancelListening() async {
    if (_state != _VoiceState.listening) return;
    await _recorder.stop();
    await _recordSub?.cancel();
    _recordSub = null;
    _pcmBuffer.clear();
    setState(() => _state = _VoiceState.idle);
  }

  /// Wraps raw 16-bit PCM samples (what `record`'s cross-platform
  /// `startStream` produces) in a standard 44-byte WAV header — no extra
  /// package needed, and it keeps this screen's audio pipeline entirely
  /// in-memory (`Uint8List` in, `Uint8List` out), which is what makes it
  /// work the same way on Web as on native.
  Uint8List _wrapPcm16AsWav(Uint8List pcm, {required int sampleRate, required int numChannels}) {
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

  bool get _mentionsShelter {
    final text = '${_transcript ?? ''} ${_replyText ?? ''}'.toLowerCase();
    return text.contains('shelter') || text.contains('camp') || text.contains('evacuat');
  }

  String get _stateLabel => switch (_state) {
        _VoiceState.idle => 'Hold the mic and ask your question',
        _VoiceState.listening => 'Listening…',
        _VoiceState.thinking => 'Thinking…',
        _VoiceState.speaking => _speakingViaTts ? 'Speaking…' : 'Responding',
        _VoiceState.error => 'Something went wrong',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Agent')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.lg),
              Text(_stateLabel, style: AppTypography.sectionTitle()),
              const SizedBox(height: AppSpacing.section),
              SizedBox(
                height: 140,
                child: Center(
                  child: AnimatedBuilder(
                    animation: _waveController,
                    builder: (context, _) => CustomPaint(
                      size: const Size(240, 120),
                      painter: _WaveformPainter(
                        progress: _waveController.value,
                        active: _state == _VoiceState.listening || _state == _VoiceState.speaking,
                        color: _state == _VoiceState.listening ? AppColors.info : AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              Expanded(
                child: ListView(
                  children: [
                    if (_transcript != null)
                      _TextPanel(
                        label: 'You said',
                        icon: Icons.mic_none_rounded,
                        text: _transcript!,
                      ),
                    if (_transcript == null && _state == _VoiceState.speaking)
                      const _TextPanel(
                        label: 'You said',
                        icon: Icons.mic_none_rounded,
                        text: 'Transcript unavailable — the backend doesn\'t return one yet.',
                        muted: true,
                      ),
                    if (_replyText != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _TextPanel(
                        label: 'Preciops AI',
                        icon: Icons.shield_moon_outlined,
                        text: _replyText!,
                      ),
                    ] else if (_hasAudio) ...[
                      const SizedBox(height: AppSpacing.sm),
                      const _TextPanel(
                        label: 'Preciops AI',
                        icon: Icons.shield_moon_outlined,
                        text: 'Response received — playing spoken reply. '
                            '(The backend returns audio only; a text transcript isn\'t available yet.)',
                        muted: true,
                      ),
                    ],
                    if (_errorText != null)
                      _TextPanel(
                        label: 'Error',
                        icon: Icons.error_outline_rounded,
                        text: _errorText!,
                        color: AppColors.dangerStrong,
                      ),
                    if (_mentionsShelter && _state == _VoiceState.speaking) ...[
                      const SizedBox(height: AppSpacing.md),
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/navigate'),
                          icon: const Icon(Icons.north_east_rounded, size: 18),
                          label: const Text('Navigate'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.info,
                            side: const BorderSide(color: AppColors.info),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.section),
                child: GestureDetector(
                  onLongPressStart: (_) => _startListening(),
                  onLongPressEnd: (_) => _stopAndSend(),
                  onLongPressCancel: _cancelListening,
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    width: _state == _VoiceState.listening ? 96 : 84,
                    height: _state == _VoiceState.listening ? 96 : 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _state == _VoiceState.listening ? AppColors.info : AppColors.accent,
                      boxShadow: AppColors.softShadow(opacity: 0.3, blur: 18),
                    ),
                    child: Icon(
                      _state == _VoiceState.thinking ? Icons.hourglass_top_rounded : Icons.mic_rounded,
                      color: Colors.black,
                      size: 34,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextPanel extends StatelessWidget {
  final String label;
  final IconData icon;
  final String text;
  final bool muted;
  final Color? color;

  const _TextPanel({required this.label, required this.icon, required this.text, this.muted = false, this.color});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color ?? AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label, style: AppTypography.label(color: color ?? AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: AppTypography.body(color: muted ? AppColors.textTertiary : AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// Lightweight animated waveform — bars breathing at slightly randomized
/// heights while `active`, flat and still at rest. No external charting
/// package needed.
class _WaveformPainter extends CustomPainter {
  final double progress;
  final bool active;
  final Color color;

  _WaveformPainter({required this.progress, required this.active, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 24;
    final barWidth = size.width / (barCount * 1.6);
    final paint = Paint()
      ..color = color
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < barCount; i++) {
      final phase = (progress * 2 * pi) + (i * 0.5);
      final amplitude = active ? (0.25 + 0.7 * (0.5 + 0.5 * sin(phase))) : 0.08;
      final barHeight = size.height * amplitude;
      final x = i * (size.width / barCount) + barWidth / 2;
      final centerY = size.height / 2;
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.active != active || oldDelegate.color != color;
}
