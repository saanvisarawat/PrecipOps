import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:latlong2/latlong.dart';

import '../models/route_option.dart';
import '../models/travel_mode.dart';
import 'dijkstra.dart';
import 'osrm_maneuver.dart';

class TravelModeUnavailableException implements Exception {
  final TravelMode mode;
  const TravelModeUnavailableException(this.mode);
}

class RouteCalculationException implements Exception {
  final String message;
  const RouteCalculationException(this.message);
}

/// Origin, ordered stops, then destination is the last waypoint. A plain
/// point-to-point route is just two waypoints.
///
/// [avoidHighways] is part of the contract for a future backend that
/// supports OSRM's `exclude` classes, but isn't surfaced as a UI toggle
/// yet: the public routing.openstreetmap.de mirrors this app currently
/// calls reject `exclude=motorway`/`exclude=toll` outright (verified —
/// they return `InvalidValue`/400), so exposing the control would be a
/// toggle that visibly does nothing. A self-hosted OSRM/backend with
/// excludable classes configured can wire this up with no interface
/// change.
abstract class RoutingService {
  Future<List<RouteOption>> getRoutes({
    required List<LatLng> waypoints,
    required TravelMode mode,
    bool avoidHighways = false,
  });

  /// Evacuation routing that steers around flooded streets. Backed by
  /// GET /api/v1/routing/blocked-nodes: the caller resolves the zone's
  /// bounding boxes into an [isBlocked] predicate (`node.lat/lon` inside
  /// any box), and this asks OSRM for every alternative it has, then picks
  /// the shortest one whose polyline never enters a blocked box — the same
  /// "mark blocked, then run Dijkstra" idea the backend spec describes,
  /// applied to this app's actual routing graph (OSRM's candidate routes,
  /// not raw street-intersection nodes, since there is no local street
  /// graph to walk). Falls back to the least-blocked candidate (flagged via
  /// [RouteOption.crossesBlockedZone]) if every alternative crosses one.
  Future<RouteOption> getRouteAvoidingBlocked({
    required List<LatLng> waypoints,
    required TravelMode mode,
    required bool Function(LatLng point) isBlocked,
  });
}

/// Real turn-by-turn routing against the public OSRM mirrors hosted at
/// routing.openstreetmap.de (routed-car / routed-foot / routed-bike). This
/// is a free community demo instance, not an SLA-backed service — fine
/// for development and small deployments, but a production rollout should
/// point [_baseUrl] at a self-hosted OSRM/backend instance instead (the
/// interface here doesn't change either way).
class OsrmRoutingService implements RoutingService {
  OsrmRoutingService({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));

  final Dio _dio;
  static const _baseUrl = 'https://routing.openstreetmap.de';

  @override
  Future<List<RouteOption>> getRoutes({
    required List<LatLng> waypoints,
    required TravelMode mode,
    bool avoidHighways = false,
  }) async {
    if (!mode.isAvailable) throw TravelModeUnavailableException(mode);
    if (waypoints.length < 2) throw const RouteCalculationException('Need an origin and a destination.');

    final coords = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
    final url = '$_baseUrl/routed-${_subdomain(mode)}/route/v1/${mode.osrmProfile}/$coords';

    try {
      final response = await _dio.get(url, queryParameters: {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'true',
        'alternatives': mode == TravelMode.drive ? 'true' : 'false',
      });

      final data = response.data as Map<String, dynamic>;
      if (data['code'] != 'Ok') {
        throw RouteCalculationException(data['message'] as String? ?? 'No route found.');
      }

      final routes = (data['routes'] as List).cast<Map<String, dynamic>>();
      final options = routes.map((r) => _toRouteOption(r)).toList();
      return [_shortest(options)];
    } on DioException catch (e) {
      throw RouteCalculationException(e.message ?? 'Routing service unreachable.');
    }
  }

  @override
  Future<RouteOption> getRouteAvoidingBlocked({
    required List<LatLng> waypoints,
    required TravelMode mode,
    required bool Function(LatLng point) isBlocked,
  }) async {
    if (!mode.isAvailable) throw TravelModeUnavailableException(mode);
    if (waypoints.length < 2) throw const RouteCalculationException('Need an origin and a destination.');

    final coords = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
    final url = '$_baseUrl/routed-${_subdomain(mode)}/route/v1/${mode.osrmProfile}/$coords';

    try {
      final response = await _dio.get(url, queryParameters: {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'true',
        'alternatives': 'true',
      });

      final data = response.data as Map<String, dynamic>;
      if (data['code'] != 'Ok') {
        throw RouteCalculationException(data['message'] as String? ?? 'No route found.');
      }

      final routes = (data['routes'] as List).cast<Map<String, dynamic>>();
      final options = routes.map((r) => _toRouteOption(r)).toList();
      return _shortestAvoidingBlocked(options, isBlocked);
    } on DioException catch (e) {
      throw RouteCalculationException(e.message ?? 'Routing service unreachable.');
    }
  }

  /// Same start/end Dijkstra graph `_shortest` already builds to pick among
  /// OSRM's candidates — except a candidate whose polyline enters a
  /// blocked box gets an infinite edge weight instead of half its real
  /// distance, so the shortest path through this graph is, by construction,
  /// the shortest candidate that never touches flooded ground. If every
  /// candidate is blocked, the least-blocked one is returned instead of
  /// throwing, flagged via [RouteOption.crossesBlockedZone].
  RouteOption _shortestAvoidingBlocked(List<RouteOption> options, bool Function(LatLng) isBlocked) {
    final blockedFlags = <String, bool>{};
    final graph = Dijkstra();
    for (final o in options) {
      final blocked = o.points.any(isBlocked);
      blockedFlags[o.id] = blocked;
      final weight = blocked ? double.infinity : o.distanceMeters / 2;
      graph.addEdge('start', o.id, weight);
      graph.addEdge(o.id, 'end', weight);
    }
    final result = graph.shortestPath('start', 'end');

    String chosenId;
    if (result != null && result.path.length >= 2 && result.distance.isFinite) {
      chosenId = result.path[1];
    } else {
      // Every candidate crosses a blocked box — fall back to whichever
      // intersects the fewest points, and flag it below.
      final sorted = [...options]..sort(
          (a, b) => a.points.where(isBlocked).length.compareTo(b.points.where(isBlocked).length));
      chosenId = sorted.first.id;
    }

    final chosen = options.firstWhere((o) => o.id == chosenId, orElse: () => options.first);
    return RouteOption(
      id: chosen.id,
      rank: RouteRank.suggested,
      points: chosen.points,
      distanceMeters: chosen.distanceMeters,
      duration: chosen.duration,
      steps: chosen.steps,
      isOfflineEstimate: chosen.isOfflineEstimate,
      crossesBlockedZone: blockedFlags[chosen.id] ?? false,
    );
  }

  String _subdomain(TravelMode mode) {
    switch (mode) {
      case TravelMode.drive:
        return 'car';
      case TravelMode.walk:
        return 'foot';
      case TravelMode.cycle:
        return 'bike';
      case TravelMode.transit:
        throw TravelModeUnavailableException(mode);
    }
  }

  RouteOption _toRouteOption(Map<String, dynamic> route) {
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coordinates = (geometry['coordinates'] as List)
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();

    final steps = <NavStep>[];
    for (final leg in (route['legs'] as List).cast<Map<String, dynamic>>()) {
      for (final step in (leg['steps'] as List).cast<Map<String, dynamic>>()) {
        final maneuver = step['maneuver'] as Map<String, dynamic>;
        final location = maneuver['location'] as List;
        final roadName = step['name'] as String?;
        final rendered = OsrmManeuver.from(
          type: maneuver['type'] as String,
          modifier: maneuver['modifier'] as String?,
          roadName: roadName,
        );
        steps.add(NavStep(
          instruction: rendered.instruction,
          icon: rendered.icon,
          roadName: roadName?.isNotEmpty == true ? roadName : null,
          distanceMeters: (step['distance'] as num).toDouble(),
          point: LatLng((location[1] as num).toDouble(), (location[0] as num).toDouble()),
        ));
      }
    }

    return RouteOption(
      id: 'osrm-${coordinates.hashCode}',
      rank: RouteRank.suggested,
      points: coordinates,
      distanceMeters: (route['distance'] as num).toDouble(),
      duration: Duration(seconds: (route['duration'] as num).round()),
      steps: steps,
    );
  }

  /// OSRM's `alternatives=true` (drive mode only) can return several
  /// candidate routes — only the shortest-distance one is ever surfaced to
  /// the user, so there's no longer-route picker to show. Picked via a real
  /// Dijkstra shortest-path search over a tiny graph (shared start/end node
  /// plus one hub node per candidate, edge weight = that route's total
  /// distance) rather than a plain min() scan.
  RouteOption _shortest(List<RouteOption> options) {
    final graph = Dijkstra();
    for (final o in options) {
      final half = o.distanceMeters / 2;
      graph.addEdge('start', o.id, half);
      graph.addEdge(o.id, 'end', half);
    }
    final result = graph.shortestPath('start', 'end');
    // Falls back to the first option only if graph construction somehow
    // yields no path (never happens with >=1 candidate, but keeps this
    // total instead of throwing).
    final chosenId = result != null && result.path.length >= 2 ? result.path[1] : options.first.id;
    final shortest = options.firstWhere((o) => o.id == chosenId, orElse: () => options.first);

    return RouteOption(
      id: shortest.id,
      rank: RouteRank.suggested,
      points: shortest.points,
      distanceMeters: shortest.distanceMeters,
      duration: shortest.duration,
      steps: shortest.steps,
      isOfflineEstimate: shortest.isOfflineEstimate,
    );
  }
}

/// Offline fallback: a great-circle "as the crow flies" line with a
/// distance/ETA estimate. This is NOT turn-by-turn routing and never
/// claims to be — [RouteOption.isOfflineEstimate] is always true so the UI
/// can label it honestly. Full offline turn-by-turn needs a bundled
/// routing engine and preprocessed road graph; see the navigation module
/// README note in [OfflineMapService].
class StraightLineRoutingService implements RoutingService {
  static const _distance = Distance();

  @override
  Future<List<RouteOption>> getRoutes({
    required List<LatLng> waypoints,
    required TravelMode mode,
    bool avoidHighways = false,
  }) async {
    if (waypoints.length < 2) throw const RouteCalculationException('Need an origin and a destination.');
    if (!mode.isAvailable) throw TravelModeUnavailableException(mode);

    double totalMeters = 0;
    for (var i = 0; i < waypoints.length - 1; i++) {
      totalMeters += _distance.as(LengthUnit.Meter, waypoints[i], waypoints[i + 1]);
    }
    final seconds = totalMeters / mode.offlineAverageSpeedMps;

    return [
      RouteOption(
        id: 'offline-straight-line',
        rank: RouteRank.suggested,
        points: waypoints,
        distanceMeters: totalMeters,
        duration: Duration(seconds: seconds.round()),
        isOfflineEstimate: true,
        steps: [
          NavStep(
            instruction: 'Head toward your destination (offline: straight-line guidance only)',
            icon: Icons.explore_outlined,
            distanceMeters: totalMeters,
            point: waypoints.last,
          ),
        ],
      ),
    ];
  }

  @override
  Future<RouteOption> getRouteAvoidingBlocked({
    required List<LatLng> waypoints,
    required TravelMode mode,
    required bool Function(LatLng point) isBlocked,
  }) async {
    final route = (await getRoutes(waypoints: waypoints, mode: mode)).first;
    return RouteOption(
      id: route.id,
      rank: route.rank,
      points: route.points,
      distanceMeters: route.distanceMeters,
      duration: route.duration,
      steps: route.steps,
      isOfflineEstimate: true,
      crossesBlockedZone: route.points.any(isBlocked),
    );
  }
}

/// Picks OSRM when online, falls back to the straight-line estimate when
/// offline or when OSRM fails/times out — satisfies "online uses real
/// routing, offline degrades gracefully" without the UI needing to know
/// which path served a given [RouteOption].
class HybridRoutingService implements RoutingService {
  HybridRoutingService({required this.isOnline, OsrmRoutingService? online, StraightLineRoutingService? offline})
      : _online = online ?? OsrmRoutingService(),
        _offline = offline ?? StraightLineRoutingService();

  final bool Function() isOnline;
  final OsrmRoutingService _online;
  final StraightLineRoutingService _offline;

  @override
  Future<List<RouteOption>> getRoutes({
    required List<LatLng> waypoints,
    required TravelMode mode,
    bool avoidHighways = false,
  }) async {
    if (!mode.isAvailable) throw TravelModeUnavailableException(mode);
    if (!isOnline()) return _offline.getRoutes(waypoints: waypoints, mode: mode);

    try {
      return await _online.getRoutes(waypoints: waypoints, mode: mode, avoidHighways: avoidHighways);
    } catch (_) {
      return _offline.getRoutes(waypoints: waypoints, mode: mode);
    }
  }

  @override
  Future<RouteOption> getRouteAvoidingBlocked({
    required List<LatLng> waypoints,
    required TravelMode mode,
    required bool Function(LatLng point) isBlocked,
  }) async {
    if (!mode.isAvailable) throw TravelModeUnavailableException(mode);
    if (!isOnline()) return _offline.getRouteAvoidingBlocked(waypoints: waypoints, mode: mode, isBlocked: isBlocked);
    try {
      return await _online.getRouteAvoidingBlocked(waypoints: waypoints, mode: mode, isBlocked: isBlocked);
    } catch (_) {
      return _offline.getRouteAvoidingBlocked(waypoints: waypoints, mode: mode, isBlocked: isBlocked);
    }
  }
}
