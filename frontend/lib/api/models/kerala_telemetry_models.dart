/// POST /api/ml/predict-kerala — live Kerala telemetry, synthesized
/// server-side from Open-Meteo via Marshall-Palmer (radar) and cloud-cover
/// mapping (satellite). Distinct from [InundationSimulationResponse]'s
/// `meteorological_inputs`, which is scenario-fixed (NORMAL/EXTREME_EVENT)
/// rather than per-district live data — this is the real 4-Pillar HUD feed.
class KeralaSatellitePillar {
  final String sensor;
  final double cloudTopTempC;
  final double cloudCoverPct;
  final bool convectiveCloudburstDetected;

  const KeralaSatellitePillar({
    required this.sensor,
    required this.cloudTopTempC,
    required this.cloudCoverPct,
    required this.convectiveCloudburstDetected,
  });

  factory KeralaSatellitePillar.fromJson(Map<String, dynamic> json) => KeralaSatellitePillar(
        sensor: json['sensor'] as String? ?? 'TIR-1 Thermal Infrared',
        cloudTopTempC: (json['cloud_top_temp_c'] as num?)?.toDouble() ?? 0,
        cloudCoverPct: (json['cloud_cover_pct'] as num?)?.toDouble() ?? 0,
        convectiveCloudburstDetected: json['convective_cloudburst_detected'] as bool? ?? false,
      );
}

class KeralaRadarPillar {
  final String band;
  final double reflectivityDbz;
  final String echoIntensity;

  const KeralaRadarPillar({required this.band, required this.reflectivityDbz, required this.echoIntensity});

  factory KeralaRadarPillar.fromJson(Map<String, dynamic> json) => KeralaRadarPillar(
        band: json['band'] as String? ?? 'S-band / C-band Pulse Doppler',
        reflectivityDbz: (json['reflectivity_dbz'] as num?)?.toDouble() ?? 0,
        echoIntensity: json['echo_intensity'] as String? ?? 'LOW',
      );
}

class KeralaAwsPillar {
  final String source;
  final double currentRainRateMmh;
  final double temperatureC;
  final double humidityPct;

  const KeralaAwsPillar({
    required this.source,
    required this.currentRainRateMmh,
    required this.temperatureC,
    required this.humidityPct,
  });

  factory KeralaAwsPillar.fromJson(Map<String, dynamic> json) => KeralaAwsPillar(
        source: json['source'] as String? ?? 'IMD Ground Station Telemetry',
        currentRainRateMmh: (json['current_rain_rate_mmh'] as num?)?.toDouble() ?? 0,
        temperatureC: (json['temperature_c'] as num?)?.toDouble() ?? 0,
        humidityPct: (json['humidity_pct'] as num?)?.toDouble() ?? 0,
      );
}

class KeralaNwpPillar {
  final String model;
  final double forecast72hAccumMm;

  const KeralaNwpPillar({required this.model, required this.forecast72hAccumMm});

  factory KeralaNwpPillar.fromJson(Map<String, dynamic> json) => KeralaNwpPillar(
        model: json['model'] as String? ?? 'WRF-NCMRWF High-Res Dynamic Core',
        forecast72hAccumMm: (json['forecast_72h_accum_mm'] as num?)?.toDouble() ?? 0,
      );
}

class KeralaTelemetryPillars {
  final KeralaSatellitePillar satelliteInsat3dr;
  final KeralaRadarPillar radarDwr;
  final KeralaAwsPillar observationalAws;
  final KeralaNwpPillar nwpForecast;

  const KeralaTelemetryPillars({
    required this.satelliteInsat3dr,
    required this.radarDwr,
    required this.observationalAws,
    required this.nwpForecast,
  });

  factory KeralaTelemetryPillars.fromJson(Map<String, dynamic> json) => KeralaTelemetryPillars(
        satelliteInsat3dr:
            KeralaSatellitePillar.fromJson((json['satellite_insat3dr'] as Map<String, dynamic>?) ?? const {}),
        radarDwr: KeralaRadarPillar.fromJson((json['radar_dwr'] as Map<String, dynamic>?) ?? const {}),
        observationalAws:
            KeralaAwsPillar.fromJson((json['observational_aws'] as Map<String, dynamic>?) ?? const {}),
        nwpForecast: KeralaNwpPillar.fromJson((json['nwp_forecast'] as Map<String, dynamic>?) ?? const {}),
      );
}

/// POST /api/ml/predict-kerala response.
class KeralaPredictionResponse {
  final String district;
  final double latitude;
  final double longitude;
  final int floodRiskScore;
  final double riskProbability;
  final String riskLevel;
  final bool isHighRisk;
  final List<String> topFactors;
  final KeralaTelemetryPillars telemetryPillars;

  const KeralaPredictionResponse({
    required this.district,
    required this.latitude,
    required this.longitude,
    required this.floodRiskScore,
    required this.riskProbability,
    required this.riskLevel,
    required this.isHighRisk,
    required this.topFactors,
    required this.telemetryPillars,
  });

  factory KeralaPredictionResponse.fromJson(Map<String, dynamic> json) => KeralaPredictionResponse(
        district: json['district'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        floodRiskScore: (json['flood_risk_score'] as num?)?.toInt() ?? 0,
        riskProbability: (json['risk_probability'] as num?)?.toDouble() ?? 0,
        riskLevel: (json['risk_level'] as String? ?? 'NORMAL').toUpperCase(),
        isHighRisk: json['is_high_risk'] as bool? ?? false,
        topFactors: (json['top_factors'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        telemetryPillars:
            KeralaTelemetryPillars.fromJson((json['telemetry_pillars'] as Map<String, dynamic>?) ?? const {}),
      );
}
