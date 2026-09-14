import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../api/floodops_api.dart';
import '../../core/constants/kerala_districts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/risk_scenario.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';
import '../../providers/sos_provider.dart';
import '../../providers/stream_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/district_dropdown.dart';
import '../../widgets/map_pin_marker.dart';
import '../../widgets/section_header.dart';
import '../../widgets/sos_button.dart';
import '../../widgets/status_badge.dart';
import '../dashboard/widgets/sos_flow.dart';
import '../navigation/models/route_option.dart';
import '../navigation/models/travel_mode.dart';
import '../navigation/providers/navigation_providers.dart';

/// General Public / Field Volunteer Citizen Dashboard — simple, clean,
/// urgent. Backed by GET /api/v1/inundation/simulate,
/// GET /api/v1/routing/blocked-nodes and POST
/// /api/v1/citizen/verification/upload.
class CitizenDashboardScreen extends ConsumerStatefulWidget {
  const CitizenDashboardScreen({super.key});

  @override
  ConsumerState<CitizenDashboardScreen> createState() => _CitizenDashboardScreenState();
}

class _CitizenDashboardScreenState extends ConsumerState<CitizenDashboardScreen> {
  String _district = KeralaDistricts.defaultName;
  Position? _position;
  InundationSimulationResponse? _inundation;
  bool _loading = true;
  String? _error;

  RouteOption? _route;
  ShelterFeature? _targetShelter;
  bool _routing = false;

  /// QA/demo-only affordance — a real GPS fix landing inside a live
  /// inundation polygon is the real trigger, but that requires physically
  /// being there. Mirrors the existing "simulate" debug patterns already
  /// in this app (e.g. `simulateIncomingCall`).
  bool _simulateInsideZone = false;

  final _depthController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _submittingReport = false;

  // Citizen-side half of the SOS -> official -> volunteer pipeline: once
  // this citizen's own SOS is filed, its ticket is tracked here so the
  // dashboard can react the moment a volunteer is assigned and, once they
  // accept, poll their live position.
  String? _activeSosTicketId;
  String? _enRouteVolunteerName;
  LatLng? _volunteerLocation;
  Timer? _volunteerPollTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _depthController.dispose();
    _descriptionController.dispose();
    _volunteerPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final pos = await ref.read(locationServiceProvider).getCurrentPosition();
      if (mounted) {
        setState(() {
          _position = pos;
          _district = KeralaDistricts.nearest(pos.latitude, pos.longitude).name;
        });
      }
    } catch (_) {
      // No GPS fix — the dashboard still works with the manually-picked city.
    }
    await _load();
  }

  Future<void> _submitSos() async {
    final outcome = await submitSosViaComposer(context, ref);
    if (outcome == null || outcome.kind != SosOutcomeKind.submitted || !mounted) return;
    setState(() {
      _activeSosTicketId = outcome.ticketId;
      _enRouteVolunteerName = null;
      _volunteerLocation = null;
    });
    _volunteerPollTimer?.cancel();
  }

  void _startVolunteerLocationPolling() {
    _volunteerPollTimer?.cancel();
    _pollVolunteerLocation();
    _volunteerPollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollVolunteerLocation());
  }

  Future<void> _pollVolunteerLocation() async {
    final ticketId = _activeSosTicketId;
    if (ticketId == null) return;
    try {
      final api = ref.read(preciopsApiProvider);
      final snapshot = await api.getVolunteerLocationForTicket(ticketId);
      if (!mounted) return;
      if (snapshot != null) {
        setState(() => _volunteerLocation = LatLng(snapshot.latitude, snapshot.longitude));
      }
    } catch (_) {
      // Best-effort tracking — a failed poll just tries again next tick.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _route = null;
    });
    try {
      final api = ref.read(preciopsApiProvider);
      final scenario = await _resolveScenario(api);
      final result = await api.getInundationSimulation(district: _district, scenario: scenario);
      if (!mounted) return;
      setState(() {
        _inundation = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't reach the backend. Pull to retry.";
        _loading = false;
      });
    }
  }

  /// Picks the simulated scenario from this district's real PS-71 risk
  /// level instead of always requesting the worst case — falls back to
  /// EXTREME_EVENT (the safer over-warn default) if the live risk feed
  /// can't be reached.
  Future<String> _resolveScenario(PreciopsApi api) async {
    try {
      final d = KeralaDistricts.byName(_district);
      final risk = await api.predictKerala(lat: d.lat, lon: d.lon, district: d.name);
      return scenarioForRiskLevel(risk.riskLevel);
    } catch (_) {
      return 'EXTREME_EVENT';
    }
  }

  bool get _insideZone {
    if (_simulateInsideZone) return true;
    if (_position == null || _inundation == null || _inundation!.inundationZones.isEmpty) return false;
    final ring = _inundation!.inundationZones.first.polygonRing;
    return pointInPolygon(LatLng(_position!.latitude, _position!.longitude), ring);
  }

  Future<void> _routeToShelter() async {
    if (_inundation == null) return;
    setState(() => _routing = true);
    try {
      final api = ref.read(preciopsApiProvider);
      final shelters = (await api.getSheltersGeoJson()).features;
      if (shelters.isEmpty) throw Exception('No shelters available');

      final selected = KeralaDistricts.byName(_district);
      final origin = _position != null ? LatLng(_position!.latitude, _position!.longitude) : selected.center;

      const dist = Distance();
      shelters.sort((a, b) => dist
          .as(LengthUnit.Meter, origin, LatLng(a.latitude, a.longitude))
          .compareTo(dist.as(LengthUnit.Meter, origin, LatLng(b.latitude, b.longitude))));
      final shelter = shelters.first;

      bool Function(LatLng) isBlocked = (p) => false;
      if (_inundation!.inundationZones.isNotEmpty) {
        final blocked = await api.getBlockedNodes(zoneId: _inundation!.inundationZones.first.zoneId);
        isBlocked = (p) => blocked.blockedBoundingBoxes.any((b) => b.contains(p.latitude, p.longitude));
      }

      final routing = ref.read(routingServiceProvider);
      final route = await routing.getRouteAvoidingBlocked(
        waypoints: [origin, LatLng(shelter.latitude, shelter.longitude)],
        mode: TravelMode.drive,
        isBlocked: isBlocked,
      );
      if (!mounted) return;
      setState(() {
        _route = route;
        _targetShelter = shelter;
        _routing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _routing = false);
      AppToast.show(context, "Couldn't compute a route right now — try again.", kind: AppToastKind.error);
    }
  }

  Future<void> _submitGroundReport() async {
    final depth = double.tryParse(_depthController.text.trim());
    if (depth == null) {
      AppToast.show(context, 'Enter the observed water depth in meters.', kind: AppToastKind.error);
      return;
    }
    setState(() => _submittingReport = true);
    try {
      final api = ref.read(preciopsApiProvider);
      final lat = _position?.latitude ?? KeralaDistricts.byName(_district).center.latitude;
      final lng = _position?.longitude ?? KeralaDistricts.byName(_district).center.longitude;
      final result = await api.submitGroundTruth(
        district: _district,
        lat: lat,
        lng: lng,
        observedWaterDepthMeters: depth,
        description: _descriptionController.text.trim().isEmpty ? 'Citizen ground report' : _descriptionController.text.trim(),
      );
      if (!mounted) return;
      _depthController.clear();
      _descriptionController.clear();
      AppToast.show(context, result.message, kind: AppToastKind.success);
    } catch (_) {
      if (mounted) AppToast.show(context, "Couldn't submit the report — try again.", kind: AppToastKind.error);
    } finally {
      if (mounted) setState(() => _submittingReport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final evacuate = _insideZone;

    // A volunteer-assigned/en-route event only means something to whichever
    // citizen filed that exact ticket — every other citizen's dashboard is
    // also listening on this same shared stream, so both checks below are
    // filtered to `_activeSosTicketId` before reacting.
    ref.listen<AsyncValue<DashboardEvent>>(dashboardEventStreamProvider, (previous, next) {
      next.whenData((event) {
        if (event is VolunteerAssignedEvent && event.ticketId == _activeSosTicketId) {
          AppToast.show(
            context,
            event.assignedVolunteerName != null
                ? '${event.assignedVolunteerName} has been assigned to your SOS.'
                : 'A volunteer has been assigned to your SOS.',
            kind: AppToastKind.success,
          );
        } else if (event is VolunteerEnRouteEvent && event.ticketId == _activeSosTicketId) {
          final name = event.volunteerName ?? 'A volunteer';
          setState(() => _enRouteVolunteerName = name);
          AppToast.show(context, '$name is on the way!', kind: AppToastKind.success);
          _startVolunteerLocationPolling();
        }
      });
    });

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      backgroundColor: AppColors.surfaceHigh,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.4))
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.sm,
                    AppSpacing.screenPadding,
                    AppSpacing.xxl,
                  ),
                  children: [
                    Text('Hi, ${auth.user?.fullName ?? 'there'}', style: AppTypography.screenTitle()),
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: Column(
                        children: [
                          SosButton(onPressed: _submitSos, isBusy: ref.watch(sosControllerProvider)),
                          const SizedBox(height: 10),
                          Text('Hold to send an emergency SOS', style: AppTypography.caption(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    if (_enRouteVolunteerName != null) ...[
                      const SizedBox(height: AppSpacing.section),
                      _VolunteerEnRouteCard(
                        volunteerName: _enRouteVolunteerName!,
                        volunteerLocation: _volunteerLocation,
                        citizenPosition: _position,
                      ),
                    ],
                    if (evacuate) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _EvacuateBanner(onGetRoute: _routing ? null : _routeToShelter),
                    ],
                    const SizedBox(height: AppSpacing.section),
                    DistrictDropdown(
                      value: _district,
                      label: 'District',
                      onChanged: (v) {
                        setState(() => _district = v);
                        _load();
                      },
                    ),
                    const SectionHeader(title: 'Inundation Warning'),
                    _InundationWarningPanel(data: _inundation!),
                    const SectionHeader(title: 'Map'),
                    _CitizenMap(
                      data: _inundation!,
                      district: _district,
                      position: _position,
                      route: _route,
                      shelter: _targetShelter,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: _routing ? 'Finding a route…' : 'Route to Nearest Safe Shelter',
                      icon: Icons.alt_route_rounded,
                      isLoading: _routing,
                      onPressed: _routing ? null : _routeToShelter,
                    ),
                    const SectionHeader(title: 'Submit Ground Report'),
                    _GroundReportForm(
                      depthController: _depthController,
                      descriptionController: _descriptionController,
                      submitting: _submittingReport,
                      onSubmit: _submitGroundReport,
                    ),
                    if (_position == null) ...[
                      const SizedBox(height: AppSpacing.section),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: AppColors.accent,
                        title: Text('Simulate GPS inside flood zone (test)', style: AppTypography.caption()),
                        value: _simulateInsideZone,
                        onChanged: (v) => setState(() => _simulateInsideZone = v),
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.section),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.textTertiary),
        const SizedBox(height: 12),
        Text(message, style: AppTypography.body(color: AppColors.textSecondary), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        AppButton.secondary(label: 'Retry', onPressed: onRetry, expand: false),
      ],
    );
  }
}

/// Impossible-to-miss full-width warning — the moment a citizen's GPS
/// falls inside an active inundation polygon.
class _EvacuateBanner extends StatelessWidget {
  final VoidCallback? onGetRoute;
  const _EvacuateBanner({required this.onGetRoute});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.dangerStrong,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.dangerStrong.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 1)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_rounded, color: Colors.white, size: 28),
              SizedBox(width: 10),
              Text(
                'EVACUATE',
                style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Your location is inside an active flood zone. Move to higher ground immediately.',
            style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: AppButton.secondary(label: 'Get Evacuation Route Now', color: Colors.white, onPressed: onGetRoute),
          ),
        ],
      ),
    );
  }
}

/// Shown the moment a volunteer accepts this citizen's own SOS
/// ([VolunteerEnRouteEvent]) — a live-ish map tracking their reported
/// position (polled via `getVolunteerLocationForTicket`) alongside the
/// citizen's own, so "on the way" is something the citizen can actually
/// watch rather than just a one-time toast.
class _VolunteerEnRouteCard extends StatelessWidget {
  final String volunteerName;
  final LatLng? volunteerLocation;
  final Position? citizenPosition;

  const _VolunteerEnRouteCard({
    required this.volunteerName,
    required this.volunteerLocation,
    required this.citizenPosition,
  });

  @override
  Widget build(BuildContext context) {
    final citizenPoint = citizenPosition != null ? LatLng(citizenPosition!.latitude, citizenPosition!.longitude) : null;
    final center = volunteerLocation ?? citizenPoint ?? KeralaDistricts.defaultDistrict.center;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_run_rounded, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$volunteerName is on the way', style: AppTypography.cardTitle()),
              ),
              const StatusBadge(label: 'En Route', color: AppColors.accent, icon: Icons.circle, dot: true),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (volunteerLocation == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text('Locating volunteer…', style: AppTypography.body(color: AppColors.textSecondary)),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 180,
                child: FlutterMap(
                  options: MapOptions(initialCenter: center, initialZoom: 13, minZoom: 4, maxZoom: 17),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.floodops.preciops_frontend',
                    ),
                    if (citizenPoint != null && volunteerLocation != null)
                      PolylineLayer(polylines: [
                        Polyline(points: [volunteerLocation!, citizenPoint], strokeWidth: 3, color: AppColors.accent),
                      ]),
                    MarkerLayer(markers: [
                      if (citizenPoint != null)
                        Marker(
                          point: citizenPoint,
                          width: 30,
                          height: 30,
                          child: const MapPinMarker(icon: Icons.navigation_rounded, color: AppColors.info, size: 28, pulsing: true),
                        ),
                      if (volunteerLocation != null)
                        Marker(
                          point: volunteerLocation!,
                          width: 34,
                          height: 34,
                          child: const MapPinMarker(icon: Icons.directions_run_rounded, color: AppColors.accent, size: 30, pulsing: true),
                        ),
                    ]),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Replaces the old risk-score gauge everywhere it used to appear: water
/// depth, submerged landmarks, alert level + lead time — nothing else.
class _InundationWarningPanel extends StatelessWidget {
  final InundationSimulationResponse data;
  const _InundationWarningPanel({required this.data});

  @override
  Widget build(BuildContext context) {
    final zone = data.inundationZones.isNotEmpty ? data.inundationZones.first : null;
    final color = AppColors.alertLevelColor(data.alertLevel);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusBadge(label: '${data.alertLevel} ALERT — ${data.leadTimeWarning}', color: color, icon: Icons.campaign_outlined, filled: true),
          const SizedBox(height: 12),
          Text(
            zone != null ? 'Predicted Flood Depth: ${zone.avgWaterDepthMeters.toStringAsFixed(2)} meters' : 'No active inundation zone',
            style: AppTypography.cardTitle().copyWith(color: AppColors.depthColor(zone?.avgWaterDepthMeters ?? 0)),
          ),
          if (zone != null && zone.affectedLandmarks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Submerged Landmarks', style: AppTypography.label()),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final lm in zone.affectedLandmarks) StatusBadge(label: lm, color: color, icon: Icons.location_on_outlined)],
            ),
          ],
        ],
      ),
    );
  }
}

class _CitizenMap extends StatelessWidget {
  final InundationSimulationResponse data;
  final String district;
  final Position? position;
  final RouteOption? route;
  final ShelterFeature? shelter;

  const _CitizenMap({required this.data, required this.district, required this.position, required this.route, required this.shelter});

  @override
  Widget build(BuildContext context) {
    final dist = KeralaDistricts.byName(district);
    final zone = data.inundationZones.isNotEmpty ? data.inundationZones.first : null;
    final ring = zone?.polygonRing ?? const <LatLng>[];
    final depthColor = AppColors.depthColor(zone?.avgWaterDepthMeters ?? 0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 280,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: position != null ? LatLng(position!.latitude, position!.longitude) : dist.center,
            initialZoom: 13,
            minZoom: 4,
            maxZoom: 17,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.floodops.preciops_frontend',
            ),
            if (ring.length >= 3)
              PolygonLayer(polygons: [
                Polygon(points: ring, color: depthColor.withValues(alpha: 0.38), borderColor: depthColor, borderStrokeWidth: 2),
              ]),
            if (route != null)
              PolylineLayer(polylines: [
                Polyline(points: route!.points, strokeWidth: 4, color: AppColors.info),
              ]),
            MarkerLayer(markers: [
              if (position != null)
                Marker(
                  point: LatLng(position!.latitude, position!.longitude),
                  width: 30,
                  height: 30,
                  child: const MapPinMarker(icon: Icons.navigation_rounded, color: AppColors.info, size: 28, pulsing: true),
                ),
              if (shelter != null)
                Marker(
                  point: LatLng(shelter!.latitude, shelter!.longitude),
                  width: 34,
                  height: 34,
                  child: const MapPinMarker(icon: Icons.home_work_rounded, color: AppColors.accent, size: 30),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _GroundReportForm extends StatelessWidget {
  final TextEditingController depthController;
  final TextEditingController descriptionController;
  final bool submitting;
  final VoidCallback onSubmit;

  const _GroundReportForm({
    required this.depthController,
    required this.descriptionController,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Help verify the model — report what you actually see.', style: AppTypography.caption()),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: depthController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTypography.body(),
            decoration: const InputDecoration(labelText: 'Observed water level (meters)'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: descriptionController,
            maxLines: 2,
            style: AppTypography.body(),
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(label: 'Submit Ground Report', icon: Icons.upload_rounded, isLoading: submitting, onPressed: submitting ? null : onSubmit),
        ],
      ),
    );
  }
}
