import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/national_metros.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/status_badge.dart';
import '../models/offline_region.dart';
import '../providers/navigation_providers.dart';
import '../services/offline_map_service.dart';

/// Assumed average size of one downloaded OSM raster tile, used only to
/// show a rough "~N MB" estimate before the user confirms a download —
/// the actual byte count tracked per region comes from real downloaded
/// bytes, not this constant.
const int _kAssumedTileBytes = 15 * 1024;

/// A downloadable region is one of the app's 5 national metros (reusing
/// [NationalMetros] — the app's only real geographic dataset) with a
/// fixed-radius bounding box, rather than a freehand map-rectangle
/// picker. Simpler to use correctly, and every region has a predictable,
/// previewable tile count.
class _DistrictRegion {
  final String name;
  final double north, south, east, west;
  const _DistrictRegion({required this.name, required this.north, required this.south, required this.east, required this.west});

  factory _DistrictRegion.fromCenter(MetroProfile d) {
    const halfDegLat = 0.35;
    final halfDegLon = 0.35 / (0.999 - 0.002 * d.center.latitude.abs() / 15);
    return _DistrictRegion(
      name: d.name,
      north: d.center.latitude + halfDegLat,
      south: d.center.latitude - halfDegLat,
      east: d.center.longitude + halfDegLon,
      west: d.center.longitude - halfDegLon,
    );
  }

  String get id => 'district-${name.toLowerCase().replaceAll(' ', '-')}';
}

class OfflineMapsScreen extends ConsumerWidget {
  const OfflineMapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regionsAsync = ref.watch(offlineRegionsControllerProvider);
    final districts = NationalMetros.all.map(_DistrictRegion.fromCenter).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Offline Maps')),
      body: regionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.4)),
        error: (e, _) => Center(child: Text('Could not load offline maps.', style: AppTypography.body())),
        data: (regions) {
          final downloadedIds = regions.map((r) => r.id).toSet();
          final availableDistricts = districts.where((d) => !downloadedIds.contains(d.id)).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, AppSpacing.md, AppSpacing.screenPadding, AppSpacing.section),
            children: [
              Text(
                'Download a district for offline use to keep the map, your position and basic guidance working with no signal.',
                style: AppTypography.body(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.section),
              if (regions.isNotEmpty) ...[
                Text('DOWNLOADED', style: AppTypography.caption().copyWith(letterSpacing: 1)),
                const SizedBox(height: AppSpacing.compact),
                for (final region in regions) ...[
                  _RegionCard(region: region),
                  const SizedBox(height: AppSpacing.compact),
                ],
                const SizedBox(height: AppSpacing.md),
              ],
              Text('AVAILABLE DISTRICTS', style: AppTypography.caption().copyWith(letterSpacing: 1)),
              const SizedBox(height: AppSpacing.compact),
              for (final district in availableDistricts) ...[
                _DistrictTile(district: district),
                const SizedBox(height: AppSpacing.compact),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RegionCard extends ConsumerWidget {
  final OfflineRegion region;
  const _RegionCard({required this.region});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(offlineRegionsControllerProvider.notifier);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(region.districtName, style: AppTypography.cardTitle())),
              _statusBadge(region.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            region.status == OfflineRegionStatus.downloading
                ? '${region.downloadedTiles}/${region.totalTiles} tiles • ${region.sizeLabel}'
                : '${region.totalTiles} tiles • ${region.sizeLabel}',
            style: AppTypography.label(),
          ),
          if (region.status == OfflineRegionStatus.downloading) ...[
            const SizedBox(height: AppSpacing.compact),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: region.progress,
                minHeight: 6,
                backgroundColor: AppColors.surfaceHigh,
                color: AppColors.accent,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (region.status == OfflineRegionStatus.downloading)
                AppButton.secondary(label: 'Cancel', expand: false, onPressed: () => controller.cancel(region.id))
              else ...[
                AppButton.secondary(
                  label: region.status == OfflineRegionStatus.complete ? 'Update' : 'Redownload',
                  expand: false,
                  onPressed: () => controller.download(
                    regionId: region.id,
                    districtName: region.districtName,
                    north: region.north,
                    south: region.south,
                    east: region.east,
                    west: region.west,
                  ),
                ),
                const SizedBox(width: AppSpacing.compact),
                AppButton.tertiary(label: 'Delete', color: AppColors.danger, onPressed: () => controller.delete(region.id)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(OfflineRegionStatus status) {
    switch (status) {
      case OfflineRegionStatus.complete:
        return const StatusBadge(label: 'Ready offline', color: AppColors.accent, icon: Icons.check_circle_outline, dot: true);
      case OfflineRegionStatus.downloading:
        return const StatusBadge(label: 'Downloading', color: AppColors.warning, icon: Icons.downloading_rounded, dot: true);
      case OfflineRegionStatus.failed:
        return const StatusBadge(label: 'Failed — storage', color: AppColors.danger, icon: Icons.error_outline, dot: true);
      case OfflineRegionStatus.interrupted:
        return const StatusBadge(label: 'Interrupted', color: AppColors.warning, icon: Icons.pause_circle_outline, dot: true);
    }
  }
}

class _DistrictTile extends ConsumerWidget {
  final _DistrictRegion district;
  const _DistrictTile({required this.district});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      onTap: () => _confirmDownload(context, ref),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.surfaceRaised, shape: BoxShape.circle),
            child: const Icon(Icons.map_outlined, color: AppColors.accent, size: 19),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(district.name, style: AppTypography.cardTitle().copyWith(fontSize: 15))),
          const Icon(Icons.download_outlined, color: AppColors.textTertiary, size: 20),
        ],
      ),
    );
  }

  Future<void> _confirmDownload(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(offlineRegionsControllerProvider.notifier);
    final tiles = controller.estimateTiles(north: district.north, south: district.south, east: district.east, west: district.west);
    final estimatedMb = (tiles * _kAssumedTileBytes / (1024 * 1024)).toStringAsFixed(0);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text('Download ${district.name}?', style: AppTypography.cardTitle()),
        content: Text(
          '~$tiles map tiles (~$estimatedMb MB). Zoom levels $kOfflineMinZoom–$kOfflineMaxZoom. '
          'You\'ll be able to pan, zoom and see your GPS position here with no signal.',
          style: AppTypography.body(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Download')),
        ],
      ),
    );

    if (confirmed == true) {
      unawaited(controller.download(
        regionId: district.id,
        districtName: district.name,
        north: district.north,
        south: district.south,
        east: district.east,
        west: district.west,
      ));
    }
  }
}
