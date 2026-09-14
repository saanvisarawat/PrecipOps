import 'package:flutter/material.dart';

/// OSRM profile backing each mode — routing.openstreetmap.de hosts
/// separate car/bike/foot instances; there is no public transit router,
/// so [transit] has no [osrmProfile] and is surfaced as unavailable
/// rather than faked (see [RoutingService]).
enum TravelMode {
  drive('driving', Icons.directions_car_rounded, 'Car'),
  walk('foot', Icons.directions_walk_rounded, 'Walking'),
  cycle('bike', Icons.directions_bike_rounded, 'Cycling'),
  transit(null, Icons.directions_transit_rounded, 'Transit');

  final String? osrmProfile;
  final IconData icon;
  final String label;

  const TravelMode(this.osrmProfile, this.icon, this.label);

  bool get isAvailable => osrmProfile != null;

  /// Average free-flow speed used only for the offline straight-line
  /// fallback estimate, in meters/second.
  double get offlineAverageSpeedMps {
    switch (this) {
      case TravelMode.drive:
        return 40 * 1000 / 3600;
      case TravelMode.walk:
        return 4.5 * 1000 / 3600;
      case TravelMode.cycle:
        return 15 * 1000 / 3600;
      case TravelMode.transit:
        return 20 * 1000 / 3600;
    }
  }
}
