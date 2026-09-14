# FloodOps API Contract

This is the contract the Flutter UI was built against. Every screen talks
only to the `FloodOpsApi` interface (`lib/api/floodops_api.dart`) —
never to `MockFloodOpsApi` or `DioFloodOpsApi` directly. Today
`providers/api_provider.dart` wires up `MockFloodOpsApi`, which fakes every
endpoint below with realistic Kerala data and a small artificial network
delay. `lib/api/dio_floodops_api.dart` is a ready (untested) implementation
of the same interface against the real FastAPI backend described in
`features.docx` — going live is flipping `Env.useMockApi` to `false` in
`lib/core/config/env.dart` (or passing
`--dart-define=USE_MOCK_API=false --dart-define=API_BASE_URL=...
--dart-define=WS_BASE_URL=...`).

All request/response field names below use `snake_case` to match the
FastAPI convention from features.docx. Dart model classes
(`lib/api/models/*.dart`) do the `snake_case` <-> `camelCase` conversion at
the boundary.

---

## 1. Auth & device onboarding

### `POST /api/auth/register`
Request:
```json
{
  "full_name": "Anand Kumar",
  "email": "anand@example.com",
  "password": "••••••••",
  "role": "citizen | volunteer | official"
}
```
Response (`AuthResponse`):
```json
{
  "token": "<jwt>",
  "user": {
    "id": "uuid",
    "full_name": "Anand Kumar",
    "email": "anand@example.com",
    "role": "volunteer"
  }
}
```
Token is persisted in `flutter_secure_storage` by `AuthController`.

### `POST /api/auth/login`
Request: `{ "email": "...", "password": "..." }`
Response: same `AuthResponse` shape as register.

> Judgment call: the mock derives a display name from the email and picks
> role `official` if the email contains the substring "official", else
> `volunteer`, since a real login response wouldn't otherwise know the
> role client-side before the call returns. Purely a demo convenience —
> the real backend response already carries `role` on `user`.

### `POST /api/users/fcm-token`
Request: `{ "fcm_token": "<token>" }` — fire-and-forget, no meaningful
response body assumed.

---

## 2. SOS & offline connectivity

### `POST /api/reports`
Request (`CreateReportRequest`):
```json
{
  "client_id": "uuid",
  "description": "Water entering ground floor...",
  "latitude": 9.4981,
  "longitude": 76.3388,
  "client_timestamp": "2026-09-02T10:15:00.000Z"
}
```
Response (`ReportSummary`):
```json
{
  "ticket_id": "SOS-AB12CD34",
  "description": "...",
  "latitude": 9.4981,
  "longitude": 76.3388,
  "distance_meters": 0,
  "confirm_count": 0,
  "false_alarm_count": 0,
  "status": "pending | verified | false_alarm",
  "reported_at": "2026-09-02T10:15:02.000Z",
  "reporter_alias": "You"
}
```

### `POST /api/reports/bulk`
Request: `{ "reports": [ <CreateReportRequest>, ... ] }`
Response:
```json
{ "synced_client_ids": ["uuid1"], "duplicate_client_ids": ["uuid2"] }
```
Used by `OfflineQueueService` (real sqflite-backed queue) to drain queued
reports once connectivity returns. Duplicate detection is assumed
server-side (`client_id` idempotency key); the mock also does a naive
description+coordinate match.

> Judgment call: features.docx says bulk sync is "for backend
> deduplication" but doesn't specify the response shape. The
> `synced_client_ids` / `duplicate_client_ids` split above is what the
> offline queue needs to know which local rows are safe to delete —
> double check this against whatever the real backend actually returns.

---

## 3. Zero-connectivity SMS fallback

No backend endpoint is called from the client for this — `SmsFallbackService`
opens the native SMS composer (real, working code, not mocked) pre-filled
with:
```
SOS <lat> <lng> <description>
```
addressed to `SmsFallbackService.emergencySmsNumber` (currently a
placeholder `+919999911111` — **replace with the real Twilio-bound number**
before shipping). The backend side of this is
`POST /api/reports/sms-webhook`, which the client never calls directly.

---

## 6. Crowdsourced verification radar

### `GET /api/reports`
Query params: `near_lat`, `near_lng` (optional, floats).
Response: `ReportSummary[]` (same shape as above), sorted by distance when
`near_lat`/`near_lng` are supplied.

### `POST /api/reports/{ticket_id}/verify`
Request: `{ "vote": "confirm | false_alarm" }`
Response: updated `ReportSummary`. `status` flips to `"verified"` once
`confirm_count >= 3` (mirrors the mock's tally logic — confirm this
threshold and field name against the real backend).

> Judgment call: features.docx doesn't specify the request body for the
> vote — "confirm" / "false_alarm" strings are this build's choice, driven
> by the "Confirm Hazard" / "False Alarm" buttons in the spec.

---

## 7. Interactive evacuation map

### `GET /api/shelters/geojson`
Response: a GeoJSON `FeatureCollection`:
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "shelter-001",
      "geometry": { "type": "Point", "coordinates": [76.3388, 9.4981] },
      "properties": {
        "name": "Govt. Higher Secondary School, Alappuzha",
        "district": "Alappuzha",
        "capacity": 220,
        "current_occupancy": 180,
        "address": "..."
      }
    }
  ]
}
```
Marker color/label is derived client-side from
`capacity - current_occupancy` (never color alone — always paired with a
"Space Available / Nearly Full / Full" text label).

---

## 4. ML flood risk predictor

### `POST /api/predict/risk`
Request (`RiskPredictionRequest`):
```json
{
  "district": "Idukki",
  "rainfall_mm_3day": 180,
  "elevation_m": 1500,
  "slope_deg": 26,
  "soil_saturation_pct": 70,
  "river_proximity_km": 0.8,
  "reservoir_level_pct": 65
}
```
Response:
```json
{
  "risk_score": 62.4,
  "district": "Idukki",
  "top_factors": [
    { "factor": "Heavy 3-Day Rainfall", "weight": 24.1 },
    { "factor": "Reservoir/Dam Level", "weight": 6.5 }
  ]
}
```
`risk_score` is 0–100. `top_factors` is pre-sorted by `|weight|` descending
by the mock; assume the real SHAP explainer output needs the same
client-side sort if it isn't already sorted.

> Judgment call: features.docx names "rainfall, elevation, slope, etc."
> without an exhaustive field list. This build adds
> `soil_saturation_pct`, `river_proximity_km`, and `reservoir_level_pct` as
> plausible additional ML inputs — check the real model's actual feature
> list and adjust the form/request shape to match.

---

## 3. RAG survival chatbot

### `POST /api/chat`
Request: `{ "message": "...", "session_id": "uuid" }`
Response: `{ "reply": "...", "mode": "online | offline" }`
`mode: "online"` → green "Cloud Verified" pill (Gemini path).
`mode: "offline"` → orange "Offline Protocol Mode" banner (local ChromaDB
fallback path). The mock randomizes ~65% online / 35% offline per message
purely so both UI states are visible in a demo.

---

## 5. Multi-agent intelligence hub

### `POST /api/agents/analyze`
Request: `{ "district": "Ernakulam" }`
Response:
```json
{
  "district": "Ernakulam",
  "execution_chain": [
    {
      "agent_name": "Hydrology Agent",
      "action": "Analyzed rainfall telemetry and river gauge levels",
      "finding": "...",
      "timestamp": "2026-09-02T10:00:02.000Z"
    }
  ],
  "coordinator_summary": "Ensemble analysis for Ernakulam indicates...",
  "alert_level": "green | yellow | orange | red"
}
```

> Judgment call: features.docx never names this endpoint's path —
> `POST /api/agents/analyze` is this build's assumption, modeled after the
> other `POST /api/predict/...`-style routes. Confirm the real path/verb
> with the backend team.

---

## 8. Volunteer command hub & masked calling

### `POST /api/volunteers/location`
Request:
```json
{
  "status": "available | offline",
  "skills": ["medical", "boat_rescue", "logistics", "communications", "first_responder"],
  "latitude": 9.98,
  "longitude": 76.3
}
```
No meaningful response body assumed.

### `GET /api/volunteers/tasks`
Response: `VolunteerTask[]`
```json
{
  "task_id": "TASK-001",
  "sos_ticket_id": "SOS-AB12CD34",
  "district": "Ernakulam",
  "latitude": 9.98,
  "longitude": 76.3,
  "description": "Family of 5 stranded near river embankment, boat needed",
  "priority": "low | medium | high | critical",
  "status": "assigned | en_route | completed",
  "assigned_at": "2026-09-02T09:40:00.000Z",
  "distance_km": 4.2
}
```

### Masked call trigger
Not an HTTP endpoint. Per features.docx this arrives as an FCM background
**data message**:
```json
{
  "type": "EMERGENCY_INCOMING_CALL",
  "sos_id": "SOS-AB12CD34",
  "caller_alias": "Anand K.",
  "risk_badge": "CRITICAL",
  "district": "Ernakulam",
  "latitude": 9.98,
  "longitude": 76.3
}
```
`MaskedCallPayload` mirrors this shape exactly. Today it's produced by
`FloodOpsApi.simulateIncomingCall()` (a debug button on the Volunteer Hub)
instead of a real push — wiring up `NotificationService`'s FCM background
handler to call the same stream is the only change needed once Firebase is
configured (see TODOs in `lib/services/notification_service.dart`).

---

## 9. Real-time command center stream

### `ws://<backend-url>/ws/dashboard`
Server -> client JSON messages, one event per frame:
```json
{ "type": "new_sos_pending", "ticket_id": "SOS-...", "latitude": 9.9, "longitude": 76.3, "description": "...", "district": "Ernakulam", "timestamp": "..." }
```
```json
{ "type": "sos_verified", "ticket_id": "SOS-...", "confirm_count": 3, "timestamp": "..." }
```
Modeled by `DashboardEvent.fromJson` (`lib/api/models/dashboard_event_models.dart`).
Today this is faked by `MockFloodOpsApi.dashboardEventStream`, a local
`Timer.periodic` emitting the same two event shapes every ~9s. Swapping
`Env.useMockApi` to `false` makes `DioFloodOpsApi` open a real
`WebSocketChannel` to `$wsBaseUrl/ws/dashboard` and decode the same JSON —
no screen changes required.

---

## Judgment calls to double-check (summary)

1. `POST /api/reports/bulk` response shape (`synced_client_ids` /
   `duplicate_client_ids`) is invented — confirm against the real backend.
2. `POST /api/reports/{ticket_id}/verify` request body
   (`{"vote": "confirm"|"false_alarm"}`) and the "3 confirms = verified"
   threshold are assumed from the spec's plain-English description.
3. The multi-agent hub endpoint path (`POST /api/agents/analyze`) is not
   named in features.docx — this build's best guess.
4. `RiskPredictionRequest` fields beyond rainfall/elevation/slope
   (soil saturation, river proximity, reservoir level) are invented to
   give the form enough inputs for a believable gauge — align with the
   real model's actual feature set.
5. The SMS fallback destination number is a placeholder and must be
   replaced with the real Twilio-bound number.
6. `role` is `citizen | volunteer | official` per features.docx's "Citizen
   vs. Volunteer" plus an inferred `Official` role for the Command Center
   / Multi-Agent Hub views that the spec describes but doesn't name a role
   for.
