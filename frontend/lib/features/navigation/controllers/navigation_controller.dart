import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/nav_destination.dart';
import '../models/route_option.dart';
import '../models/travel_mode.dart';
import '../services/route_progress.dart';
import '../services/routing_service.dart';
import 'navigation_state.dart';

/// Owns the destination/mode/route-options/active-navigation state for the
/// navigation screen. Position updates are pushed in from outside
/// (the screen forwards its [positionStreamProvider] listener here)
/// rather than the controller subscribing itself, so it stays easy to
/// test without a real GPS stream.
class NavigationController extends StateNotifier<NavigationState> {
  NavigationController(this._routingService) : super(const NavigationState());

  final RoutingService _routingService;

  void setDestination(NavDestination destination) {
    state = state.copyWith(
      phase: NavigationPhase.previewingRoutes,
      destination: destination,
      stops: const [],
      routes: const [],
      selectedRouteId: null,
      clearError: true,
    );
    _recalculate();
  }

  void clearDestination() {
    state = const NavigationState();
  }

  void addStop(NavDestination stop) {
    state = state.copyWith(stops: [...state.stops, stop]);
    _recalculate();
  }

  void removeStop(int index) {
    final stops = [...state.stops]..removeAt(index);
    state = state.copyWith(stops: stops);
    _recalculate();
  }

  void setMode(TravelMode mode) {
    if (!mode.isAvailable) return;
    state = state.copyWith(mode: mode, clearError: true);
    _recalculate();
  }

  void selectRoute(String routeId) {
    state = state.copyWith(selectedRouteId: routeId);
  }

  Future<void> _recalculate() async {
    final destination = state.destination;
    final origin = state.lastKnownPosition;
    if (destination == null || origin == null) return;

    state = state.copyWith(isCalculating: true, clearError: true);
    try {
      final waypoints = [origin, ...state.stops.map((s) => s.point), destination.point];
      final routes = await _routingService.getRoutes(waypoints: waypoints, mode: state.mode);
      state = state.copyWith(
        routes: routes,
        selectedRouteId: routes.isNotEmpty ? routes.first.id : null,
        isCalculating: false,
      );
    } on TravelModeUnavailableException {
      state = state.copyWith(isCalculating: false, routes: const [], error: '${state.mode.label} isn\'t available in this region yet.');
    } on RouteCalculationException catch (e) {
      state = state.copyWith(isCalculating: false, routes: const [], error: e.message);
    } catch (_) {
      state = state.copyWith(isCalculating: false, routes: const [], error: 'Unable to calculate a route right now.');
    }
  }

  void startNavigation() {
    if (state.selectedRoute == null) return;
    state = state.copyWith(phase: NavigationPhase.active);
  }

  void endNavigation() {
    state = const NavigationState();
  }

  /// Called by the screen on every GPS fix. Recomputes on-route progress
  /// while actively navigating, and just tracks the live position
  /// otherwise (used to recenter the map and to seed [_recalculate]'s
  /// origin once a destination is picked).
  void onPositionUpdate(LatLng position, {double? headingDegrees}) {
    final hadNoOrigin = state.lastKnownPosition == null;
    state = state.copyWith(lastKnownPosition: position, headingDegrees: headingDegrees ?? state.headingDegrees);

    final selected = state.selectedRoute;
    if (state.phase == NavigationPhase.active && selected != null) {
      final progress = RouteProgress.compute(selected, position);
      state = state.copyWith(progress: progress);
      return;
    }

    // A destination was picked before the first GPS fix arrived (e.g. the
    // "Directions" button on a shelter, tapped before a fix settles) —
    // now that an origin exists, run the calculation that was skipped.
    if (hadNoOrigin && state.destination != null && state.routes.isEmpty && !state.isCalculating) {
      _recalculate();
    }
  }

  RouteOption? routeById(String id) {
    for (final r in state.routes) {
      if (r.id == id) return r;
    }
    return null;
  }
}
