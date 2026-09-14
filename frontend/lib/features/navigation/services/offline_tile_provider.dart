import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

import 'offline_map_service.dart';
import 'tile_math.dart';

/// A flutter_map [TileProvider] that checks the offline disk cache first
/// and only touches the network on a cache miss while online — this is
/// what makes [NavigationMapScreen] pannable/zoomable with no signal, and
/// it write-through-caches whatever it fetches so simply browsing while
/// online organically seeds the offline store.
class OfflineTileProvider extends TileProvider {
  OfflineTileProvider({required this.offlineMapService, required this.isOnline, super.headers});

  final OfflineMapService offlineMapService;
  final bool Function() isOnline;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _OfflineFirstImageProvider(
      tile: TileCoord(coordinates.z, coordinates.x, coordinates.y),
      url: getTileUrl(coordinates, options),
      headers: headers,
      offlineMapService: offlineMapService,
      isOnline: isOnline,
    );
  }
}

@immutable
class _OfflineFirstImageProvider extends ImageProvider<_OfflineFirstImageProvider> {
  final TileCoord tile;
  final String url;
  final Map<String, String> headers;
  final OfflineMapService offlineMapService;
  final bool Function() isOnline;

  const _OfflineFirstImageProvider({
    required this.tile,
    required this.url,
    required this.headers,
    required this.offlineMapService,
    required this.isOnline,
  });

  @override
  ImageStreamCompleter loadImage(_OfflineFirstImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1,
      debugLabel: url,
    );
  }

  Future<Codec> _load(ImageDecoderCallback decode) async {
    final cached = await offlineMapService.readTile(tile);
    if (cached != null) {
      return decode(await ImmutableBuffer.fromUint8List(cached));
    }

    if (!isOnline()) {
      return decode(await ImmutableBuffer.fromUint8List(TileProvider.transparentImage));
    }

    try {
      final bytes = await offlineMapService.fetchAndCacheTile(tile, url, headers);
      return decode(await ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      return decode(await ImmutableBuffer.fromUint8List(TileProvider.transparentImage));
    }
  }

  @override
  SynchronousFuture<_OfflineFirstImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  bool operator ==(Object other) => identical(this, other) || (other is _OfflineFirstImageProvider && other.tile == tile);

  @override
  int get hashCode => tile.hashCode;
}
