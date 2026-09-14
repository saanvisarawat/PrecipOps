enum DutyStatus { available, offline }

extension DutyStatusX on DutyStatus {
  String get wire => this == DutyStatus.available ? 'available' : 'offline';
}

enum VolunteerSkill { medical, boatRescue, logistics, communications, firstResponder }

extension VolunteerSkillX on VolunteerSkill {
  String get wire => switch (this) {
        VolunteerSkill.medical => 'medical',
        VolunteerSkill.boatRescue => 'boat_rescue',
        VolunteerSkill.logistics => 'logistics',
        VolunteerSkill.communications => 'communications',
        VolunteerSkill.firstResponder => 'first_responder',
      };

  String get label => switch (this) {
        VolunteerSkill.medical => 'Medical',
        VolunteerSkill.boatRescue => 'Boat Rescue',
        VolunteerSkill.logistics => 'Logistics',
        VolunteerSkill.communications => 'Communications',
        VolunteerSkill.firstResponder => 'First Responder',
      };
}

class VolunteerLocationUpdate {
  final DutyStatus status;
  final List<VolunteerSkill> skills;
  final double latitude;
  final double longitude;

  const VolunteerLocationUpdate({
    required this.status,
    required this.skills,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'status': status.wire,
        'skills': skills.map((s) => s.wire).toList(),
        'latitude': latitude,
        'longitude': longitude,
      };
}

enum TaskPriority { low, medium, high, critical }

extension TaskPriorityX on TaskPriority {
  static TaskPriority fromWire(String value) => switch (value) {
        'medium' => TaskPriority.medium,
        'high' => TaskPriority.high,
        'critical' => TaskPriority.critical,
        _ => TaskPriority.low,
      };

  String get label => switch (this) {
        TaskPriority.low => 'Low',
        TaskPriority.medium => 'Medium',
        TaskPriority.high => 'High',
        TaskPriority.critical => 'Critical',
      };
}

enum TaskStatus { assigned, enRoute, completed }

extension TaskStatusX on TaskStatus {
  // Real Report.status writes "en-route" (hyphen); the mock and this
  // app's original guessed contract use "en_route" (underscore) — both
  // accepted here so either backend's value round-trips correctly.
  static TaskStatus fromWire(String value) => switch (value) {
        'en_route' || 'en-route' => TaskStatus.enRoute,
        'completed' => TaskStatus.completed,
        _ => TaskStatus.assigned,
      };

  String get label => switch (this) {
        TaskStatus.assigned => 'Assigned',
        TaskStatus.enRoute => 'En Route',
        TaskStatus.completed => 'Completed',
      };
}

class VolunteerTask {
  final String taskId;
  final String sosTicketId;
  final String district;
  final double latitude;
  final double longitude;
  final String description;
  final TaskPriority priority;
  final TaskStatus status;
  final DateTime assignedAt;
  final double distanceKm;

  const VolunteerTask({
    required this.taskId,
    required this.sosTicketId,
    required this.district,
    required this.latitude,
    required this.longitude,
    required this.description,
    required this.priority,
    required this.status,
    required this.assignedAt,
    required this.distanceKm,
  });

  factory VolunteerTask.fromJson(Map<String, dynamic> json) => VolunteerTask(
        taskId: json['task_id'] as String,
        sosTicketId: json['sos_ticket_id'] as String,
        district: json['district'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        description: json['description'] as String,
        priority: TaskPriorityX.fromWire(json['priority'] as String),
        status: TaskStatusX.fromWire(json['status'] as String),
        assignedAt: DateTime.parse(json['assigned_at'] as String),
        distanceKm: (json['distance_km'] as num).toDouble(),
      );
}

/// Live position of the volunteer dispatched to a specific citizen's
/// ticket, once they've accepted the task — polled by the citizen
/// dashboard while a ticket has an en-route volunteer so the citizen can
/// watch them approach on the map.
class VolunteerLocationSnapshot {
  final String? volunteerName;
  final double latitude;
  final double longitude;

  const VolunteerLocationSnapshot({
    this.volunteerName,
    required this.latitude,
    required this.longitude,
  });

  factory VolunteerLocationSnapshot.fromJson(Map<String, dynamic> json) => VolunteerLocationSnapshot(
        volunteerName: json['volunteer_name'] as String?,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );
}

/// Mirrors the data payload of an FCM push with
/// `type: "EMERGENCY_INCOMING_CALL"`. In this build it is produced by a
/// debug trigger instead of a real push, but the shape matches what a
/// real FCM data message would carry so the masked-call screen needs no
/// changes once push is wired up.
class MaskedCallPayload {
  final String sosId;
  final String callerAlias;
  final String riskBadge;
  final String district;
  final double latitude;
  final double longitude;

  const MaskedCallPayload({
    required this.sosId,
    required this.callerAlias,
    required this.riskBadge,
    required this.district,
    required this.latitude,
    required this.longitude,
  });

  /// The real backend's FCM data payload (POST /api/emergency/trigger-masked-call)
  /// sends `caller_name`/`handle_label`/`zone_label`/`risk_level` and no
  /// lat/lng at all — different keys from this app's original guessed
  /// contract. Parsed leniently here so a real FCM handler can call this
  /// directly once push is wired up.
  factory MaskedCallPayload.fromJson(Map<String, dynamic> json) => MaskedCallPayload(
        sosId: json['sos_id'] as String,
        callerAlias: (json['caller_name'] ?? json['caller_alias'] ?? 'Unknown caller') as String,
        riskBadge: (json['risk_level'] ?? json['risk_badge'] ?? 'CRITICAL') as String,
        district: (json['zone_label'] ?? json['district'] ?? '') as String,
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      );
}
