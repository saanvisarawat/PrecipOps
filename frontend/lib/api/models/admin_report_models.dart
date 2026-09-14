/// Mirrors GET /api/officials/reports — every citizen report regardless of
/// status (pending/dispatched/verified/false_alarm), for the official SOS
/// dashboard. Distinct from [ReportSummary] (GET /api/reports), which only
/// ever returns status=="verified" rows and uses different wire field names.
class AdminReport {
  final int id;
  final String description;
  final double latitude;
  final double longitude;
  final String status;
  final int yesCount;
  final int noCount;
  final DateTime? clientTimestamp;
  final int? assignedVolunteerId;
  final String? assignedVolunteerName;

  const AdminReport({
    required this.id,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.yesCount,
    required this.noCount,
    this.clientTimestamp,
    this.assignedVolunteerId,
    this.assignedVolunteerName,
  });

  bool get isAssigned => assignedVolunteerId != null;

  AdminReport copyWith({
    String? status,
    int? assignedVolunteerId,
    String? assignedVolunteerName,
  }) =>
      AdminReport(
        id: id,
        description: description,
        latitude: latitude,
        longitude: longitude,
        status: status ?? this.status,
        yesCount: yesCount,
        noCount: noCount,
        clientTimestamp: clientTimestamp,
        assignedVolunteerId: assignedVolunteerId ?? this.assignedVolunteerId,
        assignedVolunteerName: assignedVolunteerName ?? this.assignedVolunteerName,
      );

  factory AdminReport.fromJson(Map<String, dynamic> json) => AdminReport(
        id: json['id'] as int,
        description: json['description'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        status: json['status'] as String? ?? 'pending',
        yesCount: json['yes_count'] as int? ?? 0,
        noCount: json['no_count'] as int? ?? 0,
        clientTimestamp: json['client_timestamp'] != null ? DateTime.tryParse(json['client_timestamp'] as String) : null,
        assignedVolunteerId: json['assigned_volunteer_id'] as int?,
        assignedVolunteerName: json['assigned_volunteer_name'] as String?,
      );
}

/// Mirrors GET /api/officials/volunteers — used to populate the "assign to"
/// picker on the official SOS dashboard.
class AdminVolunteer {
  final int id;
  final String fullName;
  final String status;
  final String? skills;
  final double? latitude;
  final double? longitude;

  const AdminVolunteer({
    required this.id,
    required this.fullName,
    required this.status,
    this.skills,
    this.latitude,
    this.longitude,
  });

  bool get isAvailable => status == 'available';

  factory AdminVolunteer.fromJson(Map<String, dynamic> json) => AdminVolunteer(
        id: json['id'] as int,
        fullName: json['full_name'] as String,
        status: json['status'] as String? ?? 'offline',
        skills: json['skills'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );
}
