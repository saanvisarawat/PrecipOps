import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/floodops_api.dart';
import 'api_provider.dart';
import 'service_providers.dart';

/// Real-time command center stream (module 9). Backed today by
/// `MockPreciopsApi.dashboardEventStream` (a local Timer), swapped for a
/// real `ws://.../ws/dashboard` listener automatically once
/// `DioPreciopsApi` is selected in `api_provider.dart`. Not `.autoDispose`
/// on purpose: once anything reads it (see [riskPushNotifierProvider],
/// watched from `ShellScreen`), the underlying socket subscription is
/// kept alive for the app's lifetime rather than tearing down whenever the
/// screen that happened to be watching it is popped.
final dashboardEventStreamProvider = StreamProvider<DashboardEvent>((ref) {
  final api = ref.watch(preciopsApiProvider);
  return api.dashboardEventStream;
});

/// Fires a system/local push notification the moment the flood risk model
/// flags a district as high-risk (`HighRiskAlertEvent` — sent only by
/// `the hourly flood-risk pipeline job`'s model-side check in `main.py`, never by a
/// citizen/user action such as filing or verifying a report) — regardless
/// of which screen is currently open, so nobody has to have the Alerts tab
/// open to be notified. Watched once from `ShellScreen` (mounted for the
/// whole app session) so it's wired up from launch instead of only after a
/// user happens to visit Alerts.
final riskPushNotifierProvider = Provider<void>((ref) {
  final notifications = ref.watch(notificationServiceProvider);
  ref.listen<AsyncValue<DashboardEvent>>(dashboardEventStreamProvider, (previous, next) {
    next.whenData((event) {
      if (event is! HighRiskAlertEvent) return;
      notifications.init().then((_) => notifications.showRiskAlert(
            title: 'High Flood Risk — ${event.district}',
            body: 'Model risk score ${event.riskScore}% (${event.alertLevel}). '
                'Stay alert and check evacuation routes.',
          ));
    });
  });
});

/// Masked-call trigger (module 8). Today only fired by the debug button
/// on the volunteer hub via `PreciopsApi.simulateIncomingCall()`; once
/// push is wired up this same stream carries real FCM-triggered calls.
final incomingCallStreamProvider = StreamProvider<MaskedCallPayload>((ref) {
  final api = ref.watch(preciopsApiProvider);
  return api.incomingCallStream;
});
