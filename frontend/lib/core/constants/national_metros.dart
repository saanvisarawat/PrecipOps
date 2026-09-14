import 'package:latlong2/latlong.dart';

/// City profile for the pan-India metros this app now covers — mirrors the
/// backend's `PAN_INDIA_REGISTRY` in app/routers/inundation.py (same 5
/// cities, same center coordinates) so district pickers and map defaults
/// line up with whatever the inundation/routing/analytics endpoints return
/// for a given `district=` query param.
class MetroProfile {
  final String name;
  final LatLng center;
  final double avgElevationM;
  final double avgSlopeDeg;
  final String terrainNote;
  final double baseRiskScore; // 0-100, mock-only flavor for Agent Hub demo
  final double avgAnnualRainfallMm;

  const MetroProfile({
    required this.name,
    required this.center,
    this.avgElevationM = 20,
    this.avgSlopeDeg = 2,
    this.terrainNote = 'Coastal urban lowland',
    this.baseRiskScore = 60,
    this.avgAnnualRainfallMm = 2000,
  });
}

/// The app's national scope: 5 metros, replacing the old single-state
/// 14-district list. Every district picker in the app reads from here.
class NationalMetros {
  NationalMetros._();

  static const LatLng indiaMapCenter = LatLng(22.5, 80.0);
  static const double indiaMapDefaultZoom = 4.4;

  static const List<MetroProfile> all = [
    MetroProfile(
      name: 'Mumbai',
      center: LatLng(19.018, 72.842),
      avgElevationM: 14,
      avgSlopeDeg: 2,
      terrainNote: 'Coastal lowland on reclaimed land, monsoon drainage overload',
      baseRiskScore: 75,
      avgAnnualRainfallMm: 2400,
    ),
    MetroProfile(
      name: 'Chennai',
      center: LatLng(12.985, 80.218),
      avgElevationM: 6,
      avgSlopeDeg: 1,
      terrainNote: 'Flat coastal plain, Adyar/Cooum river floodplain',
      baseRiskScore: 70,
      avgAnnualRainfallMm: 1400,
    ),
    MetroProfile(
      name: 'Delhi',
      center: LatLng(28.632, 77.240),
      avgElevationM: 216,
      avgSlopeDeg: 2,
      terrainNote: 'Yamuna floodplain, urban drainage stress',
      baseRiskScore: 55,
      avgAnnualRainfallMm: 790,
    ),
    MetroProfile(
      name: 'Guwahati',
      center: LatLng(26.155, 91.765),
      avgElevationM: 55,
      avgSlopeDeg: 6,
      terrainNote: 'Brahmaputra river basin, hill-fringe urban sprawl',
      baseRiskScore: 72,
      avgAnnualRainfallMm: 1700,
    ),
    MetroProfile(
      name: 'Ernakulam',
      center: LatLng(9.975, 76.285),
      avgElevationM: 8,
      avgSlopeDeg: 2,
      terrainNote: 'Coastal, Periyar river delta, dense urban low-lying',
      baseRiskScore: 65,
      avgAnnualRainfallMm: 3000,
    ),
  ];

  static const List<String> names = ['Mumbai', 'Chennai', 'Delhi', 'Guwahati', 'Ernakulam'];

  static MetroProfile byName(String name) =>
      all.firstWhere((d) => d.name.toLowerCase() == name.toLowerCase(), orElse: () => all.first);

  /// Nearest metro to a GPS fix, by straight-line distance to each city's
  /// center point — used to turn a raw lat/lng into a metro the UI already
  /// understands (mirrors the same haversine approach `dio_preciops_api.dart`
  /// uses privately for shelter/task district lookups).
  static MetroProfile nearest(double lat, double lng) {
    const distance = Distance();
    final point = LatLng(lat, lng);
    var closest = all.first;
    var best = double.infinity;
    for (final m in all) {
      final km = distance.as(LengthUnit.Kilometer, point, m.center);
      if (km < best) {
        best = km;
        closest = m;
      }
    }
    return closest;
  }
}
