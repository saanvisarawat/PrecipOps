import 'package:flutter/material.dart';

/// Custom circular map marker — a colored circle with a white icon and a
/// subtle white ring, used for every pin on every map in this app.
/// Deliberately never a default teardrop `Icons.location_on` pin.
class MapPinMarker extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final bool pulsing;

  const MapPinMarker({
    super.key,
    required this.icon,
    required this.color,
    this.size = 38,
    this.pulsing = false,
  });

  @override
  Widget build(BuildContext context) {
    // A bright fill (the neon accent) needs a dark glyph to stay legible.
    final glyphColor = color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    final core = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.75), width: 2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 12, spreadRadius: 1),
          const BoxShadow(color: Colors.black38, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      child: Icon(icon, color: glyphColor, size: size * 0.5),
    );
    if (!pulsing) return core;
    return _PulsingRing(color: color, size: size, child: core);
  }
}

class _PulsingRing extends StatefulWidget {
  final Widget child;
  final Color color;
  final double size;
  const _PulsingRing({required this.child, required this.color, required this.size});

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: (1 - t).clamp(0, 1),
              child: Container(
                width: widget.size * (1 + t * 1.4),
                height: widget.size * (1 + t * 1.4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: widget.color, width: 2),
                ),
              ),
            ),
            child!,
          ],
        );
      },
      child: widget.child,
    );
  }
}
