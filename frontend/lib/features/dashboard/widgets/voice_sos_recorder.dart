import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';

import '../../../api/floodops_api.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_typography.dart';
import '../../../providers/api_provider.dart';
import '../../../providers/service_providers.dart';
import '../../../services/audio_wav_utils.dart';

enum _RecState { idle, recording, sending, sent, error, permissionDenied }

/// Voice SOS — a tap-to-record/tap-to-stop alternative to the SOS text
/// composer for citizens who can't type: elderly, low-literacy, panicked,
/// or in the dark. Records raw PCM, wraps it as WAV, and posts it straight
/// to POST /api/voice/agent (Sarvam STT/TTS + Gemini) with the device's
/// live GPS fix — the same real endpoint the dedicated Voice Agent screen
/// uses, just packaged for the emergency-report flow instead.
class VoiceSosRecorder extends ConsumerStatefulWidget {
  const VoiceSosRecorder({super.key});

  @override
  ConsumerState<VoiceSosRecorder> createState() => _VoiceSosRecorderState();
}

class _VoiceSosRecorderState extends ConsumerState<VoiceSosRecorder> with SingleTickerProviderStateMixin {
  static const _sampleRate = 16000;

  final _recorder = AudioRecorder();
  final BytesBuilder _pcmBuffer = BytesBuilder();
  StreamSubscription<Uint8List>? _recordSub;
  Completer<void>? _streamDone;
  late final AnimationController _pulseController;

  _RecState _state = _RecState.idle;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _recordSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_state == _RecState.recording) {
      await _stopAndSend();
      return;
    }
    if (_state == _RecState.sending) return;
    await _startRecording();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      setState(() => _state = _RecState.permissionDenied);
      return;
    }
    _pcmBuffer.clear();
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
    ));
    _streamDone = Completer<void>();
    _recordSub = stream.listen(
      _pcmBuffer.add,
      // Ordering guarantee: `onDone` only fires after every preceding
      // `data` event is delivered, so `_stopAndSend` waits on this rather
      // than risking a truncated last chunk.
      onDone: () {
        if (!(_streamDone?.isCompleted ?? true)) _streamDone!.complete();
      },
    );
    if (!mounted) return;
    setState(() {
      _state = _RecState.recording;
      _errorText = null;
    });
  }

  Future<void> _stopAndSend() async {
    await _recorder.stop();
    await _streamDone?.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    await _recordSub?.cancel();
    _recordSub = null;
    final pcm = _pcmBuffer.takeBytes();
    if (pcm.isEmpty) {
      setState(() => _state = _RecState.idle);
      return;
    }
    final wavBytes = wrapPcm16AsWav(pcm, sampleRate: _sampleRate, numChannels: 1);
    setState(() => _state = _RecState.sending);

    double? lat, lng;
    try {
      final pos = await ref.read(locationServiceProvider).getCurrentPosition();
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      // Fall through to the error state below — an SOS voice report with
      // no location attached is worse than telling the citizen to retry
      // with GPS on, since the whole point is rescuers finding them.
    }
    if (lat == null || lng == null) {
      if (!mounted) return;
      setState(() {
        _state = _RecState.error;
        _errorText = 'Could not get your GPS location — check that Location is turned on and try again.';
      });
      return;
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
        _state = _RecState.error;
        _errorText = result.errorMessage;
      });
      return;
    }
    setState(() => _state = _RecState.sent);
  }

  Future<void> _cancelRecording() async {
    await _recorder.stop();
    await _recordSub?.cancel();
    _recordSub = null;
    _pcmBuffer.clear();
    setState(() => _state = _RecState.idle);
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _RecState.permissionDenied) {
      return _StatusPanel(
        icon: Icons.mic_off_rounded,
        color: AppColors.danger,
        message: 'Microphone access is needed to send a voice SOS.',
        actionLabel: 'Open App Settings',
        onAction: () async {
          await Geolocator.openAppSettings();
          if (mounted) setState(() => _state = _RecState.idle);
        },
      );
    }
    if (_state == _RecState.error) {
      return _StatusPanel(
        icon: Icons.error_outline_rounded,
        color: AppColors.dangerStrong,
        message: _errorText ?? 'Something went wrong sending your voice message.',
        actionLabel: 'Try Again',
        onAction: () => setState(() => _state = _RecState.idle),
      );
    }
    if (_state == _RecState.sent) {
      return _StatusPanel(
        icon: Icons.check_circle_rounded,
        color: AppColors.accent,
        message: 'Voice SOS sent with your live location.',
        actionLabel: 'Record Another',
        onAction: () => setState(() => _state = _RecState.idle),
      );
    }

    final recording = _state == _RecState.recording;
    final sending = _state == _RecState.sending;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: sending ? null : _onTap,
              onLongPress: recording ? _cancelRecording : null,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final pulse = recording ? 0.12 * sin(_pulseController.value * 2 * pi) : 0.0;
                  return Transform.scale(scale: 1 + pulse, child: child);
                },
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: recording ? AppColors.dangerStrong : AppColors.danger,
                    boxShadow: AppColors.softShadow(opacity: recording ? 0.4 : 0.22, blur: recording ? 22 : 14),
                  ),
                  child: sending
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : Icon(recording ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 28),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          sending
              ? 'Sending your voice message…'
              : recording
                  ? 'Recording — tap to send, hold to cancel'
                  : "Can't type? Just speak.",
          textAlign: TextAlign.center,
          style: AppTypography.caption(color: recording ? AppColors.dangerStrong : AppColors.textSecondary)
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _StatusPanel({
    required this.icon,
    required this.color,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: AppTypography.body(color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onAction,
          child: Text(actionLabel, style: AppTypography.label(color: color).copyWith(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
