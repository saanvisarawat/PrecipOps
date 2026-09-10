import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../utils/format.dart';

enum RouteRank { suggested, fastest, alternative }

extension RouteRankLabel on RouteRank {
  String get label {
    switch (this) {
      case RouteRank.suggested:
        return 'Suggested';
      case RouteRank.fastest:
        return 'Fastest';
      case RouteRank.alternative:
        return 'Alternative';
    }
  }
}

/// One turn-by-turn maneuver. Only ever populated from a real OSRM `steps`
/// response — the offline straight-line fallback produces a route with a
/// single generic step instead of fabricating maneuvers it has no data
/// for (see [RouteOption.offlineStraightLine]).
class NavStep {
  final String instruction;
  final IconData icon;
  final String? roadName;
  final double distanceMeters;
  final LatLng point;

  const NavStep({
    required this.instruction,
    required this.icon,
    required this.distanceMeters,
    required this.point,
    this.roadName,
  });
}

class RouteOption {
  final String id;
  final RouteRank rank;
  final List<LatLng> points;
  final double distanceMeters;
  final Duration duration;
  final List<NavStep> steps;

  /// True for the straight-line offline fallback — callers must not treat
  /// [steps] as real turn-by-turn guidance when this is true.
  final bool isOfflineEstimate;

  /// True when every available candidate route passed through a blocked
  /// (flooded) zone and this was picked only as the least-bad option — see
  /// `RoutingService.getRouteAvoidingBlocked`. UI should show this as a
  /// visible warning rather than presenting it as a clean evacuation path.
  final bool crossesBlockedZone;

  const RouteOption({
    required this.id,
    required this.rank,
    required this.points,
    required this.distanceMeters,
    required this.duration,
    required this.steps,
    this.isOfflineEstimate = false,
    this.crossesBlockedZone = false,
  });

  String get distanceLabel => formatDistance(distanceMeters);

  String get durationLabel => formatDuration(duration);

  DateTime get eta => DateTime.now().add(duration);
}
