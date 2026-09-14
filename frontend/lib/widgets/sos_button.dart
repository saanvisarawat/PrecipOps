import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_motion.dart';

/// Emergency clarity first, elegance second — stays unmistakably red and
/// large regardless of the surrounding design language.
///
/// Fires [onPressed] only after a deliberate press-and-hold (guards
/// against an accidental tap dispatching a real emergency report) — a
/// progress ring sweeps around the button while held and resets if
/// released early. The public contract (`onPressed`/`isBusy`) is
/// unchanged, so callers need no changes.
class SosButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isBusy;

  const SosButton({super.key, required this.onPressed, this.isBusy = false});

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> with TickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 850);

  late final AnimationController _pulseController;
  late final AnimationController _holdController;
  bool _fired = false;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _holdController = AnimationController(vsync: this, duration: _holdDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_fired) {
          _fired = true;
          widget.onPressed();
        }
      });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _holdController.dispose();
    super.dispose();
  }

  void _startHold() {
    if (widget.isBusy) return;
    _fired = false;
    setState(() => _holding = true);
    _holdController.forward(from: 0);
  }

  void _cancelHold() {
    setState(() => _holding = false);
    if (_fired) return; // already completed — let the caller's own state take over
    _holdController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: widget.isBusy ? null : (_) => _startHold(),
      onLongPressEnd: widget.isBusy ? null : (_) => _cancelHold(),
      onLongPressCancel: widget.isBusy ? null : _cancelHold,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseController, _holdController]),
        builder: (context, child) {
          final scale = 1.0 + _pulseController.value * 0.04 - _holdController.value * 0.035;
          return Transform.scale(scale: scale, child: child);
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 192,
              height: 192,
              child: AnimatedBuilder(
                animation: _holdController,
                builder: (context, _) => CircularProgressIndicator(
                  value: _holdController.value,
                  strokeWidth: 4,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ),
            Container(
              width: 176,
              height: 176,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.dangerStrong,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.dangerStrong.withValues(alpha: 0.35),
                    blurRadius: 22,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: widget.isBusy
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                    )
                  : AnimatedSwitcher(
                      duration: AppMotion.fast,
                      child: _holding
                          ? const Column(
                              key: ValueKey('holding'),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.emergency_share_rounded, color: Colors.white, size: 40),
                                SizedBox(height: 6),
                                Text(
                                  'HOLD',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            )
                          : const Column(
                              key: ValueKey('idle'),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.emergency_share_rounded, color: Colors.white, size: 44),
                                SizedBox(height: 6),
                                Text(
                                  'SOS',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
