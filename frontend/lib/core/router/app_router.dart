import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/agent_hub/agent_hub_screen.dart';
import '../../features/alerts/alerts_screen.dart';
import '../../features/alerts/pending_alerts_screen.dart';
import '../../features/official/official_sos_dashboard_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/root_gate.dart';
import '../../features/navigation/models/nav_destination.dart';
import '../../features/navigation/screens/navigation_map_screen.dart';
import '../../features/navigation/screens/offline_maps_screen.dart';
import '../../features/predictor/predictor_dashboard_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/responder/responder_dashboard_screen.dart';
import '../../features/shelters/shelters_near_me_screen.dart';
import '../../features/sos/offline_queue_screen.dart';
import '../../features/voice/voice_agent_screen.dart';
import '../../features/volunteer/masked_call_screen.dart';
import '../../features/volunteer/volunteer_hub_screen.dart';
import '../../api/models/volunteer_models.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const RootGate()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
    GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
    GoRoute(path: '/predictor', builder: (context, state) => const PredictorDashboardScreen()),
    GoRoute(path: '/responder', builder: (context, state) => const ResponderDashboardScreen()),
    GoRoute(path: '/offline-queue', builder: (context, state) => const OfflineQueueScreen()),
    GoRoute(path: '/volunteer-hub', builder: (context, state) => const VolunteerHubScreen()),
    GoRoute(path: '/agent-hub', builder: (context, state) => const AgentHubScreen()),
    GoRoute(
      path: '/navigate',
      builder: (context, state) => NavigationMapScreen(initialDestination: state.extra as NavDestination?),
    ),
    GoRoute(path: '/offline-maps', builder: (context, state) => const OfflineMapsScreen()),
    GoRoute(path: '/voice-agent', builder: (context, state) => const VoiceAgentScreen()),
    GoRoute(path: '/alerts', builder: (context, state) => const AlertsScreen()),
    GoRoute(path: '/pending-alerts', builder: (context, state) => const PendingAlertsScreen()),
    GoRoute(path: '/sos-dashboard', builder: (context, state) => const OfficialSosDashboardScreen()),
    GoRoute(path: '/shelters-near-me', builder: (context, state) => const SheltersNearMeScreen()),
    GoRoute(
      path: '/masked-call',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        opaque: true,
        child: MaskedCallScreen(payload: state.extra as MaskedCallPayload),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          );
        },
      ),
    ),
  ],
);
