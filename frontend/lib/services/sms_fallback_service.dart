import 'package:url_launcher/url_launcher.dart';

/// Zero-connectivity SOS fallback. This is real, working device
/// functionality — no backend or mock is involved, it just opens the
/// OS's native SMS compose flow pre-filled with the SOS payload aimed at
/// the backend's Twilio webhook (POST /api/reports/sms-webhook), per
/// features.docx.
class SmsFallbackService {
  /// Destination number the backend's Twilio webhook is bound to. In a
  /// real deployment this comes from remote config; hardcoded here since
  /// there's no backend yet.
  static const String emergencySmsNumber = '+919999911111';

  String buildPayload({
    required double latitude,
    required double longitude,
    required String description,
  }) {
    return 'SOS $latitude $longitude $description';
  }

  Future<void> sendFallbackSms({
    required double latitude,
    required double longitude,
    required String description,
  }) async {
    final body = buildPayload(
      latitude: latitude,
      longitude: longitude,
      description: description,
    );

    final uri = Uri(
      scheme: 'sms',
      path: emergencySmsNumber,
      queryParameters: {'body': body},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
