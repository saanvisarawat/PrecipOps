import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models/volunteer_models.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_badge.dart';

/// Fullscreen simulated masked-call UI (module 8), modeled directly on a
/// real incoming-call screen: large glowing avatar centered on a dark
/// background, decline/accept as filled circular icon buttons with
/// labels underneath. In production this is pushed by the app when an
/// FCM data message with `type: "EMERGENCY_INCOMING_CALL"` arrives in the
/// background; today it's pushed by `simulateIncomingCall()`'s debug
/// trigger via the same [MaskedCallPayload] shape, so no screen code
/// changes once push lands.
class MaskedCallScreen extends StatefulWidget {
  final MaskedCallPayload payload;

  const MaskedCallScreen({super.key, required this.payload});

  @override
  State<MaskedCallScreen> createState() => _MaskedCallScreenState();
}

class _MaskedCallScreenState extends State<MaskedCallScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _glowController =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.payload;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Text(
                  'INCOMING EMERGENCY CALL',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 18),
                const StatusBadge(
                  label: 'CRITICAL',
                  color: AppColors.dangerStrong,
                  icon: Icons.warning_amber_rounded,
                  filled: true,
                ),
                const SizedBox(height: 28),
                AnimatedBuilder(
                  animation: _glowController,
                  builder: (context, child) {
                    final glow = 0.25 + _glowController.value * 0.35;
                    return Container(
                      width: 152,
                      height: 152,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // Glow only — the avatar itself stays a neutral
                        // dark fill so this doesn't turn into a large
                        // flat block of neon green.
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: glow * 0.5),
                            blurRadius: 40,
                            spreadRadius: 12,
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: Container(
                    width: 128,
                    height: 128,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceRaised,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.5), width: 2),
                    ),
                    child: const Icon(Icons.person_rounded, size: 68, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  payload.callerAlias,
                  style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Emergency Rescue Dispatch',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 15),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    children: [
                      _InfoRow(label: 'SOS ID', value: payload.sosId),
                      const SizedBox(height: 6),
                      _InfoRow(label: 'District', value: payload.district),
                      const SizedBox(height: 6),
                      _InfoRow(
                        label: 'Location',
                        value:
                            '${payload.latitude.toStringAsFixed(4)}, ${payload.longitude.toStringAsFixed(4)}',
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallActionButton(
                      color: AppColors.dangerStrong,
                      icon: Icons.call_end_rounded,
                      label: 'Decline',
                      onTap: () => context.pop(),
                    ),
                    _CallActionButton(
                      color: AppColors.accent,
                      icon: Icons.call_rounded,
                      label: 'Accept Mission',
                      onTap: () {
                        context.pop();
                        AppToast.show(context, 'Mission accepted — ${payload.sosId}', kind: AppToastKind.success);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CallActionButton({required this.color, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 68,
              height: 68,
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                size: 30,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
