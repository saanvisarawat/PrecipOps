import 'dart:typed_data';

import 'models/auth_models.dart';
import 'models/report_models.dart';
import 'models/shelter_models.dart';
import 'models/chat_models.dart';
import 'models/agent_hub_models.dart';
import 'models/volunteer_models.dart';
import 'models/dashboard_event_models.dart';
import 'models/voice_models.dart';
import 'models/alert_models.dart';
import 'models/admin_report_models.dart';
import 'models/inundation_models.dart';

export 'models/auth_models.dart';
export 'models/report_models.dart';
export 'models/shelter_models.dart';
export 'models/chat_models.dart';
export 'models/agent_hub_models.dart';
export 'models/volunteer_models.dart';
export 'models/dashboard_event_models.dart';
export 'models/voice_models.dart';
export 'models/alert_models.dart';
export 'models/admin_report_models.dart';
export 'models/inundation_models.dart';

/// The single contract every screen in this app talks to. Every mocked
/// endpoint here mirrors a real FastAPI route documented in
/// API_CONTRACT.md — swapping [MockPreciopsApi] for a real
/// `DioPreciopsApi` in providers/api_provider.dart is the only change
/// needed to go live.
abstract class PreciopsApi {
  // 1. Auth & device onboarding
  Future<AuthResponse> register(RegisterRequest request);
  Future<AuthResponse> login(LoginRequest request);
  Future<void> registerFcmToken(String token);

  // 2. SOS & offline connectivity
  Future<ReportSummary> createReport(CreateReportRequest request);
  Future<BulkSyncResult> bulkSyncReports(List<CreateReportRequest> requests);

  // 2b. Low Data SOS — a single-packet fallback for edge/2G connectivity
  // (POST /api/reports/lite), distinct from the richer createReport flow.
  Future<ReportSummary> sendLiteSos({required double lat, required double lng, required String description});

  // 6. Crowdsourced verification radar
  Future<List<ReportSummary>> getReports({double? nearLat, double? nearLng});
  Future<ReportSummary> verifyReport(String ticketId, VerifyVote vote);

  // 7. Evacuation map
  Future<ShelterFeatureCollection> getSheltersGeoJson();

  // 3. RAG survival chatbot
  Future<ChatResponse> sendChatMessage(ChatRequest request);

  // 5. Multi-agent intelligence hub
  Future<AgentHubResponse> runAgentHubAnalysis(String district);

  // 8. Volunteer command hub
  Future<void> updateVolunteerLocation(VolunteerLocationUpdate update);
  Future<List<VolunteerTask>> getVolunteerTasks();

  // 8. Masked calling — real trigger is a background FCM data message
  // (type: "EMERGENCY_INCOMING_CALL") from POST
  // /api/emergency/trigger-masked-call. In this build
  // MockPreciopsApi.simulateIncomingCall() is invoked by a debug button
  // instead; deliverIncomingCall() is what a real FCM handler calls once
  // Firebase is configured (see services/fcm_service.dart) — both feed
  // the same stream, so MaskedCallScreen needs no changes either way.
  Stream<MaskedCallPayload> get incomingCallStream;
  void simulateIncomingCall();
  void deliverIncomingCall(MaskedCallPayload payload);

  // 9. Real-time command center stream
  Stream<DashboardEvent> get dashboardEventStream;

  // 11. Voice Agent (POST /api/voice/agent) — Sarvam STT/TTS + Gemini.
  // Takes raw WAV bytes rather than a `dart:io File` so this works
  // identically on web (where there is no real filesystem path to open).
  Future<VoiceAgentResult> sendVoiceQuery({
    required double lat,
    required double lng,
    required Uint8List audioBytes,
  });

  // 12. HITL alert approval — a model-detected high-risk transition
  // creates a pending alert (see the hourly flood-risk pipeline job); the citizen-
  // facing high_risk_alert push only fires once a volunteer/official
  // approves it here. Both roles may approve/reject.
  Future<List<PendingAlert>> getPendingAlerts();
  Future<PendingAlert> approveAlert(int alertId);
  Future<PendingAlert> rejectAlert(int alertId);

  // 13. Official SOS dashboard — every citizen report regardless of status,
  // plus manual dispatch to a specific volunteer (fallback for when
  // allocate_resources_for_sos found nobody available within 5km at
  // creation time). Official-only.
  Future<List<AdminReport>> getAllReportsAdmin();
  Future<List<AdminVolunteer>> getAllVolunteersAdmin();
  Future<AdminReport> assignReportToVolunteer(int reportId, int volunteerId);

  // 14. PS 26071 — Heavy rainfall early warning & inundation prediction
  // (GET /api/v1/inundation/simulate). Predictor Dashboard's primary feed:
  // the 4-Pillar HUD, the inundation polygon, and the 4-frame time-lapse.
  Future<InundationSimulationResponse> getInundationSimulation({
    required String district,
    required String scenario, // 'NORMAL' or 'EXTREME_EVENT'
  });

  // 15. Evacuation routing — blocked street bounding boxes for a given
  // inundation zone (GET /api/v1/routing/blocked-nodes). Feeds the offline
  // Dijkstra router used by both the Responder and Citizen dashboards.
  Future<BlockedNodesResponse> getBlockedNodes({required String zoneId});

  // 16. RAG-generated NDMA protocol checklist (GET /api/v1/agents/protocol).
  // Responder Dashboard's actionable checklist + IMD advisory bulletin.
  Future<NdmaProtocolResponse> getNdmaProtocol({
    required String district,
    required String alertLevel,
    double? radarDbz,
    double? satelliteTempK,
  });

  // 17. Comparative storm analytics (GET /api/v1/analytics/storm-comparison).
  // Responder Dashboard's current-vs-historical rainfall trend chart.
  Future<StormComparisonResponse> getStormComparison({required String district});

  // 18. Emergency SMS broadcast fallback (POST /api/v1/citizen/broadcast).
  Future<SmsBroadcastResult> broadcastEmergencySms({
    required String district,
    required String zoneId,
    required String alertMessage,
  });

  // 19. Citizen ground-truth verification upload
  // (POST /api/v1/citizen/verification/upload).
  Future<GroundTruthReportResult> submitGroundTruth({
    required String district,
    required double lat,
    required double lng,
    required double observedWaterDepthMeters,
    required String description,
  });

  void dispose();
}
