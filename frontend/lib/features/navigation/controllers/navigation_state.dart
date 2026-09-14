import 'package:latlong2/latlong.dart';

import '../models/nav_destination.dart';
import '../models/route_option.dart';
import '../models/travel_mode.dart';
import '../services/route_progress.dart';

enum NavigationPhase { idle, pickingDestination, previewingRoutes, active }

class NavigationState {
  final NavigationPhase phase;
  final NavDestination? destination;
  final List<NavDestination> stops;
  final TravelMode mode;
  final List<RouteOption> routes;
  final String? selectedRouteId;
  final bool isCalculating;
  final String? error;
  final RouteProgress? progress;
  final LatLng? lastKnownPosition;
  final double? headingDegrees;

  const NavigationState({
    this.phase = NavigationPhase.idle,
    this.destination,
    this.stops = const [],
    this.mode = TravelMode.drive,
    this.routes = const [],
    this.selectedRouteId,
    this.isCalculating = false,
    this.error,
    this.progress,
    this.lastKnownPosition,
    this.headingDegrees,
  });

  RouteOption? get selectedRoute {
    if (routes.isEmpty) return null;
    return routes.firstWhere((r) => r.id == selectedRouteId, orElse: () => routes.first);
  }

  NavigationState copyWith({
    NavigationPhase? phase,
    NavDestination? destination,
    bool clearDestination = false,
    List<NavDestination>? stops,
    TravelMode? mode,
    List<RouteOption>? routes,
    String? selectedRouteId,
    bool? isCalculating,
    String? error,
    bool clearError = false,
    RouteProgress? progress,
    LatLng? lastKnownPosition,
    double? headingDegrees,
  }) {
    return NavigationState(
      phase: phase ?? this.phase,
      destination: clearDestination ? null : (destination ?? this.destination),
      stops: stops ?? this.stops,
      mode: mode ?? this.mode,
      routes: routes ?? this.routes,
      selectedRouteId: selectedRouteId ?? this.selectedRouteId,
      isCalculating: isCalculating ?? this.isCalculating,
      error: clearError ? null : (error ?? this.error),
      progress: progress ?? this.progress,
      lastKnownPosition: lastKnownPosition ?? this.lastKnownPosition,
      headingDegrees: headingDegrees ?? this.headingDegrees,
    );
  }
}
