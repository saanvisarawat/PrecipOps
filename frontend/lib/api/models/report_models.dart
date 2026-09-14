enum ReportStatus { pending, verified, falseAlarm }

extension ReportStatusX on ReportStatus {
  String get wire => switch (this) {
        ReportStatus.pending => 'pending',
        ReportStatus.verified => 'verified',
        ReportStatus.falseAlarm => 'false_alarm',
      };

  static ReportStatus fromWire(String value) => switch (value) {
        'verified' => ReportStatus.verified,
        'false_alarm' => ReportStatus.falseAlarm,
        _ => ReportStatus.pending,
      };
}

/// Payload used both for a live online submission and for a queued
/// offline-sync submission (via [clientId] / [clientTimestamp]).
class CreateReportRequest {
  final String clientId;
  final String description;
  final double latitude;
  final double longitude;
  final DateTime clientTimestamp;

  const CreateReportRequest({
    required this.clientId,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.clientTimestamp,
  });

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'client_timestamp': clientTimestamp.toIso8601String(),
      };

  factory CreateReportRequest.fromJson(Map<String, dynamic> json) => CreateReportRequest(
        clientId: json['client_id'] as String,
        description: json['description'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        clientTimestamp: DateTime.parse(json['client_timestamp'] as String),
      );
}

class ReportSummary {
  final String ticketId;
  final String description;
  final double latitude;
  final double longitude;
  final double distanceMeters;
  final int confirmCount;
  final int falseAlarmCount;
  final ReportStatus status;
  final DateTime reportedAt;
  final String? reporterAlias;
  final String? assignedVolunteerId;

  const ReportSummary({
    required this.ticketId,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.confirmCount,
    required this.falseAlarmCount,
    required this.status,
    required this.reportedAt,
    this.reporterAlias,
    this.assignedVolunteerId,
  });

  ReportSummary copyWith({
    int? confirmCount,
    int? falseAlarmCount,
    ReportStatus? status,
    String? assignedVolunteerId,
  }) =>
      ReportSummary(
        ticketId: ticketId,
        description: description,
        latitude: latitude,
        longitude: longitude,
        distanceMeters: distanceMeters,
        confirmCount: confirmCount ?? this.confirmCount,
        falseAlarmCount: falseAlarmCount ?? this.falseAlarmCount,
        status: status ?? this.status,
        reportedAt: reportedAt,
        reporterAlias: reporterAlias,
        assignedVolunteerId: assignedVolunteerId ?? this.assignedVolunteerId,
      );

  factory ReportSummary.fromJson(Map<String, dynamic> json) => ReportSummary(
        ticketId: json['ticket_id'] as String,
        description: json['description'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        distanceMeters: (json['distance_meters'] as num).toDouble(),
        confirmCount: json['confirm_count'] as int,
        falseAlarmCount: json['false_alarm_count'] as int,
        status: ReportStatusX.fromWire(json['status'] as String),
        reportedAt: DateTime.parse(json['reported_at'] as String),
        reporterAlias: json['reporter_alias'] as String?,
        assignedVolunteerId: json['assigned_volunteer_id']?.toString(),
      );
}

enum VerifyVote { confirm, falseAlarm }

class BulkSyncResult {
  final List<String> syncedClientIds;
  final List<String> duplicateClientIds;

  const BulkSyncResult({required this.syncedClientIds, required this.duplicateClientIds});
}
