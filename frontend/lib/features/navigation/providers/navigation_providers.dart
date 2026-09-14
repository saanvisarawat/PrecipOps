import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../api/models/shelter_models.dart';
import '../../../providers/connectivity_provider.dart';
import '../../../providers/service_providers.dart';
import '../controllers/navigation_controller.dart';
import '../controllers/navigation_state.dart';
import '../models/offline_region.dart';
import '../services/offline_map_service.dart';
import '../services/offline_tile_provider.dart';
import '../services/routing_service.dart';

final offlineMapServiceProvider = Provider<OfflineMapService>((ref) => OfflineMapService());

final offlineTileProviderProvider = Provider<OfflineTileProvider>((ref) {
  return OfflineTileProvider(
    offlineMapService: ref.watch(offlineMapServiceProvider),
    isOnline: () => ref.read(isOnlineProvider),
  );
});

final routingServiceProvider = Provider<RoutingService>((ref) {
  return HybridRoutingService(isOnline: () => ref.read(isOnlineProvider));
});

final navigationControllerProvider = StateNotifierProvider<NavigationController, NavigationState>((ref) {
  return NavigationController(ref.watch(routingServiceProvider));
});

/// Raw continuous GPS updates. A 5 m distance filter (set in
/// [LocationService.watchPosition]) keeps this from firing on every GPS
/// jitter while stationary.
final positionStreamProvider = StreamProvider<Position>((ref) {
  return ref.watch(locationServiceProvider).watchPosition();
});

/// Manages the list of downloaded/downloading offline regions and drives
/// [OfflineMapService] downloads, surfacing progress back into the list
/// so [OfflineMapsScreen] just watches this provider.
class OfflineRegionsController extends StateNotifier<AsyncValue<List<OfflineRegion>>> {
  OfflineRegionsController(this._service) : super(const AsyncValue.loading()) {
    refresh();
  }

  final OfflineMapService _service;

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _service.listRegions());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void _upsert(OfflineRegion region) {
    final current = state.value ?? [];
    final index = current.indexWhere((r) => r.id == region.id);
    final next = [...current];
    if (index == -1) {
      next.insert(0, region);
    } else {
      next[index] = region;
    }
    state = AsyncValue.data(next);
  }

  Future<void> download({
    required String regionId,
    required String districtName,
    required double north,
    required double south,
    required double east,
    required double west,
  }) async {
    try {
      await _service.downloadRegion(
        regionId: regionId,
        districtName: districtName,
        north: north,
        south: south,
        east: east,
        west: west,
        onProgress: _upsert,
      );
    } finally {
      await refresh();
    }
  }

  void cancel(String regionId) => _service.cancelDownload(regionId);

  Future<void> delete(String regionId) async {
    await _service.deleteRegion(regionId);
    await refresh();
  }

  int estimateTiles({required double north, required double south, required double east, required double west}) {
    return _service.estimateTileCount(north: north, south: south, east: east, west: west);
  }
}

final offlineRegionsControllerProvider = StateNotifierProvider<OfflineRegionsController, AsyncValue<List<OfflineRegion>>>((ref) {
  return OfflineRegionsController(ref.watch(offlineMapServiceProvider));
});

/// Last successfully fetched shelters list, kept in memory for the
/// session so destination search still works offline from whatever was
/// last synced (there's no geocoding backend — shelters are the only
/// searchable destinations in this app).
final sheltersCacheProvider = StateProvider<List<ShelterFeature>>((ref) => []);
