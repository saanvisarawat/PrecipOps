import 'package:flutter_test/flutter_test.dart';
import 'package:preciops_frontend/api/models/chat_models.dart';
import 'package:preciops_frontend/api/models/kerala_telemetry_models.dart';

void main() {
  group('KeralaPredictionResponse.fromJson', () {
    test('parses the exact shape POST /api/ml/predict-kerala returns', () {
      // Mirrors app/main.py's predict_kerala_flood() response literal and
      // app/data_ingestion.py's derive_four_pillars() output exactly.
      final json = {
        'status': 'success',
        'district': 'Wayanad',
        'latitude': 11.68,
        'longitude': 76.13,
        'flood_risk_score': 12,
        'risk_probability': 0.12,
        'risk_level': 'NORMAL',
        'is_high_risk': false,
        'top_factors': ['INSAT-3DR Topography (Satellite)', 'Doppler Weather Radar (Streamflow)'],
        'telemetry_pillars': {
          'satellite_insat3dr': {
            'sensor': 'TIR-1 Thermal Infrared',
            'cloud_top_temp_c': -8.4,
            'cloud_cover_pct': 94.0,
            'convective_cloudburst_detected': false,
          },
          'radar_dwr': {
            'band': 'S-band / C-band Pulse Doppler',
            'reflectivity_dbz': 33.2,
            'echo_intensity': 'MODERATE',
          },
          'observational_aws': {
            'source': 'IMD Ground Station Telemetry',
            'current_rain_rate_mmh': 24.0,
            'temperature_c': 21.0,
            'humidity_pct': 93.0,
          },
          'nwp_forecast': {
            'model': 'WRF-NCMRWF High-Res Dynamic Core',
            'forecast_72h_accum_mm': 230.0,
          },
        },
      };

      final result = KeralaPredictionResponse.fromJson(json);

      expect(result.district, 'Wayanad');
      expect(result.latitude, 11.68);
      expect(result.longitude, 76.13);
      expect(result.floodRiskScore, 12);
      expect(result.riskLevel, 'NORMAL');
      expect(result.isHighRisk, false);
      expect(result.topFactors, ['INSAT-3DR Topography (Satellite)', 'Doppler Weather Radar (Streamflow)']);

      // The exact field paths the 4-Pillar HUD binds to.
      expect(result.telemetryPillars.radarDwr.reflectivityDbz, 33.2);
      expect(result.telemetryPillars.satelliteInsat3dr.cloudTopTempC, -8.4);
      expect(result.telemetryPillars.satelliteInsat3dr.cloudCoverPct, 94.0);
    });

    test('tolerates a missing telemetry_pillars key without throwing', () {
      final result = KeralaPredictionResponse.fromJson({'district': 'Ernakulam'});
      expect(result.telemetryPillars.radarDwr.reflectivityDbz, 0);
      expect(result.topFactors, isEmpty);
    });
  });

  group('ChatRequest.toJson', () {
    test('sends language: malayalam when the toggle is set', () {
      final json = const ChatRequest(
        message: 'What do I do if trapped by rising water?',
        sessionId: 'session-1',
        language: ChatLanguage.malayalam,
      ).toJson();

      expect(json['language'], 'malayalam');
      expect(json['message'], 'What do I do if trapped by rising water?');
      expect(json['session_id'], 'session-1');
    });

    test('defaults to english when no language is passed', () {
      final json = const ChatRequest(message: 'hi', sessionId: 's').toJson();
      expect(json['language'], 'english');
    });
  });
}
