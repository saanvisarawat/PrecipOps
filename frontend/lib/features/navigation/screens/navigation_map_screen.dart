import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/national_metros.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/connectivity_provider.dart';
import '../../../providers/service_providers.dart';
import '../../../services/location_service.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/map_pin_marker.dart';
import '../controllers/navigation_state.dart';
import '../models/nav_destination.dart';
import '../models/route_option.dart';
import '../providers/navigation_providers.dart';
import '../widgets/directions_sheet.dart';
import '../widgets/location_marker.dart';
import '../widgets/map_controls.dart';
import '../widgets/nav_bottom_bar.dart';
import '../widgets/navigation_instruction_card.dart';
import '../widgets/offline_indicator.dart';

/// The full-screen offline-capable navigation map — Apple-Maps-inspired:
/// floating glass controls instead of an AppBar, a persistent draggable
/// directions sheet, and a simplified active-navigation overlay once the
/// user taps GO. Pass [initialDestination] to jump straight into
/// directions (used by the shelter "Directions" button); leave it null
/// to open on free browse + search.
class NavigationMapScreen extends ConsumerStatefulWidget {
  final NavDestination? initialDestination;
  const NavigationMapScreen({super.key, this.initialDestination});

  @override
  ConsumerState<NavigationMapScreen> createState() => _NavigationMapScreenState();
}

class _NavigationMapScreenState extends ConsumerState<NavigationMapScreen> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  SmoothedPosition? _smoothedPosition;
  double _rotationDegrees = 0;
  bool _follow = true;
  LocationAvailability? _availability;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
    _mapController.mapEventStream.listen((event) {
      if (mounted) setState(() => _rotationDegrees = event.camera.rotation);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final destination = widget.initialDestination;
      if (destination != null) {
        ref.read(navigationControllerProvider.notifier).setDestination(destination);
      }
    });
  }

  Future<void> _checkAvailability() async {
    final availability = await ref.read(locationServiceProvider).checkAvailability();
    if (mounted) setState(() => _availability = availability);
  }

  @override
  void dispose() {
    _smoothedPosition?.dispose();
    super.dispose();
  }

  void _onPosition(Position position) {
    final latLng = LatLng(position.latitude, position.longitude);
    // GPS course-over-ground is only meaningful in motion — below ~1 m/s
    // it's noise, so the heading cone is left as-is rather than pointing
    // at a meaningless "0°" while stationary.
    final heading = position.speed > 1.0 ? position.heading : null;
    ref.read(navigationControllerProvider.notifier).onPositionUpdate(latLng, headingDegrees: heading);

    final smoothed = _smoothedPosition;
    if (smoothed == null) {
      _smoothedPosition = SmoothedPosition(vsync: this, initial: latLng);
      _mapController.move(latLng, 15.5);
    } else {
      smoothed.moveTo(latLng);
    }

    final nav = ref.read(navigationControllerProvider);
    if (_follow && (nav.phase == NavigationPhase.active)) {
      _mapController.moveAndRotate(latLng, _mapController.camera.zoom, -(position.heading));
    }
  }

  void _recenter() {
    final pos = _smoothedPosition?.value;
    setState(() => _follow = true);
    if (pos != null) _mapController.move(pos, 16.5);
  }

  void _resetRotation() => _mapController.rotate(0);

  void _go() {
    HapticFeedback.mediumImpact();
    ref.read(navigationControllerProvider.notifier).startNavigation();
    setState(() => _follow = true);
  }

  void _endRoute() {
    HapticFeedback.lightImpact();
    ref.read(navigationControllerProvider.notifier).endNavigation();
    setState(() => _follow = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_availability != null && _availability != LocationAvailability.available) {
      return _LocationBlockedView(availability: _availability!, onRetry: _checkAvailability);
    }

    ref.listen<AsyncValue<Position>>(positionStreamProvider, (previous, next) {
      next.whenData(_onPosition);
    });

    final nav = ref.watch(navigationControllerProvider);
    final isOnline = ref.watch(isOnlineProvider);
    final tileProvider = ref.watch(offlineTileProviderProvider);
    final smoothed = _smoothedPosition;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: smoothed ?? const _NullListenable(),
            builder: (context, _) {
              final position = smoothed?.value;
              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: widget.initialDestination?.point ?? position ?? NationalMetros.indiaMapCenter,
                  initialZoom: position != null ? 15.5 : NationalMetros.indiaMapDefaultZoom,
                  minZoom: 5,
                  maxZoom: 19,
                  onPositionChanged: (camera, hasGesture) {
                    if (hasGesture) _follow = false;
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.floodops.floodops_frontend',
                    tileProvider: tileProvider,
                  ),
                  for (final route in nav.routes) _routePolylineLayer(route, route.id == nav.selectedRouteId),
                  if (nav.destination != null)
                    MarkerLayer(markers: [
                      for (final stop in nav.stops)
                        Marker(
                          point: stop.point,
                          width: 34,
                          height: 34,
                          child: const MapPinMarker(icon: Icons.circle, color: AppColors.textSecondary, size: 22),
                        ),
                      Marker(
                        point: nav.destination!.point,
                        width: 40,
                        height: 40,
                        alignment: Alignment.bottomCenter,
                        child: const MapPinMarker(icon: Icons.flag_rounded, color: AppColors.dangerStrong),
                      ),
                    ]),
                  if (position != null)
                    CircleLayer(circles: [
                      CircleMarker(
                        point: position,
                        radius: 30,
                        useRadiusInMeter: true,
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderColor: AppColors.accent.withValues(alpha: 0.3),
                        borderStrokeWidth: 1,
                      ),
                    ]),
                  if (position != null)
                    MarkerLayer(markers: [
                      Marker(
                        point: position,
                        width: 44,
                        height: 44,
                        child: LocationPuck(headingDegrees: nav.headingDegrees),
                      ),
                    ]),
                ],
              );
            },
          ),

          if (!isOnline)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 0,
              right: 0,
              child: const Center(child: OfflineIndicator()),
            ),

          if (nav.phase != NavigationPhase.active)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: AppSpacing.md,
              child: MapControlButton(icon: Icons.arrow_back_rounded, onTap: () => context.pop(), size: 42),
            ),

          if (nav.phase != NavigationPhase.active)
            Positioned(
              right: AppSpacing.md,
              bottom: 240,
              child: Column(
                children: [
                  RotationCompassButton(rotationDegrees: _rotationDegrees, onTap: _resetRotation),
                  const SizedBox(height: AppSpacing.compact),
                  MapControlButton(icon: Icons.my_location_rounded, onTap: _recenter),
                  const SizedBox(height: AppSpacing.compact),
                  MapControlButton(icon: Icons.layers_outlined, onTap: () => context.push('/offline-maps')),
                ],
              ),
            ),

          if (nav.phase == NavigationPhase.active)
            _ActiveNavigationOverlay(nav: nav, onEndRoute: _endRoute)
          else
            DirectionsSheet(onGo: _go),
        ],
      ),
    );
  }

  Widget _routePolylineLayer(RouteOption route, bool selected) {
    final color = route.isOfflineEstimate
        ? AppColors.warning
        : switch (route.rank) {
            RouteRank.suggested => AppColors.accent,
            RouteRank.fastest => AppColors.accent,
            RouteRank.alternative => AppColors.textTertiary,
          };

    return PolylineLayer(polylines: [
      Polyline(
        points: route.points,
        strokeWidth: selected ? 6 : 4,
        color: selected ? color : color.withValues(alpha: 0.45),
        pattern: route.isOfflineEstimate ? StrokePattern.dashed(segments: const [12, 8]) : const StrokePattern.solid(),
        borderStrokeWidth: selected ? 1.5 : 0,
        borderColor: Colors.black.withValues(alpha: 0.25),
      ),
    ]);
  }
}

class _ActiveNavigationOverlay extends StatelessWidget {
  final NavigationState nav;
  final VoidCallback onEndRoute;

  const _ActiveNavigationOverlay({required this.nav, required this.onEndRoute});

  @override
  Widget build(BuildContext context) {
    final route = nav.selectedRoute;
    final progress = nav.progress;
    if (route == null) return const SizedBox.shrink();

    final stepIndex = progress?.currentStepIndex.clamp(0, route.steps.length - 1) ?? 0;
    final step = route.steps.isEmpty ? null : route.steps[stepIndex];

    return Stack(
      children: [
        if (step != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: NavigationInstructionCard(
              step: step,
              distanceToManeuverMeters: progress?.distanceToManeuverMeters ?? 0,
              isOfflineEstimate: route.isOfflineEstimate,
            ),
          ),
        Positioned(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: AppSpacing.md,
          child: NavBottomBar(
            remainingDuration: progress?.remainingDuration ?? route.duration,
            remainingDistanceMeters: progress?.remainingDistanceMeters ?? route.distanceMeters,
            onEndRoute: onEndRoute,
          ),
        ),
      ],
    );
  }
}

class _LocationBlockedView extends StatelessWidget {
  final LocationAvailability availability;
  final VoidCallback onRetry;

  const _LocationBlockedView({required this.availability, required this.onRetry});

  (IconData, String, String) get _content {
    switch (availability) {
      case LocationAvailability.servicesDisabled:
        return (Icons.location_disabled_rounded, 'Location services are off', 'Turn on Location Services in your device settings to use the offline map and navigation.');
      case LocationAvailability.permissionDeniedForever:
        return (Icons.lock_outline_rounded, 'Location permission required', 'Preciops needs location access to show your position and calculate routes. Enable it from the app\'s system settings.');
      case LocationAvailability.permissionDenied:
        return (Icons.my_location_rounded, 'Location permission required', 'Allow location access to see your position on the map and get directions.');
      case LocationAvailability.available:
        return (Icons.check_circle_outline, '', '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = _content;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Navigate')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.section),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: AppColors.textTertiary),
              const SizedBox(height: AppSpacing.md),
              Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.compact),
              Text(message, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.section),
              AppButton(label: 'Try Again', onPressed: onRetry, expand: false),
            ],
          ),
        ),
      ),
    );
  }
}

/// A no-op [Listenable] so [AnimatedBuilder] has something to attach to
/// before the first GPS fix arrives (and [SmoothedPosition] exists).
class _NullListenable extends Listenable {
  const _NullListenable();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
