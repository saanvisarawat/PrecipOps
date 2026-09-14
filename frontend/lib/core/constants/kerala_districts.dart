import 'package:latlong2/latlong.dart';

/// Kerala's 14 districts — mirrors the backend's `KERALA_DISTRICTS` in
/// app/data_ingestion.py exactly (same names, same lat/lon) so
/// POST /api/ml/predict-kerala never 404s with "No live telemetry found".
/// The terrain/risk fields below are mock-only flavor (not real survey
/// data) used to make the Agent Hub and other district-driven mock output
/// look believable per district.
class KeralaDistrict {
  final String name;
  final double lat;
  final double lon;
  final double avgElevationM;
  final double avgSlopeDeg;
  final String terrainNote;
  final double baseRiskScore; // 0-100, mock-only seed for demo risk output
  final double avgAnnualRainfallMm;

  const KeralaDistrict({
    required this.name,
    required this.lat,
    required this.lon,
    this.avgElevationM = 50,
    this.avgSlopeDeg = 4,
    this.terrainNote = 'Kerala midland terrain',
    this.baseRiskScore = 50,
    this.avgAnnualRainfallMm = 3000,
  });

  LatLng get center => LatLng(lat, lon);
}

class KeralaDistricts {
  KeralaDistricts._();

  /// Demo/dev default — matches the PS 71 test coordinates
  /// `{"lat": 11.68, "lon": 76.13}` exactly.
  static const String defaultName = 'Wayanad';

  static const LatLng keralaMapCenter = LatLng(10.3, 76.35);
  static const double keralaMapDefaultZoom = 7.3;

  static const List<KeralaDistrict> all = [
    KeralaDistrict(
      name: 'Thiruvananthapuram',
      lat: 8.52,
      lon: 76.93,
      avgElevationM: 64,
      avgSlopeDeg: 4,
      terrainNote: 'Coastal lowland with midland hills',
      baseRiskScore: 38,
      avgAnnualRainfallMm: 1850,
    ),
    KeralaDistrict(
      name: 'Kollam',
      lat: 8.89,
      lon: 76.61,
      avgElevationM: 45,
      avgSlopeDeg: 3,
      terrainNote: 'Coastal, Ashtamudi backwaters',
      baseRiskScore: 42,
      avgAnnualRainfallMm: 2100,
    ),
    KeralaDistrict(
      name: 'Pathanamthitta',
      lat: 9.26,
      lon: 76.78,
      avgElevationM: 220,
      avgSlopeDeg: 9,
      terrainNote: 'Pamba river basin, highland-midland mix',
      baseRiskScore: 68,
      avgAnnualRainfallMm: 2650,
    ),
    KeralaDistrict(
      name: 'Alappuzha',
      lat: 9.49,
      lon: 76.33,
      avgElevationM: 2,
      avgSlopeDeg: 1,
      terrainNote: 'Kuttanad — below sea level, flat backwater delta',
      baseRiskScore: 82,
      avgAnnualRainfallMm: 2350,
    ),
    KeralaDistrict(
      name: 'Kottayam',
      lat: 9.59,
      lon: 76.52,
      avgElevationM: 15,
      avgSlopeDeg: 2,
      terrainNote: 'Low-lying Kuttanad fringe, backwater adjacent',
      baseRiskScore: 71,
      avgAnnualRainfallMm: 2450,
    ),
    KeralaDistrict(
      name: 'Idukki',
      lat: 9.85,
      lon: 76.94,
      avgElevationM: 1500,
      avgSlopeDeg: 26,
      terrainNote: 'Western Ghats highlands, steep terrain, dam catchments',
      baseRiskScore: 58,
      avgAnnualRainfallMm: 3200,
    ),
    KeralaDistrict(
      name: 'Ernakulam',
      lat: 9.98,
      lon: 76.28,
      avgElevationM: 8,
      avgSlopeDeg: 2,
      terrainNote: 'Coastal, Periyar river delta, dense urban low-lying',
      baseRiskScore: 65,
      avgAnnualRainfallMm: 3000,
    ),
    KeralaDistrict(
      name: 'Thrissur',
      lat: 10.52,
      lon: 76.21,
      avgElevationM: 30,
      avgSlopeDeg: 3,
      terrainNote: 'Chalakudy river plains, Kole wetlands',
      baseRiskScore: 60,
      avgAnnualRainfallMm: 3100,
    ),
    KeralaDistrict(
      name: 'Palakkad',
      lat: 10.78,
      lon: 76.65,
      avgElevationM: 110,
      avgSlopeDeg: 6,
      terrainNote: 'Palakkad Gap, semi-arid rain shadow plains',
      baseRiskScore: 34,
      avgAnnualRainfallMm: 2400,
    ),
    KeralaDistrict(
      name: 'Malappuram',
      lat: 11.07,
      lon: 76.07,
      avgElevationM: 60,
      avgSlopeDeg: 5,
      terrainNote: 'Chaliyar and Kadalundi river basins',
      baseRiskScore: 55,
      avgAnnualRainfallMm: 3000,
    ),
    KeralaDistrict(
      name: 'Kozhikode',
      lat: 11.25,
      lon: 75.78,
      avgElevationM: 40,
      avgSlopeDeg: 4,
      terrainNote: 'Coastal midland, Chaliyar/Korapuzha basins',
      baseRiskScore: 48,
      avgAnnualRainfallMm: 3050,
    ),
    KeralaDistrict(
      name: 'Wayanad',
      lat: 11.68,
      lon: 76.13,
      avgElevationM: 950,
      avgSlopeDeg: 22,
      terrainNote: 'Western Ghats plateau, landslide-prone slopes',
      baseRiskScore: 56,
      avgAnnualRainfallMm: 2900,
    ),
    KeralaDistrict(
      name: 'Kannur',
      lat: 11.87,
      lon: 75.37,
      avgElevationM: 35,
      avgSlopeDeg: 4,
      terrainNote: 'Coastal, Valapattanam river basin',
      baseRiskScore: 40,
      avgAnnualRainfallMm: 3400,
    ),
    KeralaDistrict(
      name: 'Kasaragod',
      lat: 12.49,
      lon: 74.98,
      avgElevationM: 50,
      avgSlopeDeg: 5,
      terrainNote: 'Coastal, laterite midlands',
      baseRiskScore: 36,
      avgAnnualRainfallMm: 3700,
    ),
  ];

  static const List<String> names = [
    'Thiruvananthapuram',
    'Kollam',
    'Pathanamthitta',
    'Alappuzha',
    'Kottayam',
    'Idukki',
    'Ernakulam',
    'Thrissur',
    'Palakkad',
    'Malappuram',
    'Kozhikode',
    'Wayanad',
    'Kannur',
    'Kasaragod',
  ];

  static KeralaDistrict get defaultDistrict => byName(defaultName);

  static KeralaDistrict byName(String name) =>
      all.firstWhere((d) => d.name.toLowerCase() == name.toLowerCase(), orElse: () => all.first);

  /// Nearest district to a GPS fix, by straight-line distance to each
  /// district's center point — used to turn a raw lat/lng into a district
  /// the risk model/UI already understands (mirrors the same haversine
  /// approach `dio_preciops_api.dart` uses privately for shelter/task
  /// district lookups).
  static KeralaDistrict nearest(double lat, double lng) {
    const distance = Distance();
    final point = LatLng(lat, lng);
    var closest = all.first;
    var best = double.infinity;
    for (final d in all) {
      final km = distance.as(LengthUnit.Kilometer, point, d.center);
      if (km < best) {
        best = km;
        closest = d;
      }
    }
    return closest;
  }
}
