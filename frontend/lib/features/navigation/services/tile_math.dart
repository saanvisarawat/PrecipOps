import 'dart:math';

/// Slippy-map tile coordinates for one XYZ tile.
class TileCoord {
  final int z;
  final int x;
  final int y;
  const TileCoord(this.z, this.x, this.y);

  @override
  bool operator ==(Object other) => other is TileCoord && other.z == z && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(z, x, y);
}

/// Standard OSM slippy-map tile math (see wiki.openstreetmap.org/wiki/Slippy_map_tilenames).
class TileMath {
  TileMath._();

  static int lonToTileX(double lon, int z) => ((lon + 180.0) / 360.0 * (1 << z)).floor();

  static int latToTileY(double lat, int z) {
    final latRad = lat * pi / 180.0;
    return ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * (1 << z)).floor();
  }

  /// Every tile covering [north]/[south]/[east]/[west] across
  /// [minZoom]..[maxZoom] inclusive.
  static List<TileCoord> tilesForBounds({
    required double north,
    required double south,
    required double east,
    required double west,
    required int minZoom,
    required int maxZoom,
  }) {
    final tiles = <TileCoord>[];
    for (var z = minZoom; z <= maxZoom; z++) {
      final xMin = lonToTileX(west, z);
      final xMax = lonToTileX(east, z);
      final yMin = latToTileY(north, z);
      final yMax = latToTileY(south, z);
      for (var x = xMin; x <= xMax; x++) {
        for (var y = yMin; y <= yMax; y++) {
          tiles.add(TileCoord(z, x, y));
        }
      }
    }
    return tiles;
  }
}
