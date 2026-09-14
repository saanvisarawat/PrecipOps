import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'web_notifier.dart';

/// Push notification integration point.
///
/// TODO(real-backend): This is intentionally a no-op/mock shim so the app
/// builds and demos without a Firebase project attached. To wire up real
/// push:
///   1. Add `firebase_core`, run `flutterfire configure`, add
///      google-services.json / GoogleService-Info.plist.
///   2. Replace [requestPermissionAndGetMockToken] with
///      `FirebaseMessaging.instance.requestPermission()` +
///      `FirebaseMessaging.instance.getToken()`, and call
///      `PreciopsApi.registerFcmToken` with the real token.
///   3. Listen to `FirebaseMessaging.onMessage` /
///      `onBackgroundMessage` and route `type: "EMERGENCY_INCOMING_CALL"`
///      data payloads to the masked-call screen the same way
///      `simulateIncomingCall()` does today.
///
/// Local notifications are real and functional today. The only trigger for
/// them is a model-determined high flood risk (`HighRiskAlertEvent` on
/// `dashboardEventStreamProvider`, see `stream_providers.dart`) — no
/// citizen/user action (filing or verifying a report) fires a push.
class NotificationService {
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) {
      // flutter_local_notifications has no Web backend at all — use the
      // browser's native Notification API instead (see web_notifier.dart).
      await requestWebNotificationPermission();
      _initialized = true;
      return;
    }
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );
    } catch (_) {
      // Desktop platforms with no flutter_local_notifications backend
      // (e.g. Windows) — proximity/hazard alerts just won't show there.
    }
    _initialized = true;
  }

  /// Stands in for requesting system notification permission + FCM token
  /// registration on first launch (features.docx: "FCM Push Notification
  /// Listener"). Returns a plausible fake token so
  /// `PreciopsApi.registerFcmToken` has something to send.
  Future<String> requestPermissionAndGetMockToken() async {
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    final rand = Random();
    final token = 'mock-fcm-token-${List.generate(24, (_) => rand.nextInt(16).toRadixString(16)).join()}';
    debugPrint('[NotificationService] mock FCM token: $token');
    return token;
  }

  Future<void> showRiskAlert({
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();
    if (kIsWeb) {
      showWebNotification(title: title, body: body);
      return;
    }
    const androidDetails = AndroidNotificationDetails(
      'flood_risk_high',
      'High Flood Risk Alerts',
      channelDescription: 'Alerts when the flood risk model flags a district as high-risk',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );
    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
      );
    } catch (_) {
      // Desktop platforms with no flutter_local_notifications backend
      // (e.g. Windows) — fail silently rather than crash the caller.
    }
  }

  /// Alerts an official the moment a citizen files a new SOS
  /// (`NewSosPendingEvent` — see [sosPushNotifierProvider] in
  /// `stream_providers.dart`), so dispatch doesn't depend on someone
  /// happening to have the SOS Dashboard open.
  Future<void> showSosAlert({
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();
    if (kIsWeb) {
      showWebNotification(title: title, body: body);
      return;
    }
    const androidDetails = AndroidNotificationDetails(
      'new_sos_reports',
      'New SOS Reports',
      channelDescription: 'Alerts officials the moment a citizen files a new SOS report',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );
    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
      );
    } catch (_) {
      // Desktop platforms with no flutter_local_notifications backend
      // (e.g. Windows) — fail silently rather than crash the caller.
    }
  }
}
