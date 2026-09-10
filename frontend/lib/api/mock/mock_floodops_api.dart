import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../core/constants/national_metros.dart';
import '../floodops_api.dart';
import 'national_mock_data.dart';

/// Fully self-contained mock of the FastAPI backend described in
/// features.docx. Every method has a small artificial delay so loading
/// states are visible, and every response shape matches what the real
/// backend is expected to return (see API_CONTRACT.md). No screen should
/// ever see this class directly — they depend on [PreciopsApi].
class MockPreciopsApi implements PreciopsApi {
  MockPreciopsApi() {
    _reports.addAll(_seedReports());
  }

  final Random _rng = Random();
  final Uuid _uuid = const Uuid();

  final List<ReportSummary> _reports = [];
  ShelterFeatureCollection? _sheltersCache;

  final List<PendingAlert> _pendingAlerts = [
    PendingAlert(
      id: 1,
      district: 'Idukki',
      alertLevel: 'CRITICAL',
      message: 'Model-detected critical flood risk in Idukki (score 91).',
      status: PendingAlertStatus.pending,
      riskScore: 91,
      createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
    ),
  ];

  final List<AdminVolunteer> _adminVolunteers = [
    const AdminVolunteer(id: 101, fullName: 'Arjun Nair', status: 'available', skills: 'boat,medical', latitude: 9.9816, longitude: 76.2999),
    const AdminVolunteer(id: 102, fullName: 'Divya Menon', status: 'busy', skills: 'swimming', latitude: 10.0159, longitude: 76.3419),
    const AdminVolunteer(id: 103, fullName: 'Rahul Pillai', status: 'offline', skills: 'medical,boat', latitude: 9.4981, longitude: 76.3388),
  ];

  final List<AdminReport> _adminReports = [
    AdminReport(
      id: 501,
      description: 'Family of 4 stranded on rooftop, water rising fast.',
      latitude: 9.9312,
      longitude: 76.2673,
      status: 'pending',
      yesCount: 6,
      noCount: 0,
      clientTimestamp: DateTime.now().subtract(const Duration(minutes: 8)),
    ),
    AdminReport(
      id: 502,
      description: 'Elderly couple needs evacuation, no boat access by road.',
      latitude: 10.0159,
      longitude: 76.3419,
      status: 'dispatched',
      yesCount: 4,
      noCount: 1,
      clientTimestamp: DateTime.now().subtract(const Duration(minutes: 25)),
      assignedVolunteerId: 102,
      assignedVolunteerName: 'Divya Menon',
    ),
    AdminReport(
      id: 503,
      description: 'Road washed out near bridge, requesting alternate route info.',
      latitude: 9.4981,
      longitude: 76.3388,
      status: 'verified',
      yesCount: 11,
      noCount: 2,
      clientTimestamp: DateTime.now().subtract(const Duration(hours: 2)),
    ),
  ];

  final StreamController<MaskedCallPayload> _incomingCallController =
      StreamController<MaskedCallPayload>.broadcast();

  StreamController<DashboardEvent>? _dashboardController;
  Timer? _dashboardTimer;

  Future<void> _delay([int minMs = 400, int maxMs = 1100]) =>
      Future.delayed(Duration(milliseconds: minMs + _rng.nextInt(maxMs - minMs)));

  // ---------------------------------------------------------------------
  // 1. Auth & device onboarding
  // ---------------------------------------------------------------------

  @override
  Future<AuthResponse> register(RegisterRequest request) async {
    await _delay(600, 1400);
    final user = UserProfile(
      id: _uuid.v4(),
      fullName: request.fullName,
      email: request.email,
      role: request.role,
    );
    return AuthResponse(token: _fakeJwt(user), user: user);
  }

  @override
  Future<AuthResponse> login(LoginRequest request) async {
    await _delay(500, 1200);
    final namePart = request.email.split('@').first;
    final displayName = namePart
        .split(RegExp(r'[._]'))
        .map((s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}')
        .join(' ');
    final role = request.email.contains('official') ? UserRole.official : UserRole.volunteer;
    final user = UserProfile(
      id: _uuid.v4(),
      fullName: displayName.isEmpty ? 'Field Responder' : displayName,
      email: request.email,
      role: role,
    );
    return AuthResponse(token: _fakeJwt(user), user: user);
  }

  String _fakeJwt(UserProfile user) {
    final payload = '${user.id}.${user.role.wire}.${DateTime.now().millisecondsSinceEpoch}';
    return 'mock.$payload.jwt';
  }

  @override
  Future<void> registerFcmToken(String token) async {
    await _delay(150, 400);
  }

  // ---------------------------------------------------------------------
  // 2. SOS & offline connectivity
  // ---------------------------------------------------------------------

  @override
  Future<ReportSummary> createReport(CreateReportRequest request) async {
    await _delay(500, 1300);
    final summary = ReportSummary(
      ticketId: 'SOS-${_uuid.v4().substring(0, 8).toUpperCase()}',
      description: request.description,
      latitude: request.latitude,
      longitude: request.longitude,
      distanceMeters: 0,
      confirmCount: 0,
      falseAlarmCount: 0,
      status: ReportStatus.pending,
      reportedAt: request.clientTimestamp,
      reporterAlias: 'You',
    );
    _reports.insert(0, summary);
    _pushDashboardEvent(NewSosPendingEvent(
      ticketId: summary.ticketId,
      latitude: summary.latitude,
      longitude: summary.longitude,
      description: summary.description,
      district: _nearestDistrict(summary.latitude, summary.longitude).name,
      timestamp: DateTime.now(),
    ));
    return summary;
  }

  @override
  Future<BulkSyncResult> bulkSyncReports(List<CreateReportRequest> requests) async {
    await _delay(700, 1600);
    final synced = <String>[];
    final duplicates = <String>[];
    for (final req in requests) {
      final alreadySynced = _reports.any((r) =>
          r.description == req.description &&
          r.latitude == req.latitude &&
          r.longitude == req.longitude);
      if (alreadySynced) {
        duplicates.add(req.clientId);
        continue;
      }
      _reports.insert(
        0,
        ReportSummary(
          ticketId: 'SOS-${_uuid.v4().substring(0, 8).toUpperCase()}',
          description: req.description,
          latitude: req.latitude,
          longitude: req.longitude,
          distanceMeters: 0,
          confirmCount: 0,
          falseAlarmCount: 0,
          status: ReportStatus.pending,
          reportedAt: req.clientTimestamp,
          reporterAlias: 'You (synced)',
        ),
      );
      synced.add(req.clientId);
    }
    return BulkSyncResult(syncedClientIds: synced, duplicateClientIds: duplicates);
  }

  // ---------------------------------------------------------------------
  // 2b. Low Data SOS
  // ---------------------------------------------------------------------

  @override
  Future<ReportSummary> sendLiteSos({required double lat, required double lng, required String description}) async {
    await _delay(200, 500); // the whole point of the lite endpoint is speed
    final summary = ReportSummary(
      ticketId: 'SOS-${_uuid.v4().substring(0, 8).toUpperCase()}',
      description: '[LOW DATA] $description',
      latitude: lat,
      longitude: lng,
      distanceMeters: 0,
      confirmCount: 0,
      falseAlarmCount: 0,
      status: ReportStatus.pending,
      reportedAt: DateTime.now(),
      reporterAlias: 'You',
    );
    _reports.insert(0, summary);
    _pushDashboardEvent(NewSosPendingEvent(
      ticketId: summary.ticketId,
      latitude: lat,
      longitude: lng,
      description: summary.description,
      district: _nearestDistrict(lat, lng).name,
      timestamp: DateTime.now(),
    ));
    return summary;
  }

  // ---------------------------------------------------------------------
  // 6. Crowdsourced verification radar
  // ---------------------------------------------------------------------

  @override
  Future<List<ReportSummary>> getReports({double? nearLat, double? nearLng}) async {
    await _delay(400, 900);
    final list = List<ReportSummary>.from(_reports);
    if (nearLat != null && nearLng != null) {
      list.sort((a, b) => _distanceMeters(nearLat, nearLng, a.latitude, a.longitude)
          .compareTo(_distanceMeters(nearLat, nearLng, b.latitude, b.longitude)));
    }
    return list;
  }

  @override
  Future<ReportSummary> verifyReport(String ticketId, VerifyVote vote) async {
    await _delay(300, 700);
    final index = _reports.indexWhere((r) => r.ticketId == ticketId);
    if (index == -1) {
      throw StateError('Report $ticketId not found');
    }
    final current = _reports[index];
    final updated = vote == VerifyVote.confirm
        ? current.copyWith(confirmCount: current.confirmCount + 1)
        : current.copyWith(falseAlarmCount: current.falseAlarmCount + 1);
    final finalUpdate =
        updated.confirmCount >= 3 ? updated.copyWith(status: ReportStatus.verified) : updated;
    _reports[index] = finalUpdate;
    if (finalUpdate.status == ReportStatus.verified && current.status != ReportStatus.verified) {
      _pushDashboardEvent(SosVerifiedEvent(
        ticketId: finalUpdate.ticketId,
        confirmCount: finalUpdate.confirmCount,
        timestamp: DateTime.now(),
      ));
    }
    return finalUpdate;
  }

  // ---------------------------------------------------------------------
  // 7. Evacuation map
  // ---------------------------------------------------------------------

  @override
  Future<ShelterFeatureCollection> getSheltersGeoJson() async {
    await _delay(500, 1100);
    _sheltersCache ??= ShelterFeatureCollection(NationalMockData.generateShelters());
    return _sheltersCache!;
  }

  // ---------------------------------------------------------------------
  // 3. RAG survival chatbot
  // ---------------------------------------------------------------------

  @override
  Future<ChatResponse> sendChatMessage(ChatRequest request) async {
    await _delay(500, 1500);
    final isOnline = _rng.nextDouble() < 0.65;
    final replies = isOnline ? NationalMockData.chatOnlineReplies : NationalMockData.chatOfflineReplies;
    final reply = replies[_rng.nextInt(replies.length)];
    return ChatResponse(reply: reply, mode: isOnline ? ChatMode.online : ChatMode.offline);
  }

  // ---------------------------------------------------------------------
  // 5. Multi-agent intelligence hub
  // ---------------------------------------------------------------------

  @override
  Future<AgentHubResponse> runAgentHubAnalysis(String district) async {
    await _delay(1200, 2200);
    final profile = NationalMetros.byName(district);
    final now = DateTime.now();
    final steps = <AgentExecutionStep>[
      AgentExecutionStep(
        agentName: 'Hydrology Agent',
        action: 'Analyzed rainfall telemetry and river gauge levels',
        finding:
            '${profile.avgAnnualRainfallMm.toStringAsFixed(0)}mm avg annual rainfall; recent '
            '3-day accumulation trending ${profile.baseRiskScore > 55 ? 'above' : 'near'} seasonal norm.',
        timestamp: now.add(const Duration(seconds: 2)),
      ),
      AgentExecutionStep(
        agentName: 'Infrastructure Agent',
        action: 'Cross-referenced elevation, drainage and reservoir data',
        finding: '${profile.terrainNote}. Avg elevation ${profile.avgElevationM.toStringAsFixed(0)}m, '
            'slope ${profile.avgSlopeDeg.toStringAsFixed(0)}°.',
        timestamp: now.add(const Duration(seconds: 5)),
      ),
      AgentExecutionStep(
        agentName: 'Population Density Agent',
        action: 'Estimated exposed population in low-lying wards',
        finding: 'Identified ${8 + _rng.nextInt(24)} wards with elevated exposure near '
            'waterways in $district.',
        timestamp: now.add(const Duration(seconds: 8)),
      ),
      AgentExecutionStep(
        agentName: 'Historical Pattern Agent',
        action: 'Compared against past flood event signatures (2018, 2019, 2024)',
        finding: profile.baseRiskScore > 60
            ? 'Current signature closely matches pre-event conditions from prior major floods.'
            : 'Current signature shows partial overlap with prior minor flood events.',
        timestamp: now.add(const Duration(seconds: 11)),
      ),
    ];

    final alertLevel = profile.baseRiskScore >= 75
        ? AlertLevel.red
        : profile.baseRiskScore >= 55
            ? AlertLevel.orange
            : profile.baseRiskScore >= 35
                ? AlertLevel.yellow
                : AlertLevel.green;

    steps.add(AgentExecutionStep(
      agentName: 'Coordinator Agent',
      action: 'Synthesized findings from all agents into a unified assessment',
      finding: 'Alert level set to ${alertLevel.label} based on combined hydrology, '
          'infrastructure and population signals.',
      timestamp: now.add(const Duration(seconds: 13)),
    ));

    final summary = 'Ensemble analysis for $district indicates ${alertLevel.label.toLowerCase()} '
        'conditions. ${profile.terrainNote}. '
        '${alertLevel == AlertLevel.red || alertLevel == AlertLevel.orange ? 'Recommend pre-positioning rescue boats and opening relief camps in low-lying wards.' : 'Recommend routine monitoring; no immediate evacuation advised.'}';

    return AgentHubResponse(
      district: district,
      executionChain: steps,
      coordinatorSummary: summary,
      alertLevel: alertLevel,
    );
  }

  // ---------------------------------------------------------------------
  // 8. Volunteer command hub
  // ---------------------------------------------------------------------

  @override
  Future<void> updateVolunteerLocation(VolunteerLocationUpdate update) async {
    await _delay(300, 700);
  }

  @override
  Future<List<VolunteerTask>> getVolunteerTasks() async {
    await _delay(500, 1100);
    final districts = NationalMetros.all;
    return List.generate(NationalMockData.taskTemplates.length, (i) {
      final district = districts[_rng.nextInt(districts.length)];
      final template = NationalMockData.taskTemplates[i];
      return VolunteerTask(
        taskId: 'TASK-${(i + 1).toString().padLeft(3, '0')}',
        sosTicketId: 'SOS-${_uuid.v4().substring(0, 8).toUpperCase()}',
        district: district.name,
        latitude: district.center.latitude + (_rng.nextDouble() - 0.5) * 0.08,
        longitude: district.center.longitude + (_rng.nextDouble() - 0.5) * 0.08,
        description: template.description,
        priority: TaskPriority.values[_rng.nextInt(TaskPriority.values.length)],
        status: i == 0 ? TaskStatus.assigned : TaskStatus.values[_rng.nextInt(TaskStatus.values.length)],
        assignedAt: DateTime.now().subtract(Duration(minutes: _rng.nextInt(180))),
        distanceKm: 0.8 + _rng.nextDouble() * 12,
      );
    });
  }

  @override
  Stream<MaskedCallPayload> get incomingCallStream => _incomingCallController.stream;

  @override
  void deliverIncomingCall(MaskedCallPayload payload) => _incomingCallController.add(payload);

  @override
  void simulateIncomingCall() {
    final report = _reports.isNotEmpty
        ? _reports[_rng.nextInt(_reports.length)]
        : null;
    final district = report != null
        ? _nearestDistrict(report.latitude, report.longitude)
        : NationalMetros.all[_rng.nextInt(NationalMetros.all.length)];
    final alias = NationalMockData.reporterAliases[_rng.nextInt(NationalMockData.reporterAliases.length)];
    _incomingCallController.add(MaskedCallPayload(
      sosId: report?.ticketId ?? 'SOS-${_uuid.v4().substring(0, 8).toUpperCase()}',
      callerAlias: alias,
      riskBadge: 'CRITICAL',
      district: district.name,
      latitude: report?.latitude ?? district.center.latitude,
      longitude: report?.longitude ?? district.center.longitude,
    ));
  }

  // ---------------------------------------------------------------------
  // 9. Real-time command center stream
  // ---------------------------------------------------------------------

  @override
  Stream<DashboardEvent> get dashboardEventStream {
    _dashboardController ??= StreamController<DashboardEvent>.broadcast(
      onListen: _startDashboardTimer,
      onCancel: () {
        _dashboardTimer?.cancel();
        _dashboardTimer = null;
      },
    );
    return _dashboardController!.stream;
  }

  void _startDashboardTimer() {
    _dashboardTimer?.cancel();
    _dashboardTimer = Timer.periodic(const Duration(seconds: 9), (_) {
      if (_dashboardController == null || _dashboardController!.isClosed) return;
      // Mirrors main.py's the hourly flood-risk pipeline job: the only event that
      // triggers a push notification is a model-side high-risk read, never
      // a user/citizen action — kept rare here since it's a demo stand-in
      // for an hourly pipeline run finding a district newly high-risk.
      if (_rng.nextDouble() < 0.12) {
        final district = NationalMetros.all[_rng.nextInt(NationalMetros.all.length)];
        final riskScore = 81 + _rng.nextInt(19);
        _dashboardController!.add(HighRiskAlertEvent(
          district: district.name,
          riskScore: riskScore,
          alertLevel: 'CRITICAL',
          timestamp: DateTime.now(),
        ));
      } else if (_rng.nextBool() && _reports.any((r) => r.status == ReportStatus.pending)) {
        final pending = _reports.where((r) => r.status == ReportStatus.pending).toList();
        final target = pending[_rng.nextInt(pending.length)];
        final idx = _reports.indexWhere((r) => r.ticketId == target.ticketId);
        final updated = target.copyWith(
          confirmCount: target.confirmCount + 1,
          status: target.confirmCount + 1 >= 3 ? ReportStatus.verified : ReportStatus.pending,
        );
        _reports[idx] = updated;
        _dashboardController!.add(SosVerifiedEvent(
          ticketId: updated.ticketId,
          confirmCount: updated.confirmCount,
          timestamp: DateTime.now(),
        ));
      } else {
        final district = NationalMetros.all[_rng.nextInt(NationalMetros.all.length)];
        final lat = district.center.latitude + (_rng.nextDouble() - 0.5) * 0.1;
        final lng = district.center.longitude + (_rng.nextDouble() - 0.5) * 0.1;
        final description = NationalMockData
            .sosDescriptions[_rng.nextInt(NationalMockData.sosDescriptions.length)];
        final summary = ReportSummary(
          ticketId: 'SOS-${_uuid.v4().substring(0, 8).toUpperCase()}',
          description: description,
          latitude: lat,
          longitude: lng,
          distanceMeters: 0,
          confirmCount: 0,
          falseAlarmCount: 0,
          status: ReportStatus.pending,
          reportedAt: DateTime.now(),
          reporterAlias:
              NationalMockData.reporterAliases[_rng.nextInt(NationalMockData.reporterAliases.length)],
        );
        _reports.insert(0, summary);
        _dashboardController!.add(NewSosPendingEvent(
          ticketId: summary.ticketId,
          latitude: lat,
          longitude: lng,
          description: description,
          district: district.name,
          timestamp: DateTime.now(),
        ));
      }
    });
  }

  void _pushDashboardEvent(DashboardEvent event) {
    if (_dashboardController != null && !_dashboardController!.isClosed) {
      _dashboardController!.add(event);
    }
  }

  // ---------------------------------------------------------------------
  // 11. Voice Agent
  // ---------------------------------------------------------------------

  @override
  Future<VoiceAgentResult> sendVoiceQuery({
    required double lat,
    required double lng,
    required Uint8List audioBytes,
  }) async {
    await _delay(900, 1800);
    final district = _nearestDistrict(lat, lng);
    return VoiceAgentResult(
      transcript: "Where's the nearest shelter, I'm stranded near ${district.name}?",
      replyText: 'The nearest relief camp is Govt Higher Secondary School, about 2.4km away. '
          'An offline routing map has been provided on your app screen to guide you safely.',
      // The mock has no real audio asset to play back — the screen skips
      // playback and shows the text response when audioBytes is null.
    );
  }

  // ---------------------------------------------------------------------
  // helpers
  // ---------------------------------------------------------------------

  List<ReportSummary> _seedReports() {
    final now = DateTime.now();
    final result = <ReportSummary>[];
    for (var i = 0; i < 9; i++) {
      final district = NationalMetros.all[_rng.nextInt(NationalMetros.all.length)];
      final lat = district.center.latitude + (_rng.nextDouble() - 0.5) * 0.12;
      final lng = district.center.longitude + (_rng.nextDouble() - 0.5) * 0.12;
      final confirmCount = _rng.nextInt(3);
      result.add(ReportSummary(
        ticketId: 'SOS-${_uuid.v4().substring(0, 8).toUpperCase()}',
        description: NationalMockData.sosDescriptions[i % NationalMockData.sosDescriptions.length],
        latitude: lat,
        longitude: lng,
        distanceMeters: 200 + _rng.nextDouble() * 4800,
        confirmCount: confirmCount,
        falseAlarmCount: _rng.nextInt(2),
        status: confirmCount >= 3 ? ReportStatus.verified : ReportStatus.pending,
        reportedAt: now.subtract(Duration(minutes: 5 + _rng.nextInt(600))),
        reporterAlias: NationalMockData.reporterAliases[i % NationalMockData.reporterAliases.length],
      ));
    }
    return result;
  }

  MetroProfile _nearestDistrict(double lat, double lng) => NationalMetros.nearest(lat, lng);

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double deg) => deg * pi / 180;

  // ---------------------------------------------------------------------
  // 12. HITL alert approval
  // ---------------------------------------------------------------------

  @override
  Future<List<PendingAlert>> getPendingAlerts() async {
    await _delay();
    return _pendingAlerts.where((a) => a.status == PendingAlertStatus.pending).toList();
  }

  Future<PendingAlert> _resolve(int alertId, PendingAlertStatus status) async {
    await _delay();
    final index = _pendingAlerts.indexWhere((a) => a.id == alertId);
    if (index == -1) throw Exception('Alert not found');
    final updated = PendingAlert(
      id: _pendingAlerts[index].id,
      district: _pendingAlerts[index].district,
      alertLevel: _pendingAlerts[index].alertLevel,
      message: _pendingAlerts[index].message,
      status: status,
      riskScore: _pendingAlerts[index].riskScore,
      createdAt: _pendingAlerts[index].createdAt,
    );
    _pendingAlerts[index] = updated;
    return updated;
  }

  @override
  Future<PendingAlert> approveAlert(int alertId) => _resolve(alertId, PendingAlertStatus.approved);

  @override
  Future<PendingAlert> rejectAlert(int alertId) => _resolve(alertId, PendingAlertStatus.rejected);

  @override
  Future<List<AdminReport>> getAllReportsAdmin() async {
    await _delay();
    return List.unmodifiable(_adminReports);
  }

  @override
  Future<List<AdminVolunteer>> getAllVolunteersAdmin() async {
    await _delay();
    return List.unmodifiable(_adminVolunteers);
  }

  @override
  Future<AdminReport> assignReportToVolunteer(int reportId, int volunteerId) async {
    await _delay();
    final reportIndex = _adminReports.indexWhere((r) => r.id == reportId);
    if (reportIndex == -1) throw Exception('Report not found');
    final volunteer = _adminVolunteers.firstWhere((v) => v.id == volunteerId, orElse: () => throw Exception('Volunteer not found'));
    final updated = _adminReports[reportIndex].copyWith(
      status: 'dispatched',
      assignedVolunteerId: volunteer.id,
      assignedVolunteerName: volunteer.fullName,
    );
    _adminReports[reportIndex] = updated;
    return updated;
  }

  @override
  void dispose() {
    _dashboardTimer?.cancel();
    _dashboardController?.close();
    _incomingCallController.close();
  }

  // ---------------------------------------------------------------------
  // 14-19. PS 26071 — inundation, routing, protocol, analytics, citizen ops
  // ---------------------------------------------------------------------

  static const Map<String, List<String>> _landmarksByCity = {
    'Mumbai': ['Hindmata Junction Basin', 'Milan Subway Corridor', 'Gandhi Market (Kings Circle)', 'Sion Station Low-lying Road'],
    'Chennai': ['Velachery Lake Catchment', 'Madipakkam Ward 188', 'T. Nagar Usman Road Underpass', 'Adyar River Floodplain'],
    'Delhi': ['ITO Ring Road Underpass', 'Yamuna Bazar Ghat Area', 'Kashmere Gate ISBT Basin', 'Pragati Maidan Corridor'],
    'Guwahati': ['Rukminigaon GS Road Axis', 'Anil Nagar Canal Overflow Basin', 'Nabin Nagar Low-elevation Sector', 'Zoo Road Downstream Ward'],
    'Ernakulam': ['MG Road Metro Corridor', 'Railway Colony Basin', 'Kaloor Stadium Low-lying Ward', 'Central Broadway Market Ward'],
  };

  Map<String, dynamic> _polygon(double lat, double lon, double delta) => {
        'type': 'Polygon',
        'coordinates': [
          [
            [lon - delta, lat - delta],
            [lon + delta, lat - delta],
            [lon + delta, lat + delta],
            [lon - delta, lat + delta],
            [lon - delta, lat - delta],
          ]
        ],
      };

  @override
  Future<InundationSimulationResponse> getInundationSimulation({
    required String district,
    required String scenario,
  }) async {
    await _delay(300, 700);
    final metro = NationalMetros.byName(district);
    final landmarks = _landmarksByCity[metro.name] ?? const [];
    final lat = metro.center.latitude;
    final lon = metro.center.longitude;
    final extreme = scenario.toUpperCase() == 'EXTREME_EVENT';

    final steps = extreme
        ? [
            (t: 'T+0h (Nowcast)', depth: 0.25, dbz: 39.5, rain: 28.0, delta: 0.007, sev: 'MODERATE', lm: landmarks.take(1).toList()),
            (t: 'T+1h', depth: 0.75, dbz: 48.0, rain: 52.0, delta: 0.012, sev: 'HIGH', lm: landmarks.take(2).toList()),
            (t: 'T+2h (Peak Inundation)', depth: 1.45, dbz: 54.2, rain: 72.0, delta: 0.018, sev: 'CRITICAL', lm: landmarks),
            (t: 'T+3h (Receding)', depth: 0.85, dbz: 32.0, rain: 14.0, delta: 0.013, sev: 'HIGH', lm: landmarks.take(2).toList()),
          ]
        : [
            (t: 'T+0h (Nowcast)', depth: 0.02, dbz: 18.0, rain: 1.0, delta: 0.003, sev: 'LOW', lm: <String>[]),
            (t: 'T+1h', depth: 0.04, dbz: 22.0, rain: 2.5, delta: 0.003, sev: 'LOW', lm: <String>[]),
            (t: 'T+2h', depth: 0.05, dbz: 20.0, rain: 2.0, delta: 0.003, sev: 'LOW', lm: <String>[]),
            (t: 'T+3h', depth: 0.01, dbz: 15.0, rain: 0.5, delta: 0.003, sev: 'LOW', lm: <String>[]),
          ];

    final frames = steps
        .map((s) => InundationFrame(
              timeStep: s.t,
              waterDepthMeters: s.depth,
              radarDbz: s.dbz,
              satelliteRainRateMmHr: s.rain,
              severity: s.sev,
              affectedLandmarks: s.lm,
              geojsonGeometry: _polygon(lat, lon, s.delta),
            ))
        .toList();

    final peak = extreme ? steps[2] : steps[0];
    final zones = extreme
        ? [
            InundationPolygon(
              zoneId: 'INUND-PEAK-${metro.name.substring(0, 3).toUpperCase()}-01',
              severity: 'CRITICAL',
              avgWaterDepthMeters: peak.depth,
              affectedLandmarks: landmarks,
              geojsonGeometry: _polygon(lat, lon, peak.delta),
            ),
          ]
        : <InundationPolygon>[];

    return InundationSimulationResponse(
      timestamp: DateTime.now().toUtc().toIso8601String(),
      district: metro.name,
      leadTimeWarning: extreme ? '0 - 3 Hours Nowcast (Immediate Inundation Expected)' : 'No Extreme Inundation Threat Detected',
      alertLevel: extreme ? 'RED' : 'GREEN',
      telemetry: FourPillarTelemetry.fromJson({
        'satellite': {
          'source': 'INSAT-3DR (MOSDAC / ISRO)',
          'cloud_top_temp_kelvin': extreme ? 201.8 : 265.0,
          'rainfall_hydro_estimator_mm_hr': extreme ? 72.0 : 2.5,
        },
        'radar': {
          'station': 'Doppler Weather Radar (DWR) ${metro.name}',
          'reflectivity_dbz': extreme ? 54.2 : 22.0,
          'echo_top_km': extreme ? 15.1 : 4.0,
        },
        'observational_weather': {
          'station_id': 'IMD-AWS-${metro.name.substring(0, 3).toUpperCase()}-01',
          'current_rainfall_mm_hr': extreme ? 72.0 : 1.5,
          'cumulative_24h_rainfall_mm': extreme ? 188.4 : 10.0,
        },
        'numerical_weather_prediction': {
          'model_name': 'NCMRWF Unified Model / WRF (4km)',
          'forecast_lead_time_hours': 6,
          'predicted_precipitation_mm': extreme ? 98.0 : 4.0,
        },
      }),
      inundationZones: zones,
      simulationFrames: frames,
      advisoryBulletin: extreme
          ? 'IMD HIGH-SEVERITY BULLETIN (${metro.name.toUpperCase()} METROPOLITAN AREA): Fused Doppler Radar and '
              'INSAT-3DR imagery confirm intense convective storm activity. Peak street inundation of '
              '${peak.depth}m projected across ${landmarks.take(2).join(', ')} at T+2h.'
          : 'IMD NORMAL ADVISORY (${metro.name.toUpperCase()}): No convective cloudburst or road inundation conditions detected.',
    );
  }

  @override
  Future<BlockedNodesResponse> getBlockedNodes({required String zoneId}) async {
    await _delay(200, 500);
    final upper = zoneId.toUpperCase();
    final metro = NationalMetros.all.firstWhere(
      (m) => upper.contains(m.name.substring(0, 3).toUpperCase()),
      orElse: () => NationalMetros.all.first,
    );
    final lat = metro.center.latitude;
    final lon = metro.center.longitude;
    return BlockedNodesResponse(
      zoneId: zoneId,
      blockedBoundingBoxes: [
        BlockedBoundingBox(
          minLat: lat - 0.01,
          maxLat: lat - 0.002,
          minLon: lon - 0.008,
          maxLon: lon + 0.002,
          description: '${_landmarksByCity[metro.name]?.first ?? 'Main corridor'} - Impassable',
        ),
      ],
      action: 'Set graph node weights inside these bounding boxes to infinity.',
    );
  }

  @override
  Future<NdmaProtocolResponse> getNdmaProtocol({
    required String district,
    required String alertLevel,
    double? radarDbz,
    double? satelliteTempK,
  }) async {
    await _delay(300, 700);
    final upper = alertLevel.toUpperCase();
    if (upper == 'RED') {
      return NdmaProtocolResponse(
        district: district,
        alertLevel: 'RED',
        ragKnowledgeSource: 'NDMA Standard Guidelines on Urban Flooding & IMD Heavy Rainfall SOP 4.2',
        meteorologicalTriggerSummary:
            'Severe convective cloudburst detected. Radar reflectivity ${radarDbz ?? 53.2} dBZ indicates extreme precipitation over $district.',
        actionableChecklist: [
          '1. [IMD Protocol]: Activate District Emergency Operations Center (DEOC) for $district immediately.',
          '2. [Power Grid]: Isolate power supply to low-lying electrical substations within the inundation bounding boxes.',
          '3. [NDRF Deployment]: Pre-position NDRF rescue units and boats at identified bottleneck zones.',
          '4. [Traffic Control]: Barricade and restrict vehicular entry into local underpasses and low-elevation corridors.',
          '5. [Public Safety]: Open designated public relief camps and broadcast evacuation routes via SMS fallback.',
        ],
        evacuationPriority: 'CRITICAL - IMMEDIATE ACTION REQUIRED',
      );
    } else if (upper == 'ORANGE') {
      return NdmaProtocolResponse(
        district: district,
        alertLevel: 'ORANGE',
        ragKnowledgeSource: 'NDMA Guidelines on Urban Flooding Management (Section 3.5)',
        meteorologicalTriggerSummary: 'Moderate-to-heavy rainfall warning. Elevated risk of waterlogging in low-elevation sectors.',
        actionableChecklist: [
          '1. Place municipal drainage pumping stations on high alert across $district.',
          '2. Issue advisory warnings to local citizens via the mobile app and shelter networks.',
          '3. Monitor live Doppler Radar and INSAT-3DR telemetry spikes.',
        ],
        evacuationPriority: 'ELEVATED PREPAREDNESS',
      );
    }
    return NdmaProtocolResponse(
      district: district,
      alertLevel: 'GREEN',
      ragKnowledgeSource: 'NDMA Guidelines on Urban Flooding Management (Section 2.1)',
      meteorologicalTriggerSummary: 'Normal regional moisture levels. No heavy rainfall or convective cloudburst signatures.',
      actionableChecklist: [
        '1. Routine meteorological monitoring of $district telemetry feeds.',
        '2. Ensure standard municipal canal cleaning schedules are maintained.',
      ],
      evacuationPriority: 'NORMAL MONITORING',
    );
  }

  @override
  Future<StormComparisonResponse> getStormComparison({required String district}) async {
    await _delay(300, 700);
    return StormComparisonResponse(
      district: district,
      currentStormName: 'Active Convective Cell (PS-26071 Fused Stream)',
      currentPeakRainfallMmHr: 72.0,
      currentMaxRadarDbz: 54.2,
      currentHourlyTrend: const [15.0, 32.5, 52.0, 72.0, 48.0, 22.0],
      historicalBenchmarks: const [
        HistoricalStormBenchmark(
          eventName: 'Mumbai Historic Cloudburst',
          year: 2005,
          peakRainfallMmHr: 94.0,
          maxRadarDbz: 58.5,
          hourlyTrend: [20.0, 45.0, 85.0, 94.0, 60.0, 30.0],
        ),
        HistoricalStormBenchmark(
          eventName: 'Chennai Urban Flood Event',
          year: 2015,
          peakRainfallMmHr: 82.0,
          maxRadarDbz: 52.0,
          hourlyTrend: [10.0, 25.0, 65.0, 82.0, 55.0, 20.0],
        ),
      ],
    );
  }

  @override
  Future<SmsBroadcastResult> broadcastEmergencySms({
    required String district,
    required String zoneId,
    required String alertMessage,
  }) async {
    await _delay(500, 1200);
    return SmsBroadcastResult(
      status: 'SUCCESS',
      broadcastTimestamp: DateTime.now().toUtc().toIso8601String(),
      targetedDistrict: district,
      simulatedSmsRecipientsCount: 14280,
      sampleRecipients: const ['+91-98765XXXXX', '+91-91234XXXXX', '+91-99887XXXXX'],
      fallbackMode: 'Cellular Gateway Emergency Broadcast (Cell Broadcast / Offline SMS Fallback)',
    );
  }

  @override
  Future<GroundTruthReportResult> submitGroundTruth({
    required String district,
    required double lat,
    required double lng,
    required double observedWaterDepthMeters,
    required String description,
  }) async {
    await _delay(400, 900);
    return GroundTruthReportResult(
      status: 'VERIFIED_LOGGED',
      reportId: 'GT-REP-${DateTime.now().millisecondsSinceEpoch % 1000000}',
      receivedTimestamp: DateTime.now().toUtc().toIso8601String(),
      message: 'Observation recorded successfully for $district. Forwarded to IMD Predictor validation pipeline.',
    );
  }
}
