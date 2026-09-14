enum OfflineRegionStatus { downloading, complete, failed, interrupted }

/// A downloadable/downloaded offline map region. Regions are always one
/// of the existing [KeralaDistricts] entries — picking a real district
/// instead of a freehand map rectangle keeps region selection simple and
/// gives a predictable, testable tile count.
class OfflineRegion {
  final String id;
  final String districtName;
  final double north;
  final double south;
  final double east;
  final double west;
  final int minZoom;
  final int maxZoom;
  final int totalTiles;
  final int downloadedTiles;
  final int bytes;
  final OfflineRegionStatus status;
  final DateTime updatedAt;

  const OfflineRegion({
    required this.id,
    required this.districtName,
    required this.north,
    required this.south,
    required this.east,
    required this.west,
    required this.minZoom,
    required this.maxZoom,
    required this.totalTiles,
    required this.downloadedTiles,
    required this.bytes,
    required this.status,
    required this.updatedAt,
  });

  double get progress => totalTiles == 0 ? 0 : downloadedTiles / totalTiles;

  String get sizeLabel {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  OfflineRegion copyWith({
    int? downloadedTiles,
    int? bytes,
    OfflineRegionStatus? status,
    DateTime? updatedAt,
  }) =>
      OfflineRegion(
        id: id,
        districtName: districtName,
        north: north,
        south: south,
        east: east,
        west: west,
        minZoom: minZoom,
        maxZoom: maxZoom,
        totalTiles: totalTiles,
        downloadedTiles: downloadedTiles ?? this.downloadedTiles,
        bytes: bytes ?? this.bytes,
        status: status ?? this.status,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
