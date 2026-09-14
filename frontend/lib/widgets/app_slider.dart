import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// The ONLY slider used in this app. A thick fully-rounded track
/// (emerald when active, a barely-visible track when inactive) and an
/// oversized soft-glow thumb — never Flutter's default thin grey
/// slider. Screens must never reach for a raw `Slider`.
class AppSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const AppSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 6,
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.surfaceHigh,
        trackShape: const RoundedRectSliderTrackShape(),
        thumbShape: const _GlowThumbShape(),
        overlayShape: SliderComponentShape.noOverlay,
        thumbColor: AppColors.accent,
      ),
      child: Slider(value: value, min: min, max: max, onChanged: onChanged),
    );
  }
}

class _GlowThumbShape extends SliderComponentShape {
  const _GlowThumbShape({this.radius = 10});
  final double radius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double textScaleFactor,
    required Size sizeWithOverflow,
    required double value,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(
      center,
      radius + 7,
      Paint()..color = AppColors.accentGlow,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(center, radius, Paint()..color = AppColors.accent);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.bg.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }
}
