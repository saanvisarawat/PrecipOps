import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_motion.dart';
import '../core/theme/app_radius.dart';

/// The ONLY container used for grouped content in this app — a premium
/// dark-graphite surface: large radius, a hairline ~8% white border, a
/// soft low-opacity shadow (never a heavy Material drop shadow), and
/// generous internal padding. Never a plain outlined Material `Card`.
class AppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? splashColor;
  final Color? highlightColor;
  final ValueChanged<bool>? onHighlightChanged;
  final bool tinted;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.onTap,
    this.gradient,
    this.splashColor,
    this.highlightColor,
    this.onHighlightChanged,
    this.tinted = false,
    this.radius = AppRadius.card,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(widget.radius);
    return AnimatedScale(
      scale: widget.onTap != null && _pressed ? AppMotion.pressScale : 1,
      duration: AppMotion.fast,
      curve: AppMotion.curve,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: widget.gradient ??
              (widget.tinted
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.surfaceHigh, AppColors.surface],
                    )
                  : null),
          color: widget.gradient == null && !widget.tinted ? (widget.color ?? AppColors.surface) : null,
          border: Border.all(color: AppColors.cardBorder, width: 1),
          boxShadow: AppColors.softShadow(),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            splashColor: widget.splashColor ?? AppColors.accentGlow,
            highlightColor: widget.highlightColor ?? AppColors.accent.withValues(alpha: 0.04),
            onHighlightChanged: (v) {
              setState(() => _pressed = v);
              widget.onHighlightChanged?.call(v);
            },
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}
