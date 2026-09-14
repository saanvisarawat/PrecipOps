import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../api/models/inundation_models.dart';
import '../../core/constants/national_metros.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_slider.dart';
import '../../widgets/district_dropdown.dart';
import '../../widgets/map_pin_marker.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/status_badge.dart';

/// IMD Meteorologist / MoES Predictor Dashboard — PS 26071's heavy-
/// telemetry, technical view. Backed entirely by
/// GET /api/v1/inundation/simulate.
class PredictorDashboardScreen extends ConsumerStatefulWidget {
  const PredictorDashboardScreen({super.key});

  @override
  ConsumerState<PredictorDashboardScreen> createState() => _PredictorDashboardScreenState();
}

class _PredictorDashboardScreenState extends ConsumerState<PredictorDashboardScreen> {
  String _district = NationalMetros.all.first.name;
  String _scenario = 'EXTREME_EVENT';
  InundationSimulationResponse? _data;
  bool _loading = true;
  String? _error;

  int _frameIndex = 0;
  Timer? _playTimer;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _playTimer?.cancel();
      _playing = false;
    });
    try {
      final api = ref.read(preciopsApiProvider);
      final result = await api.getInundationSimulation(district: _district, scenario: _scenario);
      if (!mounted) return;
      setState(() {
        _data = result;
        _frameIndex = 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't reach the inundation model. Pull to retry.";
        _loading = false;
      });
    }
  }

  void _togglePlay() {
    final frames = _data?.simulationFrames ?? const [];
    if (frames.isEmpty) return;
    if (_playing) {
      _playTimer?.cancel();
      setState(() => _playing = false);
      return;
    }
    setState(() {
      _playing = true;
      if (_frameIndex >= frames.length - 1) _frameIndex = 0;
    });
    _playTimer = Timer.periodic(const Duration(milliseconds: 1400), (timer) {
      if (!mounted) return;
      setState(() {
        if (_frameIndex >= frames.length - 1) {
          _playing = false;
          timer.cancel();
        } else {
          _frameIndex++;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Predictor Dashboard'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'agent-hub') context.push('/agent-hub');
              if (v == 'sos-dashboard') context.push('/sos-dashboard');
              if (v == 'logout') ref.read(authProvider.notifier).logout();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'agent-hub', child: Text('Multi-Agent Hub')),
              const PopupMenuItem(value: 'sos-dashboard', child: Text('Legacy SOS Dashboard')),
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
                        Text('Welcome, ${auth.user?.fullName ?? 'Predictor'}', style: AppTypography.label()),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: DistrictDropdown(
                                value: _district,
                                label: 'City',
                                onChanged: (v) {
                                  setState(() => _district = v);
                                  _load();
                                },
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _ScenarioToggle(
                                value: _scenario,
                                onChanged: (v) {
                                  setState(() => _scenario = v);
                                  _load();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SectionHeader(title: '4-Pillar Meteorological HUD'),
                        _FourPillarHud(telemetry: _data!.telemetry),
                        const SectionHeader(title: 'Inundation Map'),
                        _InundationMap(
                          frame: _data!.simulationFrames.isNotEmpty ? _data!.simulationFrames[_frameIndex] : null,
                          district: _district,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _TimeLapseControls(
                          frames: _data!.simulationFrames,
                          index: _frameIndex,
                          playing: _playing,
                          onScrub: (i) => setState(() => _frameIndex = i),
                          onPlayPause: _togglePlay,
                        ),
                        const SectionHeader(title: 'IMD Advisory'),
                        _AdvisoryPanel(data: _data!),
                        const SizedBox(height: AppSpacing.section),
                        AppButton(
                          label: 'Approve & Broadcast Alert',
                          icon: Icons.campaign_rounded,
                          color: AppColors.alertLevelColor(_data!.alertLevel),
                          onPressed: null,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Broadcast-approval endpoint pending backend — review only for now.',
                          style: AppTypography.caption(),
                          textAlign: TextAlign.center,
                        ),
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

class _ScenarioToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _ScenarioToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isExtreme = value == 'EXTREME_EVENT';
    return Container(
      height: 56,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(child: _seg(context, 'Normal', !isExtreme, () => onChanged('NORMAL'))),
          Expanded(child: _seg(context, 'Extreme', isExtreme, () => onChanged('EXTREME_EVENT'))),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? (label == 'Extreme' ? AppColors.dangerStrong : AppColors.accent) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: AppTypography.label(color: selected ? Colors.black : AppColors.textSecondary)
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// The 4-Pillar HUD: Satellite / Doppler Radar / Ground AWS / NWP Model,
/// arranged 2x2 per PS 26071's mandated 4 meteorological feeds.
class _FourPillarHud extends StatelessWidget {
  final FourPillarTelemetry telemetry;
  const _FourPillarHud({required this.telemetry});

  @override
  Widget build(BuildContext context) {
    return StatGrid(cards: [
      StatCard(
        label: 'Satellite (INSAT-3DR)',
        value: '${telemetry.cloudTopTempKelvin.toStringAsFixed(1)}K',
        trend: 'Rain rate ${telemetry.satelliteRainRateMmHr.toStringAsFixed(1)} mm/hr',
        icon: Icons.satellite_alt_outlined,
        accent: AppColors.info,
      ),
      StatCard(
        label: 'Doppler Radar (DWR)',
        value: '${telemetry.radarReflectivityDbz.toStringAsFixed(1)} dBZ',
        trend: 'Echo top ${telemetry.radarEchoTopKm.toStringAsFixed(1)} km',
        icon: Icons.radar_rounded,
        accent: AppColors.warning,
      ),
      StatCard(
        label: 'Ground AWS (IMD)',
        value: '${telemetry.awsRainRateMmHr.toStringAsFixed(1)} mm/hr',
        trend: '24h cumulative ${telemetry.awsCumulative24hMm.toStringAsFixed(1)} mm',
        icon: Icons.water_drop_outlined,
        accent: AppColors.accent,
      ),
      StatCard(
        label: 'NWP Model (NCMRWF)',
        value: '${telemetry.nwpPredictedPrecipMm.toStringAsFixed(1)} mm',
        trend: '${telemetry.nwpLeadTimeHours}h forecast precipitation',
        icon: Icons.insights_rounded,
        accent: AppColors.dangerStrong,
      ),
    ]);
  }
}

/// Deterministic pseudo-position for a landmark callout — the backend
/// gives landmark names only, no coordinates, so each name is jittered to
/// a stable point inside the polygon (seeded by the name's hash) purely
/// for a visual choke-point marker. Not a real surveyed location.
LatLng _landmarkPoint(String name, List<LatLng> ring) {
  if (ring.isEmpty) return const LatLng(0, 0);
  final lats = ring.map((p) => p.latitude);
  final lngs = ring.map((p) => p.longitude);
  final centerLat = lats.reduce((a, b) => a + b) / ring.length;
  final centerLng = lngs.reduce((a, b) => a + b) / ring.length;
  final spreadLat = (lats.reduce((a, b) => a > b ? a : b) - lats.reduce((a, b) => a < b ? a : b)) / 2;
  final spreadLng = (lngs.reduce((a, b) => a > b ? a : b) - lngs.reduce((a, b) => a < b ? a : b)) / 2;
  final seed = name.codeUnits.fold<int>(0, (acc, c) => acc + c);
  final fx = ((seed % 100) / 100 - 0.5) * 1.4;
  final fy = (((seed * 7) % 100) / 100 - 0.5) * 1.4;
  return LatLng(centerLat + fy * spreadLat, centerLng + fx * spreadLng);
}

class _InundationMap extends StatelessWidget {
  final InundationFrame? frame;
  final String district;
  const _InundationMap({required this.frame, required this.district});

  @override
  Widget build(BuildContext context) {
    final metro = NationalMetros.byName(district);
    final ring = frame?.polygonRing ?? const <LatLng>[];
    final depthColor = AppColors.depthColor(frame?.waterDepthMeters ?? 0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 320,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(initialCenter: metro.center, initialZoom: 13, minZoom: 4, maxZoom: 17),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.floodops.preciops_frontend',
                ),
                if (ring.length >= 3)
                  PolygonLayer(polygons: [
                    Polygon(
                      points: ring,
                      color: depthColor.withValues(alpha: 0.38),
                      borderColor: depthColor,
                      borderStrokeWidth: 2,
                    ),
                  ]),
                if (frame != null && ring.length >= 3)
                  MarkerLayer(markers: [
                    for (final landmark in frame!.affectedLandmarks)
                      Marker(
                        point: _landmarkPoint(landmark, ring),
                        width: 150,
                        height: 56,
                        alignment: Alignment.bottomCenter,
                        child: _LandmarkCallout(name: landmark, depthMeters: frame!.waterDepthMeters),
                      ),
                  ]),
              ],
            ),
            Positioned(
              left: 12,
              top: 12,
              child: StatusBadge(
                label: '${frame?.severity ?? 'LOW'} · ${(frame?.waterDepthMeters ?? 0).toStringAsFixed(2)}m',
                color: depthColor,
                icon: Icons.water_rounded,
                filled: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandmarkCallout extends StatelessWidget {
  final String name;
  final double depthMeters;
  const _LandmarkCallout({required this.name, required this.depthMeters});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.glassSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Text(
                '$name: ${depthMeters.toStringAsFixed(2)}m Submerged',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.caption(color: AppColors.textPrimary).copyWith(fontSize: 10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        MapPinMarker(icon: Icons.warning_rounded, color: AppColors.dangerStrong, size: 22),
      ],
    );
  }
}

class _TimeLapseControls extends StatelessWidget {
  final List<InundationFrame> frames;
  final int index;
  final bool playing;
  final ValueChanged<int> onScrub;
  final VoidCallback onPlayPause;

  const _TimeLapseControls({
    required this.frames,
    required this.index,
    required this.playing,
    required this.onScrub,
    required this.onPlayPause,
  });

  @override
  Widget build(BuildContext context) {
    if (frames.isEmpty) return const SizedBox.shrink();
    final current = frames[index];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(current.timeStep, style: AppTypography.cardTitle()),
              Text(
                'Predicted Water Depth: ${current.waterDepthMeters.toStringAsFixed(2)}m',
                style: AppTypography.accentValue(color: AppColors.depthColor(current.waterDepthMeters)).copyWith(fontSize: 15),
              ),
            ],
          ),
          AppSlider(
            value: index.toDouble(),
            min: 0,
            max: (frames.length - 1).toDouble(),
            onChanged: (v) => onScrub(v.round()),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final f in frames)
                Text(
                  f.timeStep.split(' ').first,
                  style: AppTypography.caption(
                    color: f == current ? AppColors.accent : AppColors.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.secondary(
            label: playing ? 'Pause Simulation' : '▶ Simulate Flood Spread',
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            onPressed: onPlayPause,
          ),
        ],
      ),
    );
  }
}

class _AdvisoryPanel extends StatelessWidget {
  final InundationSimulationResponse data;
  const _AdvisoryPanel({required this.data});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.alertLevelColor(data.alertLevel);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(label: '${data.alertLevel} ALERT', color: color, icon: Icons.campaign_outlined, filled: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(data.leadTimeWarning, style: AppTypography.label(), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(data.advisoryBulletin, style: AppTypography.body(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
