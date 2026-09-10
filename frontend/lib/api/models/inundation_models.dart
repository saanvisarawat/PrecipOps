import 'package:latlong2/latlong.dart';

/// Standard ray-casting point-in-polygon test — used to decide whether a
/// citizen's live GPS fix falls inside an active inundation zone (drives
/// the Citizen Dashboard's EVACUATE state).
bool pointInPolygon(LatLng point, List<LatLng> ring) {
  if (ring.length < 3) return false;
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i].longitude, yi = ring[i].latitude;
    final xj = ring[j].longitude, yj = ring[j].latitude;
    final intersects = ((yi > point.latitude) != (yj > point.latitude)) &&
        (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
    if (intersects) inside = !inside;
  }
  return inside;
}

/// Parses a GeoJSON `Polygon`'s outer ring into the `LatLng` list
/// `flutter_map`'s `Polygon` widget wants. GeoJSON coordinates are
/// `[lon, lat]` pairs — this flips them to the `LatLng(lat, lon)` order
/// every other map widget in this app already uses.
List<LatLng> parseGeoJsonPolygonRing(Map<String, dynamic> geojson) {
  final coordinates = geojson['coordinates'] as List?;
  if (coordinates == null || coordinates.isEmpty) return const [];
  final ring = coordinates.first as List;
  return ring.map((pt) {
    final p = pt as List;
    final lon = (p[0] as num).toDouble();
    final lat = (p[1] as num).toDouble();
    return LatLng(lat, lon);
  }).toList();
}

/// The 4-Pillar HUD: Satellite (INSAT-3DR), Doppler Radar (DWR), Ground AWS
/// (IMD), NWP Model (NCMRWF) — flattened from the backend's nested
/// `meteorological_inputs` object.
class FourPillarTelemetry {
  final String satelliteSource;
  final double cloudTopTempKelvin;
  final double satelliteRainRateMmHr;

  final String radarStation;
  final double radarReflectivityDbz;
  final double radarEchoTopKm;

  final String awsStationId;
  final double awsRainRateMmHr;
  final double awsCumulative24hMm;

  final String nwpModelName;
  final int nwpLeadTimeHours;
  final double nwpPredictedPrecipMm;

  const FourPillarTelemetry({
    required this.satelliteSource,
    required this.cloudTopTempKelvin,
    required this.satelliteRainRateMmHr,
    required this.radarStation,
    required this.radarReflectivityDbz,
    required this.radarEchoTopKm,
    required this.awsStationId,
    required this.awsRainRateMmHr,
    required this.awsCumulative24hMm,
    required this.nwpModelName,
    required this.nwpLeadTimeHours,
    required this.nwpPredictedPrecipMm,
  });

  factory FourPillarTelemetry.fromJson(Map<String, dynamic> json) {
    final satellite = (json['satellite'] as Map<String, dynamic>?) ?? const {};
    final radar = (json['radar'] as Map<String, dynamic>?) ?? const {};
    final aws = (json['observational_weather'] as Map<String, dynamic>?) ?? const {};
    final nwp = (json['numerical_weather_prediction'] as Map<String, dynamic>?) ?? const {};
    return FourPillarTelemetry(
      satelliteSource: satellite['source'] as String? ?? 'INSAT-3DR',
      cloudTopTempKelvin: (satellite['cloud_top_temp_kelvin'] as num?)?.toDouble() ?? 0,
      satelliteRainRateMmHr: (satellite['rainfall_hydro_estimator_mm_hr'] as num?)?.toDouble() ?? 0,
      radarStation: radar['station'] as String? ?? 'DWR',
      radarReflectivityDbz: (radar['reflectivity_dbz'] as num?)?.toDouble() ?? 0,
      radarEchoTopKm: (radar['echo_top_km'] as num?)?.toDouble() ?? 0,
      awsStationId: aws['station_id'] as String? ?? 'IMD-AWS',
      awsRainRateMmHr: (aws['current_rainfall_mm_hr'] as num?)?.toDouble() ?? 0,
      awsCumulative24hMm: (aws['cumulative_24h_rainfall_mm'] as num?)?.toDouble() ?? 0,
      nwpModelName: nwp['model_name'] as String? ?? 'NCMRWF',
      nwpLeadTimeHours: (nwp['forecast_lead_time_hours'] as num?)?.toInt() ?? 6,
      nwpPredictedPrecipMm: (nwp['predicted_precipitation_mm'] as num?)?.toDouble() ?? 0,
    );
  }
}

class InundationFrame {
  final String timeStep;
  final double waterDepthMeters;
  final double radarDbz;
  final double satelliteRainRateMmHr;
  final String severity;
  final List<String> affectedLandmarks;
  final Map<String, dynamic> geojsonGeometry;

  const InundationFrame({
    required this.timeStep,
    required this.waterDepthMeters,
    required this.radarDbz,
    required this.satelliteRainRateMmHr,
    required this.severity,
    required this.affectedLandmarks,
    required this.geojsonGeometry,
  });

  List<LatLng> get polygonRing => parseGeoJsonPolygonRing(geojsonGeometry);

  factory InundationFrame.fromJson(Map<String, dynamic> json) => InundationFrame(
        timeStep: json['time_step'] as String? ?? '',
        waterDepthMeters: (json['water_depth_meters'] as num?)?.toDouble() ?? 0,
        radarDbz: (json['radar_dbz'] as num?)?.toDouble() ?? 0,
        satelliteRainRateMmHr: (json['satellite_rain_rate_mm_hr'] as num?)?.toDouble() ?? 0,
        severity: json['severity'] as String? ?? 'LOW',
        affectedLandmarks: (json['affected_landmarks'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        geojsonGeometry: (json['geojson_geometry'] as Map<String, dynamic>?) ?? const {},
      );
}

class InundationPolygon {
  final String zoneId;
  final String severity;
  final double avgWaterDepthMeters;
  final List<String> affectedLandmarks;
  final Map<String, dynamic> geojsonGeometry;

  const InundationPolygon({
    required this.zoneId,
    required this.severity,
    required this.avgWaterDepthMeters,
    required this.affectedLandmarks,
    required this.geojsonGeometry,
  });

  List<LatLng> get polygonRing => parseGeoJsonPolygonRing(geojsonGeometry);

  factory InundationPolygon.fromJson(Map<String, dynamic> json) => InundationPolygon(
        zoneId: json['zone_id'] as String? ?? '',
        severity: json['severity'] as String? ?? 'LOW',
        avgWaterDepthMeters: (json['avg_water_depth_meters'] as num?)?.toDouble() ?? 0,
        affectedLandmarks: (json['affected_landmarks'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        geojsonGeometry: (json['geojson_geometry'] as Map<String, dynamic>?) ?? const {},
      );
}

/// GET /api/v1/inundation/simulate — the Predictor Dashboard's primary feed.
class InundationSimulationResponse {
  final String timestamp;
  final String district;
  final String leadTimeWarning;
  final String alertLevel; // RED, ORANGE, YELLOW, GREEN
  final FourPillarTelemetry telemetry;
  final List<InundationPolygon> inundationZones;
  final List<InundationFrame> simulationFrames;
  final String advisoryBulletin;

  const InundationSimulationResponse({
    required this.timestamp,
    required this.district,
    required this.leadTimeWarning,
    required this.alertLevel,
    required this.telemetry,
    required this.inundationZones,
    required this.simulationFrames,
    required this.advisoryBulletin,
  });

  factory InundationSimulationResponse.fromJson(Map<String, dynamic> json) => InundationSimulationResponse(
        timestamp: json['timestamp'] as String? ?? '',
        district: json['district'] as String? ?? '',
        leadTimeWarning: json['lead_time_warning'] as String? ?? '',
        alertLevel: (json['alert_level'] as String? ?? 'GREEN').toUpperCase(),
        telemetry: FourPillarTelemetry.fromJson((json['meteorological_inputs'] as Map<String, dynamic>?) ?? const {}),
        inundationZones: (json['inundation_zones'] as List?)
                ?.map((e) => InundationPolygon.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        simulationFrames: (json['simulation_frames'] as List?)
                ?.map((e) => InundationFrame.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        advisoryBulletin: json['advisory_bulletin'] as String? ?? '',
      );
}

class BlockedBoundingBox {
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
  final String description;

  const BlockedBoundingBox({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    required this.description,
  });

  bool contains(double lat, double lon) => lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;

  factory BlockedBoundingBox.fromJson(Map<String, dynamic> json) => BlockedBoundingBox(
        minLat: (json['min_lat'] as num).toDouble(),
        maxLat: (json['max_lat'] as num).toDouble(),
        minLon: (json['min_lon'] as num).toDouble(),
        maxLon: (json['max_lon'] as num).toDouble(),
        description: json['description'] as String? ?? '',
      );
}

/// GET /api/v1/routing/blocked-nodes — impassable street bounding boxes for
/// the offline Dijkstra evacuation router (Responder + Citizen routing).
class BlockedNodesResponse {
  final String zoneId;
  final List<BlockedBoundingBox> blockedBoundingBoxes;
  final String action;

  const BlockedNodesResponse({required this.zoneId, required this.blockedBoundingBoxes, required this.action});

  factory BlockedNodesResponse.fromJson(Map<String, dynamic> json) => BlockedNodesResponse(
        zoneId: json['zone_id'] as String? ?? '',
        blockedBoundingBoxes: (json['blocked_bounding_boxes'] as List?)
                ?.map((e) => BlockedBoundingBox.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        action: json['action'] as String? ?? '',
      );
}

/// GET /api/v1/agents/protocol — RAG-generated NDMA response checklist for
/// the Responder Dashboard.
class NdmaProtocolResponse {
  final String district;
  final String alertLevel;
  final String ragKnowledgeSource;
  final String meteorologicalTriggerSummary;
  final List<String> actionableChecklist;
  final String evacuationPriority;

  const NdmaProtocolResponse({
    required this.district,
    required this.alertLevel,
    required this.ragKnowledgeSource,
    required this.meteorologicalTriggerSummary,
    required this.actionableChecklist,
    required this.evacuationPriority,
  });

  factory NdmaProtocolResponse.fromJson(Map<String, dynamic> json) => NdmaProtocolResponse(
        district: json['district'] as String? ?? '',
        alertLevel: (json['alert_level'] as String? ?? 'GREEN').toUpperCase(),
        ragKnowledgeSource: json['rag_knowledge_source'] as String? ?? '',
        meteorologicalTriggerSummary: json['meteorological_trigger_summary'] as String? ?? '',
        actionableChecklist: (json['actionable_checklist'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        evacuationPriority: json['evacuation_priority'] as String? ?? '',
      );
}

class HistoricalStormBenchmark {
  final String eventName;
  final int year;
  final double peakRainfallMmHr;
  final double maxRadarDbz;
  final List<double> hourlyTrend;

  const HistoricalStormBenchmark({
    required this.eventName,
    required this.year,
    required this.peakRainfallMmHr,
    required this.maxRadarDbz,
    required this.hourlyTrend,
  });

  factory HistoricalStormBenchmark.fromJson(Map<String, dynamic> json) => HistoricalStormBenchmark(
        eventName: json['event_name'] as String? ?? '',
        year: (json['year'] as num?)?.toInt() ?? 0,
        peakRainfallMmHr: (json['peak_rainfall_mm_hr'] as num?)?.toDouble() ?? 0,
        maxRadarDbz: (json['max_radar_dbz'] as num?)?.toDouble() ?? 0,
        hourlyTrend: (json['hourly_trend'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? const [],
      );
}

/// GET /api/v1/analytics/storm-comparison — comparative storm analytics for
/// the Responder Dashboard's chart.
class StormComparisonResponse {
  final String district;
  final String currentStormName;
  final double currentPeakRainfallMmHr;
  final double currentMaxRadarDbz;
  final List<double> currentHourlyTrend;
  final List<HistoricalStormBenchmark> historicalBenchmarks;

  const StormComparisonResponse({
    required this.district,
    required this.currentStormName,
    required this.currentPeakRainfallMmHr,
    required this.currentMaxRadarDbz,
    required this.currentHourlyTrend,
    required this.historicalBenchmarks,
  });

  factory StormComparisonResponse.fromJson(Map<String, dynamic> json) => StormComparisonResponse(
        district: json['district'] as String? ?? '',
        currentStormName: json['current_storm_name'] as String? ?? '',
        currentPeakRainfallMmHr: (json['current_peak_rainfall_mm_hr'] as num?)?.toDouble() ?? 0,
        currentMaxRadarDbz: (json['current_max_radar_dbz'] as num?)?.toDouble() ?? 0,
        currentHourlyTrend: (json['current_hourly_trend'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? const [],
        historicalBenchmarks: (json['historical_benchmarks'] as List?)
                ?.map((e) => HistoricalStormBenchmark.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

/// POST /api/v1/citizen/broadcast — emergency SMS fallback broadcast.
class SmsBroadcastResult {
  final String status;
  final String broadcastTimestamp;
  final String targetedDistrict;
  final int simulatedSmsRecipientsCount;
  final List<String> sampleRecipients;
  final String fallbackMode;

  const SmsBroadcastResult({
    required this.status,
    required this.broadcastTimestamp,
    required this.targetedDistrict,
    required this.simulatedSmsRecipientsCount,
    required this.sampleRecipients,
    required this.fallbackMode,
  });

  factory SmsBroadcastResult.fromJson(Map<String, dynamic> json) => SmsBroadcastResult(
        status: json['status'] as String? ?? '',
        broadcastTimestamp: json['broadcast_timestamp'] as String? ?? '',
        targetedDistrict: json['targeted_district'] as String? ?? '',
        simulatedSmsRecipientsCount: (json['simulated_sms_recipients_count'] as num?)?.toInt() ?? 0,
        sampleRecipients: (json['sample_recipients'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        fallbackMode: json['fallback_mode'] as String? ?? '',
      );
}

/// POST /api/v1/citizen/verification/upload — citizen ground-truth report.
class GroundTruthReportResult {
  final String status;
  final String reportId;
  final String receivedTimestamp;
  final String message;

  const GroundTruthReportResult({
    required this.status,
    required this.reportId,
    required this.receivedTimestamp,
    required this.message,
  });

  factory GroundTruthReportResult.fromJson(Map<String, dynamic> json) => GroundTruthReportResult(
        status: json['status'] as String? ?? '',
        reportId: json['report_id'] as String? ?? '',
        receivedTimestamp: json['received_timestamp'] as String? ?? '',
        message: json['message'] as String? ?? '',
      );
}
