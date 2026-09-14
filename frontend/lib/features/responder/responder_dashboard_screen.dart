import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../api/models/inundation_models.dart';
import '../../api/models/shelter_models.dart';
import '../../core/constants/kerala_districts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/district_dropdown.dart';
import '../../widgets/map_pin_marker.dart';
import '../../widgets/section_header.dart';
import '../../widgets/status_badge.dart';
import '../navigation/models/route_option.dart';
import '../navigation/models/travel_mode.dart';
import '../navigation/providers/navigation_providers.dart';

/// District Magistrate / NDMA / NDRF Responder Dashboard — tactical,
/// action-oriented. No raw telemetry, only what's needed to act.
class ResponderDashboardScreen extends ConsumerStatefulWidget {
  const ResponderDashboardScreen({super.key});

  @override
  ConsumerState<ResponderDashboardScreen> createState() => _ResponderDashboardScreenState();
}

class _ResponderDashboardScreenState extends ConsumerState<ResponderDashboardScreen> {
  String _district = KeralaDistricts.defaultName;
  bool _loading = true;
  String? _error;

  InundationSimulationResponse? _inundation;
  NdmaProtocolResponse? _protocol;
  StormComparisonResponse? _storm;
  RouteOption? _route;
  ShelterFeature? _targetShelter;
  final Set<String> _checkedItems = {};
  bool _broadcasting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _checkedItems.clear();
      _route = null;
    });
    final api = ref.read(preciopsApiProvider);
    try {
      final inundation = await api.getInundationSimulation(district: _district, scenario: 'EXTREME_EVENT');
      final protocol = await api.getNdmaProtocol(
        district: _district,
        alertLevel: inundation.alertLevel,
        radarDbz: inundation.telemetry.radarReflectivityDbz,
        satelliteTempK: inundation.telemetry.cloudTopTempKelvin,
      );
      final storm = await api.getStormComparison(district: _district);

      if (!mounted) return;
      setState(() {
        _inundation = inundation;
        _protocol = protocol;
        _storm = storm;
        _loading = false;
      });

      if (inundation.inundationZones.isNotEmpty) {
        await _computeRoute(inundation.inundationZones.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't reach the backend. Pull to retry.";
        _loading = false;
      });
    }
  }

  Future<void> _computeRoute(InundationPolygon zone) async {
    try {
      final api = ref.read(preciopsApiProvider);
      final blocked = await api.getBlockedNodes(zoneId: zone.zoneId);
      final shelters = (await api.getSheltersGeoJson()).features;
      if (shelters.isEmpty) return;

      final ring = zone.polygonRing;
      final zoneCenterLat = ring.map((p) => p.latitude).reduce((a, b) => a + b) / ring.length;
      final zoneCenterLng = ring.map((p) => p.longitude).reduce((a, b) => a + b) / ring.length;
      const dist = Distance();
      final origin = LatLng(zoneCenterLat, zoneCenterLng);

      shelters.sort((a, b) => dist
          .as(LengthUnit.Meter, origin, LatLng(a.latitude, a.longitude))
          .compareTo(dist.as(LengthUnit.Meter, origin, LatLng(b.latitude, b.longitude))));
      final shelter = shelters.first;

      bool isBlocked(LatLng p) => blocked.blockedBoundingBoxes.any((b) => b.contains(p.latitude, p.longitude));

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
      });
    } catch (_) {
      // Routing is a bonus overlay on the tactical map — a failure here
      // (OSRM mirror down, no shelter data) shouldn't block the rest of
      // the dashboard from working.
    }
  }

  Future<void> _broadcast() async {
    if (_inundation == null) return;
    setState(() => _broadcasting = true);
    try {
      final api = ref.read(preciopsApiProvider);
      final zoneId = _inundation!.inundationZones.isNotEmpty ? _inundation!.inundationZones.first.zoneId : 'INUND-$_district';
      final result = await api.broadcastEmergencySms(
        district: _district,
        zoneId: zoneId,
        alertMessage: _inundation!.advisoryBulletin,
      );
      if (mounted) {
        AppToast.show(
          context,
          '${result.simulatedSmsRecipientsCount} offline SMS warnings queued for cellular fallback.',
          kind: AppToastKind.success,
        );
      }
    } catch (_) {
      if (mounted) AppToast.show(context, "Couldn't send the broadcast — try again.", kind: AppToastKind.error);
    } finally {
      if (mounted) setState(() => _broadcasting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Responder Dashboard'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'sos-dashboard') context.push('/sos-dashboard');
              if (v == 'volunteer-hub') context.push('/volunteer-hub');
              if (v == 'logout') ref.read(authProvider.notifier).logout();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'sos-dashboard', child: Text('SOS Ticket Queue')),
              const PopupMenuItem(value: 'volunteer-hub', child: Text('Volunteer Coordination')),
              const PopupMenuItem(value: 'logout', child: Text('Sign Out')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
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
                        Text('Welcome, ${auth.user?.fullName ?? 'Responder'}', style: AppTypography.label()),
                        const SizedBox(height: 4),
                        DistrictDropdown(
                          value: _district,
                          label: 'District',
                          onChanged: (v) {
                            setState(() => _district = v);
                            _load();
                          },
                        ),
                        const SectionHeader(title: 'IMD Advisory'),
                        _AdvisoryCard(inundation: _inundation!, protocol: _protocol!),
                        const SectionHeader(title: 'Tactical Map'),
                        _TacticalMap(
                          zone: _inundation!.inundationZones.isNotEmpty ? _inundation!.inundationZones.first : null,
                          route: _route,
                          shelter: _targetShelter,
                          district: _district,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        AppButton(
                          label: _broadcasting ? 'Broadcasting…' : 'Broadcast Emergency SMS',
                          icon: Icons.sms_outlined,
                          color: AppColors.dangerStrong,
                          isLoading: _broadcasting,
                          onPressed: _broadcasting ? null : _broadcast,
                        ),
                        const SectionHeader(title: 'NDMA Protocol Checklist'),
                        _ProtocolChecklist(
                          protocol: _protocol!,
                          checked: _checkedItems,
                          onToggle: (item) => setState(
                            () => _checkedItems.contains(item) ? _checkedItems.remove(item) : _checkedItems.add(item),
                          ),
                        ),
                        const SectionHeader(title: 'Comparative Storm Analytics'),
                        _StormChart(storm: _storm!),
                      ],
                    ),
        ),
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

class _AdvisoryCard extends StatelessWidget {
  final InundationSimulationResponse inundation;
  final NdmaProtocolResponse protocol;
  const _AdvisoryCard({required this.inundation, required this.protocol});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.alertLevelColor(inundation.alertLevel);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(label: '${inundation.alertLevel} ALERT', color: color, icon: Icons.campaign_outlined, filled: true),
              const SizedBox(width: 8),
              Expanded(child: Text(inundation.leadTimeWarning, style: AppTypography.label())),
            ],
          ),
          const SizedBox(height: 10),
          Text(protocol.evacuationPriority, style: AppTypography.cardTitle().copyWith(color: color)),
          const SizedBox(height: 4),
          Text(protocol.meteorologicalTriggerSummary, style: AppTypography.body(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _TacticalMap extends StatelessWidget {
  final InundationPolygon? zone;
  final RouteOption? route;
  final ShelterFeature? shelter;
  final String district;

  const _TacticalMap({required this.zone, required this.route, required this.shelter, required this.district});

  @override
  Widget build(BuildContext context) {
    final dist = KeralaDistricts.byName(district);
    final ring = zone?.polygonRing ?? const <LatLng>[];
    final depthColor = AppColors.depthColor(zone?.avgWaterDepthMeters ?? 0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 340,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(initialCenter: dist.center, initialZoom: 12.5, minZoom: 4, maxZoom: 17),
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
                    Polyline(
                      points: route!.points,
                      strokeWidth: 4,
                      color: route!.crossesBlockedZone ? AppColors.warning : AppColors.info,
                    ),
                  ]),
                if (shelter != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(shelter!.latitude, shelter!.longitude),
                      width: 36,
                      height: 36,
                      child: const MapPinMarker(icon: Icons.home_work_rounded, color: AppColors.accent, size: 32),
                    ),
                  ]),
              ],
            ),
            Positioned(
              left: 12,
              top: 12,
              child: StatusBadge(
                label: zone != null ? 'Zone ${zone!.zoneId} · ${zone!.avgWaterDepthMeters.toStringAsFixed(2)}m' : 'No active zone',
                color: depthColor,
                icon: Icons.water_rounded,
                filled: true,
              ),
            ),
            if (route != null)
              Positioned(
                right: 12,
                bottom: 12,
                child: StatusBadge(
                  label: route!.crossesBlockedZone ? 'Route crosses flooding' : 'Route avoids flooded zone',
                  color: route!.crossesBlockedZone ? AppColors.warning : AppColors.info,
                  icon: Icons.alt_route_rounded,
                  filled: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProtocolChecklist extends StatelessWidget {
  final NdmaProtocolResponse protocol;
  final Set<String> checked;
  final ValueChanged<String> onToggle;

  const _ProtocolChecklist({required this.protocol, required this.checked, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(protocol.ragKnowledgeSource, style: AppTypography.caption(), maxLines: 2)),
                Text('${checked.length}/${protocol.actionableChecklist.length}', style: AppTypography.label(color: AppColors.accent)),
              ],
            ),
          ),
          for (final item in protocol.actionableChecklist)
            InkWell(
              onTap: () => onToggle(item),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      checked.contains(item) ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                      color: checked.contains(item) ? AppColors.accent : AppColors.textTertiary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item,
                        style: AppTypography.body(
                          color: checked.contains(item) ? AppColors.textTertiary : AppColors.textPrimary,
                        ).copyWith(
                          decoration: checked.contains(item) ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

class _StormChart extends StatelessWidget {
  final StormComparisonResponse storm;
  const _StormChart({required this.storm});

  static const _palette = [AppColors.dangerStrong, AppColors.info, AppColors.warning];

  @override
  Widget build(BuildContext context) {
    final series = <(String, List<double>, Color)>[
      (storm.currentStormName, storm.currentHourlyTrend, _palette[0]),
      for (var i = 0; i < storm.historicalBenchmarks.length; i++)
        (
          '${storm.historicalBenchmarks[i].eventName} (${storm.historicalBenchmarks[i].year})',
          storm.historicalBenchmarks[i].hourlyTrend,
          _palette[(i + 1) % _palette.length],
        ),
    ];
    final maxY = series.expand((s) => s.$2).fold<double>(0, (a, b) => a > b ? a : b);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY * 1.15,
                gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxY / 4),
                titlesData: const FlTitlesData(
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  for (final s in series)
                    LineChartBarData(
                      spots: [for (var i = 0; i < s.$2.length; i++) FlSpot(i.toDouble(), s.$2[i])],
                      isCurved: true,
                      color: s.$3,
                      barWidth: 2.5,
                      dotData: const FlDotData(show: false),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final s in series)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(s.$1, style: AppTypography.caption()),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
