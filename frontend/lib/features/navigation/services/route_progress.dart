import 'package:latlong2/latlong.dart';

import '../models/route_option.dart';

const _distance = Distance();

/// Live progress along a [RouteOption], recomputed on every GPS update.
///
/// This is intentionally not full map-matching: it finds the closest
/// point on the route's own polyline to the current fix and measures
/// forward from there. That's accurate enough for on-route guidance and
/// far simpler than snapping to a road graph — a real difference only
/// shows up if the user goes badly off-route, which active navigation
/// already surfaces via a growing "distance to route" rather than
/// silently producing nonsense.
class RouteProgress {
  final double remainingDistanceMeters;
  final Duration remainingDuration;
  final int currentStepIndex;
  final double distanceToManeuverMeters;
  final double distanceOffRouteMeters;

  const RouteProgress({
    required this.remainingDistanceMeters,
    required this.remainingDuration,
    required this.currentStepIndex,
    required this.distanceToManeuverMeters,
    required this.distanceOffRouteMeters,
  });

  static RouteProgress compute(RouteOption route, LatLng position) {
    final points = route.points;
    if (points.isEmpty) {
      return RouteProgress(
        remainingDistanceMeters: route.distanceMeters,
        remainingDuration: route.duration,
        currentStepIndex: 0,
        distanceToManeuverMeters: route.distanceMeters,
        distanceOffRouteMeters: 0,
      );
    }

    var nearestIndex = 0;
    var nearestDist = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final d = _distance.as(LengthUnit.Meter, position, points[i]);
      if (d < nearestDist) {
        nearestDist = d;
        nearestIndex = i;
      }
    }

    var remaining = _distance.as(LengthUnit.Meter, position, points[nearestIndex]);
    for (var i = nearestIndex; i < points.length - 1; i++) {
      remaining += _distance.as(LengthUnit.Meter, points[i], points[i + 1]);
    }

    final progressRatio = route.distanceMeters == 0 ? 1.0 : (1 - (remaining / route.distanceMeters)).clamp(0.0, 1.0);
    final remainingDuration = Duration(seconds: (route.duration.inSeconds * (1 - progressRatio)).round());

    var stepIndex = 0;
    var distanceToManeuver = remaining;
    if (route.steps.isNotEmpty && !route.isOfflineEstimate) {
      final boundaryIndices = route.steps.map((s) => _nearestPointIndex(points, s.point)).toList();
      stepIndex = boundaryIndices.length - 1;
      for (var i = 0; i < boundaryIndices.length; i++) {
        if (boundaryIndices[i] >= nearestIndex) {
          stepIndex = i;
          break;
        }
      }
      final boundaryIndex = boundaryIndices[stepIndex].clamp(nearestIndex, points.length - 1);
      distanceToManeuver = _distance.as(LengthUnit.Meter, position, points[nearestIndex]);
      for (var i = nearestIndex; i < boundaryIndex; i++) {
        distanceToManeuver += _distance.as(LengthUnit.Meter, points[i], points[i + 1]);
      }
    }

    return RouteProgress(
      remainingDistanceMeters: remaining,
      remainingDuration: remainingDuration,
      currentStepIndex: stepIndex,
      distanceToManeuverMeters: distanceToManeuver,
      distanceOffRouteMeters: nearestDist,
    );
  }

  static int _nearestPointIndex(List<LatLng> points, LatLng target) {
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final d = _distance.as(LengthUnit.Meter, target, points[i]);
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }
}
