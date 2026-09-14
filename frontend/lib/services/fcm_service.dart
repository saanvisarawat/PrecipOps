import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/models/volunteer_models.dart';
import '../firebase_options.dart';

/// Real Firebase Cloud Messaging wiring for masked calls (module 8) — makes
/// `POST /api/emergency/trigger-masked-call` actually ring a volunteer's
/// phone instead of only working through the Volunteer Hub's debug button.
///
/// `flutterfire configure` has been run for this project (flood-ops-b7dd9)
/// covering web/iOS/macOS/Windows — [initializeFirebase] uses the
/// generated `lib/firebase_options.dart`. Android wasn't selected in that
/// run; on Android specifically, `DefaultFirebaseOptions.currentPlatform`
/// throws `UnsupportedError`, which [initializeFirebase] catches the same
/// as "not configured" — re-run `flutterfire configure` (selecting
/// Android this time) to cover that platform too, no other code changes
/// needed.
class FcmService {
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  Future<bool> initializeFirebase() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      return true;
    } catch (_) {
      // Either a platform `flutterfire configure` hasn't covered yet (see
      // class doc), or Firebase not reachable — expected to fail
      // harmlessly until fully configured.
      return false;
    }
  }

  /// Requests notification permission and returns a real FCM device
  /// token, or null if Firebase isn't configured/available on this
  /// platform. Callers should fall back to the existing mock-token flow
  /// when this returns null.
  Future<String?> requestPermissionAndGetRealToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) return null;
      return await messaging.getToken();
    } catch (_) {
      return null;
    }
  }

  /// Wires up all three FCM delivery paths for a `type:
  /// "EMERGENCY_INCOMING_CALL"` data message and routes each into
  /// [onIncomingCall] with the same [MaskedCallPayload] shape the debug
  /// trigger already uses:
  ///   - app in foreground (`onMessage`)
  ///   - app backgrounded, user taps the notification (`onMessageOpenedApp`)
  ///   - app was terminated, user taps the notification (`getInitialMessage`)
  void listenForMaskedCalls(void Function(MaskedCallPayload payload) onIncomingCall) {
    void handle(RemoteMessage message) {
      if (message.data['type'] != 'EMERGENCY_INCOMING_CALL') return;
      onIncomingCall(MaskedCallPayload.fromJson(message.data));
    }

    FirebaseMessaging.onMessage.listen(handle);
    FirebaseMessaging.onMessageOpenedApp.listen(handle);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) handle(message);
    });
  }

  /// Shown by [firebaseMessagingBackgroundHandler] when a masked-call data
  /// message arrives while the app is backgrounded/terminated — there's no
  /// widget tree in that isolate to push the full-screen call UI onto, so
  /// this is the most that can be done there; tapping it re-opens the app,
  /// which `onMessageOpenedApp`/`getInitialMessage` above then routes to
  /// the real screen. Android/iOS only — matches
  /// `NotificationService`'s own platform coverage.
  Future<void> showBackgroundCallNotification(RemoteMessage message) async {
    if (kIsWeb) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );
      const androidDetails = AndroidNotificationDetails(
        'masked_call',
        'Emergency Rescue Dispatch',
        channelDescription: 'A masked call assigning you to an emergency rescue',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
      );
      const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
      final alias = message.data['caller_name'] as String? ?? 'Preciops Emergency';
      await _localNotifications.show(
        Random().nextInt(1 << 31),
        'Incoming Emergency Rescue Dispatch',
        alias,
        details,
      );
    } catch (_) {
      // Best-effort only — never let a background isolate crash on this.
    }
  }
}

/// Must be a top-level (or static) function per the firebase_messaging
/// contract — registered via `FirebaseMessaging.onBackgroundMessage(...)`
/// in `main.dart` before `runApp`. Runs in its own isolate with no access
/// to the app's provider container, so it can only show a local
/// notification, not push the masked-call screen directly.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.data['type'] != 'EMERGENCY_INCOMING_CALL') return;
  await FcmService().showBackgroundCallNotification(message);
}
