import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../api/models/shelter_models.dart';
import '../../core/constants/national_metros.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/api_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/map_pin_marker.dart';
import '../../widgets/status_badge.dart';
import '../navigation/models/nav_destination.dart';
import '../navigation/providers/navigation_providers.dart';

class EvacuationMapScreen extends ConsumerStatefulWidget {
  const EvacuationMapScreen({super.key});

  @override
  ConsumerState<EvacuationMapScreen> createState() => _EvacuationMapScreenState();
}

class _EvacuationMapScreenState extends ConsumerState<EvacuationMapScreen> {
  List<ShelterFeature>? _shelters;
  Position? _myPosition;
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadMyPosition();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(preciopsApiProvider);
    List<ShelterFeature> features = const [];
    try {
      features = (await api.getSheltersGeoJson()).features;
    } catch (_) {
      // Leave the list empty rather than stuck loading forever if the
      // backend is briefly unreachable.
    }
    if (mounted) setState(() => _shelters = features);
  }

  Future<void> _loadMyPosition() async {
    try {
      final pos = await ref.read(locationServiceProvider).getCurrentPosition();
      if (mounted) setState(() => _myPosition = pos);
    } catch (_) {
      // No GPS fix available — the map still works, just without a "you
      // are here" marker or recenter target.
    }
  }

  Future<void> _recenter() async {
    if (_myPosition == null) {
      await _loadMyPosition();
    }
    final target = _myPosition == null
        ? NationalMetros.indiaMapCenter
        : LatLng(_myPosition!.latitude, _myPosition!.longitude);
    _mapController.move(target, _myPosition == null ? NationalMetros.indiaMapDefaultZoom : 13);
  }

  Color _statusColor(ShelterFeature s) {
    final ratio = s.occupancyRatio;
    if (ratio >= 1.0) return AppColors.danger;
    if (ratio >= 0.75) return AppColors.warning;
    return AppColors.accent;
  }

  List<ShelterFeature> get _filtered {
    final all = _shelters ?? [];
    if (_query.trim().isEmpty) return all;
    final q = _query.toLowerCase();
    return all
        .where((s) => s.name.toLowerCase().contains(q) || s.district.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(isOnlineProvider);
    // Same offline-first tile provider the Navigate screen uses (shared
    // disk cache) — read-through on a hit, write-through-caches on a
    // network fetch, and falls back to a blank tile instead of an error
    // when offline with no cached copy of a given tile.
    final tileProvider = ref.watch(offlineTileProviderProvider);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: NationalMetros.indiaMapCenter,
            initialZoom: NationalMetros.indiaMapDefaultZoom,
            minZoom: 4,
            maxZoom: 17,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.floodops.preciops_frontend',
              tileProvider: tileProvider,
            ),
            if (_shelters != null)
              MarkerLayer(
                markers: [
                  for (final s in _filtered)
                    Marker(
                      point: LatLng(s.latitude, s.longitude),
                      width: 96,
                      height: 68,
                      alignment: Alignment.bottomCenter,
                      child: GestureDetector(
                        onTap: () => _showShelterSheet(s),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceHigh,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _statusColor(s).withValues(alpha: 0.6)),
                              ),
                              child: Text(
                                '${s.availableSpace} left',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _statusColor(s),
                                ),
                              ),
                            ),
                            MapPinMarker(icon: Icons.home_work_rounded, color: _statusColor(s)),
                          ],
                        ),
                      ),
                    ),
                  if (_myPosition != null)
                    Marker(
                      point: LatLng(_myPosition!.latitude, _myPosition!.longitude),
                      width: 34,
                      height: 34,
                      child: const MapPinMarker(icon: Icons.navigation_rounded, color: AppColors.info, size: 30, pulsing: true),
                    ),
                ],
              ),
          ],
        ),
        if (_shelters == null)
          const Positioned(
            top: 90,
            left: 0,
            right: 0,
            child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.4)),
          ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Column(
            children: [
              _SearchPill(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                badgeCount: (_shelters ?? []).where((s) => s.occupancyRatio < 0.75).length,
              ),
              if (!isOnline) ...[
                const SizedBox(height: 10),
                const Align(alignment: Alignment.centerLeft, child: _OfflineMapsChip()),
              ],
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 132,
          child: _MapControlButton(icon: Icons.my_location_rounded, onTap: _recenter),
        ),
        Positioned.fill(
          child: DraggableScrollableSheet(
            initialChildSize: 0.16,
            minChildSize: 0.12,
            maxChildSize: 0.62,
            builder: (context, scrollController) => _ShelterSheet(
              scrollController: scrollController,
              shelters: _filtered,
              statusColor: _statusColor,
              onTapShelter: _showShelterSheet,
            ),
          ),
        ),
      ],
    );
  }

  void _showShelterSheet(ShelterFeature s) {
    AppBottomSheet.show(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MapPinMarker(icon: Icons.home_work_rounded, color: _statusColor(s), size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, style: AppTypography.cardTitle().copyWith(fontSize: 17)),
                    const SizedBox(height: 3),
                    Text(
                      '${s.district} • ${s.address}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.label(),
                    ),
                  ],
                ),
              ),
              AppButton.tertiary(
                label: 'Directions',
                icon: Icons.north_east_rounded,
                onPressed: () {
                  // Capture the router before popping the sheet — `context`
                  // here is the sheet's own context, which is on its way
                  // out as soon as Navigator.pop runs.
                  final router = GoRouter.of(context);
                  Navigator.pop(context);
                  router.push('/navigate', extra: NavDestination.fromShelter(s));
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          StatusBadge(
            label: '${s.currentOccupancy}/${s.capacity} occupied · ${s.availableSpace} left',
            color: _statusColor(s),
            icon: Icons.groups_outlined,
          ),
        ],
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final int badgeCount;

  const _SearchPill({required this.controller, required this.onChanged, required this.badgeCount});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.glassSurface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: AppColors.softShadow(opacity: 0.24, blur: 16),
          ),
          child: Row(
            children: [
              const SizedBox(width: 6),
              const Icon(Icons.search_rounded, color: AppColors.textTertiary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: AppTypography.body(),
                  decoration: const InputDecoration(
                    hintText: 'Search shelters or district',
                    border: InputBorder.none,
                    isDense: true,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: AppTypography.caption()),
      ],
    );
  }
}

/// Small floating circular control — the "location/layers/compass" cluster
/// on an Apple-Maps-style map. Glass surface, never a flat Material FAB.
class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapControlButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          color: AppColors.glassSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppColors.glassBorder),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: Icon(icon, color: AppColors.info, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small pill signaling that map tiles are being served from the offline
/// cache (see `features/navigation/services/offline_tile_provider.dart`)
/// rather than the live network.
class _OfflineMapsChip extends StatelessWidget {
  const _OfflineMapsChip();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.glassSurface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_outlined, color: AppColors.warning, size: 14),
              const SizedBox(width: 6),
              Text('Offline Maps', style: AppTypography.caption(color: AppColors.warning)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draggable bottom sheet replacing the old fixed legend bar — collapses to
/// a legend-only handle, drags up to reveal the nearby-shelter list.
class _ShelterSheet extends StatelessWidget {
  final ScrollController scrollController;
  final List<ShelterFeature> shelters;
  final Color Function(ShelterFeature) statusColor;
  final ValueChanged<ShelterFeature> onTapShelter;

  const _ShelterSheet({
    required this.scrollController,
    required this.shelters,
    required this.statusColor,
    required this.onTapShelter,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.glassSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: AppColors.cardBorder, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: const [
                  _Legend(color: AppColors.accent, label: 'Available'),
                  _Legend(color: AppColors.warning, label: 'Nearly Full'),
                  _Legend(color: AppColors.danger, label: 'Full'),
                ],
              ),
              const SizedBox(height: 18),
              Text('Nearby Shelters', style: AppTypography.sectionTitle()),
              const SizedBox(height: 10),
              for (final s in shelters)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    onTap: () => onTapShelter(s),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        MapPinMarker(icon: Icons.home_work_rounded, color: statusColor(s), size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.cardTitle().copyWith(fontSize: 14)),
                              Text('${s.district} · ${s.availableSpace} spaces left', style: AppTypography.caption()),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
