import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/api_provider.dart';
import 'providers/service_providers.dart';
import 'providers/stream_providers.dart';
import 'services/fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase.initializeApp() fails harmlessly (see fcm_service.dart) until
  // a real Firebase project is wired up via `flutterfire configure` — only
  // register the background handler when it actually succeeds, since
  // FirebaseMessaging.onBackgroundMessage requires an initialized app.
  final firebaseReady = await FcmService().initializeFirebase();
  if (firebaseReady) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  runApp(ProviderScope(
    overrides: [firebaseReadyProvider.overrideWithValue(firebaseReady)],
    child: const PreciopsApp(),
  ));
}

class PreciopsApp extends ConsumerStatefulWidget {
  const PreciopsApp({super.key});

  @override
  ConsumerState<PreciopsApp> createState() => _PreciopsAppState();
}

class _PreciopsAppState extends ConsumerState<PreciopsApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFirstLaunch());
  }

  /// Module 1: request notification permission and register an FCM token
  /// on first launch — a real device token once Firebase is configured
  /// (see fcm_service.dart), the existing mock token otherwise so nothing
  /// about today's demo behavior changes until then.
  Future<void> _onFirstLaunch() async {
    final firebaseReady = ref.read(firebaseReadyProvider);
    String? token;
    if (firebaseReady) {
      token = await ref.read(fcmServiceProvider).requestPermissionAndGetRealToken();
    }
    if (token == null) {
      final notifications = ref.read(notificationServiceProvider);
      try {
        await notifications.init();
        token = await notifications.requestPermissionAndGetMockToken();
      } catch (_) {
        // Local notifications plugin has no web/desktop backend in this dev
        // environment — safe to skip on platforms where it isn't available.
        token = 'mock-fcm-token-unavailable-on-this-platform';
      }
    }
    final api = ref.read(preciopsApiProvider);
    try {
      await api.registerFcmToken(token);
    } catch (_) {
      // Real /api/users/fcm-token requires a logged-in user — this runs
      // at cold boot, before anyone (citizen or not-yet-logged-in
      // volunteer) has necessarily logged in, so a 401 here is expected
      // and must not stop the masked-call listener below from being
      // wired up. It previously did, silently, since this call had no
      // error handling at all.
    }

    // Real masked calls: foreground / tapped-from-background / tapped-
    // from-terminated all funnel into deliverIncomingCall, which feeds the
    // exact same stream the debug trigger (simulateIncomingCall) does.
    if (firebaseReady) {
      ref.read(fcmServiceProvider).listenForMaskedCalls((payload) {
        ref.read(preciopsApiProvider).deliverIncomingCall(payload);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // App-wide listener: pushes the fullscreen masked-call UI whenever an
    // incoming-call payload arrives, whether from the debug trigger, a
    // real foreground/background FCM message, or a terminated-state tap.
    ref.listen(incomingCallStreamProvider, (previous, next) {
      next.whenData((payload) {
        appRouter.push('/masked-call', extra: payload);
      });
    });

    return MaterialApp.router(
      title: 'Preciops',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
    );
  }
}
