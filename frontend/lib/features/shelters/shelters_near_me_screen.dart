import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../api/floodops_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/api_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/map_pin_marker.dart';
import '../../widgets/shelter_card.dart';
import '../../widgets/status_badge.dart';
import '../navigation/models/nav_destination.dart';

/// Distance-sorted list of every shelter (GET /api/shelters/geojson —
/// already fetched elsewhere by the Evacuation Map/Home; this screen just
/// re-fetches the same endpoint and sorts by the user's live GPS fix).
class SheltersNearMeScreen extends ConsumerStatefulWidget {
  const SheltersNearMeScreen({super.key});

  @override
  ConsumerState<SheltersNearMeScreen> createState() => _SheltersNearMeScreenState();
}

class _SheltersNearMeScreenState extends ConsumerState<SheltersNearMeScreen> {
  static const _distance = Distance();

  List<ShelterFeature>? _shelters;
  Map<String, double> _distanceKm = {};
  bool _locationDenied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    LatLng? here;
    try {
      final pos = await ref.read(locationServiceProvider).getCurrentPosition();
      here = LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      _locationDenied = true;
    }

    List<ShelterFeature> shelters = const [];
    try {
      shelters = (await ref.read(preciopsApiProvider).getSheltersGeoJson()).features;
    } catch (_) {
      if (mounted) {
        AppToast.show(context, "Couldn't load shelters — check your connection.", kind: AppToastKind.error);
      }
    }

    final distances = <String, double>{};
    if (here != null) {
      for (final s in shelters) {
        distances[s.id] = _distance.as(LengthUnit.Kilometer, here, LatLng(s.latitude, s.longitude));
      }
      shelters = [...shelters]..sort((a, b) => (distances[a.id] ?? 0).compareTo(distances[b.id] ?? 0));
    }

    if (!mounted) return;
    setState(() {
      _shelters = shelters;
      _distanceKm = distances;
    });
  }

  void _showShelterSheet(ShelterFeature s) {
    final ratio = s.occupancyRatio;
    final color = ratio >= 1.0 ? AppColors.danger : (ratio >= 0.75 ? AppColors.warning : AppColors.accent);
    AppBottomSheet.show(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MapPinMarker(icon: Icons.home_work_rounded, color: color, size: 44),
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
            color: color,
            icon: Icons.groups_outlined,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shelters Near Me')),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.accent,
        backgroundColor: AppColors.surfaceHigh,
        child: _shelters == null
            ? ListView(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                children: [
                  for (var i = 0; i < 5; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppSkeleton(height: 100, borderRadius: BorderRadius.circular(20)),
                    ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.sm,
                  AppSpacing.screenPadding,
                  AppSpacing.xxl,
                ),
                children: [
                  if (_locationDenied)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        'Location unavailable — showing all shelters, unsorted by distance.',
                        style: AppTypography.caption(),
                      ),
                    ),
                  if (_shelters!.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.section),
                      child: Center(
                        child: Text('No shelters found.', style: AppTypography.body(color: AppColors.textSecondary)),
                      ),
                    ),
                  for (final s in _shelters!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ShelterCard(
                        shelter: s,
                        width: double.infinity,
                        distanceKm: _distanceKm[s.id],
                        onTap: () => _showShelterSheet(s),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
