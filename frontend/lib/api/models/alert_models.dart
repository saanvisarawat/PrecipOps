/// Mirrors GET /api/alerts/pending on the real backend — a model-detected
/// high-risk transition (see the hourly flood-risk pipeline job in main.py) that's
/// waiting for a volunteer/official to approve or reject it. The actual
/// citizen-facing high_risk_alert push only fires on approval — see
/// POST /api/alerts/{id}/approve.
enum PendingAlertStatus { pending, approved, rejected }

extension PendingAlertStatusX on PendingAlertStatus {
  static PendingAlertStatus fromWire(String value) => switch (value) {
        'approved' => PendingAlertStatus.approved,
        'rejected' => PendingAlertStatus.rejected,
        _ => PendingAlertStatus.pending,
      };
}

class PendingAlert {
  final int id;
  final String district;
  final String alertLevel;
  final String message;
  final PendingAlertStatus status;
  final int? riskScore;
  final DateTime createdAt;

  const PendingAlert({
    required this.id,
    required this.district,
    required this.alertLevel,
    required this.message,
    required this.status,
    required this.riskScore,
    required this.createdAt,
  });

  factory PendingAlert.fromJson(Map<String, dynamic> json) => PendingAlert(
        id: json['id'] as int,
        district: json['district'] as String,
        alertLevel: json['alert_level'] as String,
        message: json['message'] as String,
        status: PendingAlertStatusX.fromWire(json['status'] as String? ?? 'pending'),
        riskScore: (json['risk_score'] as num?)?.toInt(),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}
