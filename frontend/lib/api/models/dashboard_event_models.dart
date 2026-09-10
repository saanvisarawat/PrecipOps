/// Events mirrored from the real backend's ws://<backend>/ws/dashboard
/// stream. In this build they're emitted by a local Stream/Timer
/// (see MockPreciopsApi.dashboardEventStream) instead of a real socket.
sealed class DashboardEvent {
  final DateTime timestamp;
  const DashboardEvent(this.timestamp);

  /// The real backend's `/ws/dashboard` broadcasts carry neither a
  /// `timestamp` field nor (on `sos_verified`) a `confirm_count`, and
  /// `new_sos_pending` has no `district` — all different from this app's
  /// original guessed contract. Missing fields fall back to a local
  /// timestamp / 0 / empty string rather than crashing the socket parse.
  factory DashboardEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final rawTs = json['timestamp'] as String?;
    final ts = rawTs == null ? DateTime.now() : (DateTime.tryParse(rawTs) ?? DateTime.now());
    return switch (type) {
      'sos_verified' => SosVerifiedEvent(
          ticketId: json['ticket_id'].toString(),
          confirmCount: (json['confirm_count'] as num?)?.toInt() ?? 0,
          timestamp: ts,
        ),
      // Fired by POST /api/officials/reports/{id}/assign — the manual
      // dispatch fallback for when allocate_resources_for_sos found nobody
      // available at creation time. That auto-assignment path doesn't need
      // this event: it's already reflected in new_sos_pending's own
      // assigned_volunteer_id, synchronously, in the same request that
      // filed the report.
      'volunteer_assigned' => VolunteerAssignedEvent(
          ticketId: json['ticket_id'].toString(),
          assignedVolunteerId: json['assigned_volunteer_id']?.toString(),
          assignedVolunteerName: json['assigned_volunteer_name'] as String?,
          timestamp: ts,
        ),
      'high_risk_alert' => HighRiskAlertEvent(
          district: json['district'] as String? ?? '',
          riskScore: (json['risk_score'] as num?)?.toInt() ?? 0,
          alertLevel: json['alert_level'] as String? ?? 'CRITICAL',
          timestamp: ts,
        ),
      _ => NewSosPendingEvent(
          ticketId: json['ticket_id'].toString(),
          latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
          longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
          description: json['description'] as String? ?? '',
          district: json['district'] as String? ?? '',
          assignedVolunteerId: json['assigned_volunteer_id']?.toString(),
          timestamp: ts,
        ),
    };
  }
}

class NewSosPendingEvent extends DashboardEvent {
  final String ticketId;
  final double latitude;
  final double longitude;
  final String description;
  final String district;
  final String? assignedVolunteerId;

  const NewSosPendingEvent({
    required this.ticketId,
    required this.latitude,
    required this.longitude,
    required this.description,
    required this.district,
    this.assignedVolunteerId,
    required DateTime timestamp,
  }) : super(timestamp);
}

/// A volunteer was manually dispatched to an already-filed report (the
/// official SOS dashboard's "Dispatch a Volunteer" action) — lets the
/// reporting citizen's own dashboard update the moment it happens, instead
/// of only ever knowing the allocation outcome from the instant their SOS
/// was first filed.
class VolunteerAssignedEvent extends DashboardEvent {
  final String ticketId;
  final String? assignedVolunteerId;
  final String? assignedVolunteerName;

  const VolunteerAssignedEvent({
    required this.ticketId,
    this.assignedVolunteerId,
    this.assignedVolunteerName,
    required DateTime timestamp,
  }) : super(timestamp);
}

class SosVerifiedEvent extends DashboardEvent {
  final String ticketId;
  final int confirmCount;

  const SosVerifiedEvent({
    required this.ticketId,
    required this.confirmCount,
    required DateTime timestamp,
  }) : super(timestamp);
}

/// The one event type that triggers a device push notification — fired only
/// by `the hourly flood-risk pipeline job`'s model-side risk check in `main.py`
/// (`is_high_risk` transitioning to true), never by a user/citizen action.
class HighRiskAlertEvent extends DashboardEvent {
  final String district;
  final int riskScore;
  final String alertLevel;

  const HighRiskAlertEvent({
    required this.district,
    required this.riskScore,
    required this.alertLevel,
    required DateTime timestamp,
  }) : super(timestamp);
}
