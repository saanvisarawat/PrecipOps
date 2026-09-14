import 'dart:math';

import 'package:flutter/material.dart';
// latlong2 exports its own `Path<T>` (a geodesic path), which collides
// with dart:ui's `Path` (used below for the heading-cone canvas shape) —
// this file only needs `LatLng`/`Tween` from latlong2, so hide the rest.
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';

class LatLngTween extends Tween<LatLng> {
  LatLngTween({required LatLng begin, required LatLng end}) : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) => LatLng(
        begin!.latitude + (end!.latitude - begin!.latitude) * t,
        begin!.longitude + (end!.longitude - begin!.longitude) * t,
      );
}

/// Animates the on-map location dot between successive GPS fixes instead
/// of letting it jump — flutter_map repositions a [Marker] using whatever
/// `point` it's given each build, so smoothing has to happen by animating
/// that point value over time and rebuilding, which is what this does.
/// Owns an [AnimationController], so it needs a [TickerProvider] from the
/// hosting screen (typically `this` on a `SingleTickerProviderStateMixin`
/// state).
class SmoothedPosition extends ChangeNotifier {
  SmoothedPosition({required TickerProvider vsync, required LatLng initial})
      : _controller = AnimationController(vsync: vsync, duration: AppMotion.standard),
        _current = initial {
    _controller.addListener(() {
      final tween = _tween;
      if (tween != null) {
        _current = tween.lerp(Curves.easeOut.transform(_controller.value));
        notifyListeners();
      }
    });
  }

  final AnimationController _controller;
  LatLng _current;
  LatLngTween? _tween;

  LatLng get value => _current;

  void moveTo(LatLng target) {
    if (target.latitude == _current.latitude && target.longitude == _current.longitude) return;
    _tween = LatLngTween(begin: _current, end: target);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// The blue "you are here" puck: a heading cone (when heading is known)
/// plus a white-ringed dot. The accuracy radius is drawn separately as a
/// [CircleMarker] in meters (see NavigationMapScreen) since it must scale
/// with map zoom, unlike this fixed-size widget.
class LocationPuck extends StatelessWidget {
  final double? headingDegrees;
  const LocationPuck({super.key, this.headingDegrees});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (headingDegrees != null)
            Transform.rotate(
              angle: headingDegrees! * pi / 180,
              child: CustomPaint(size: const Size(44, 44), painter: _HeadingConePainter()),
            ),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadingConePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [AppColors.accent.withValues(alpha: 0.35), AppColors.accent.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(center: center, radius: size.width / 2));

    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx - 9, center.dy - 20)
      ..arcToPoint(Offset(center.dx + 9, center.dy - 20), radius: const Radius.circular(10))
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeadingConePainter oldDelegate) => false;
}
