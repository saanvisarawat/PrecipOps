import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_motion.dart';
import '../core/theme/app_radius.dart';

enum AppToastKind { neutral, success, error }

/// Custom floating notification — a dark rounded card with a soft
/// shadow, small semantic icon and a brief slide/fade entrance. Replaces
/// Flutter's default `SnackBar` everywhere in this app.
class AppToast {
  AppToast._();

  static void show(
    BuildContext context,
    String message, {
    AppToastKind kind = AppToastKind.neutral,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ToastCard(
        message: message,
        kind: kind,
        duration: duration,
        onDismissed: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _ToastCard extends StatefulWidget {
  final String message;
  final AppToastKind kind;
  final Duration duration;
  final VoidCallback onDismissed;

  const _ToastCard({
    required this.message,
    required this.kind,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: AppMotion.standard);
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: AppMotion.curve);
  late final Animation<Offset> _slide =
      Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(_fade);

  @override
  void initState() {
    super.initState();
    _controller.forward();
    Future.delayed(widget.duration, () async {
      if (!mounted) return;
      await _controller.reverse();
      widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ({IconData icon, Color color}) get _visual => switch (widget.kind) {
        AppToastKind.success => (icon: Icons.check_circle_rounded, color: AppColors.accent),
        AppToastKind.error => (icon: Icons.error_rounded, color: AppColors.danger),
        AppToastKind.neutral => (icon: Icons.info_rounded, color: AppColors.textSecondary),
      };

  @override
  Widget build(BuildContext context) {
    final visual = _visual;
    return Positioned(
      left: 20,
      right: 20,
      bottom: 100,
      child: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh.withValues(alpha: 0.96),
                  borderRadius: AppRadius.smallR,
                  border: Border.all(color: AppColors.cardBorder),
                  boxShadow: AppColors.softShadow(opacity: 0.3, blur: 18),
                ),
                child: Row(
                  children: [
                    Icon(visual.icon, color: visual.color, size: 19),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
