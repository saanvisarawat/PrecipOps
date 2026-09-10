import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models/dashboard_event_models.dart';
import '../../providers/lite_sos_provider.dart';
import '../../providers/shell_nav_provider.dart';
import '../../providers/stream_providers.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/glass_bottom_nav.dart';
import '../chat/ragbot_screen.dart';
import '../citizen/citizen_dashboard_screen.dart';
import '../hub/hub_screen.dart';
import '../map/evacuation_map_screen.dart';
import '../verification/verification_feed_screen.dart';

/// The Citizen shell (post-login, CITIZEN role only): Home, Hub,
/// Evacuation Map, Ragbot, Verify. Tab index lives in
/// [shellTabIndexProvider] so other screens (the Hub) can switch tabs
/// without pushing a duplicate stacked route.
class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key});

  static const _titles = ['Preciops', 'Hub', 'Evacuation Map', 'Ragbot', 'Verify'];

  static const _screens = [
    CitizenDashboardScreen(),
    HubScreen(),
    EvacuationMapScreen(),
    RagbotScreen(),
    VerificationFeedScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellTabIndexProvider);
    // Wires up the model-risk push notifier for the whole app session —
    // this must be watched somewhere always-mounted (not e.g. inside the
    // Alerts tab) so a high-risk alert notifies the user regardless of
    // which screen they're currently on.
    ref.watch(riskPushNotifierProvider);

    // Resumes the Lite SOS retry loop for anything left queued from a
    // previous session — same "always-mounted" reasoning as above.
    ref.watch(liteSosControllerProvider);

    // In-app fallback banner: OS-level push depends on the browser/device
    // actually granting notification permission (never guaranteed — the
    // user may have dismissed/blocked the prompt, or be on a platform
    // `flutter_local_notifications` doesn't support, e.g. Windows
    // desktop). This toast has no such dependency, so a model-flagged
    // high-risk district is always visibly surfaced at least while the
    // app is open, on any tab.
    ref.listen<AsyncValue<DashboardEvent>>(dashboardEventStreamProvider, (previous, next) {
      next.whenData((event) {
        if (event is HighRiskAlertEvent) {
          AppToast.show(
            context,
            'High Flood Risk — ${event.district}: model risk score ${event.riskScore}% (${event.alertLevel}).',
            kind: AppToastKind.error,
          );
        }
      });
    });

    // Home builds its own top bar (greeting + avatar) per its spec, and the
    // Map tab is a full-bleed Apple-Maps-style surface with its own
    // floating controls — neither gets a default AppBar. Every other tab
    // keeps the shared one.
    return Scaffold(
      appBar: index == 0 || index == 2
          ? null
          : AppBar(
              title: Text(_titles[index]),
              actions: [
                IconButton(
                  icon: const Icon(Icons.account_circle_outlined, size: 28),
                  tooltip: 'Profile',
                  onPressed: () => context.push('/profile'),
                ),
                const SizedBox(width: 4),
              ],
            ),
      extendBody: true,
      body: IndexedStack(index: index, children: _screens),
      bottomNavigationBar: GlassBottomNav(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(shellTabIndexProvider.notifier).state = i,
        items: const [
          GlassBottomNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
          GlassBottomNavItem(icon: Icons.grid_view_outlined, selectedIcon: Icons.grid_view, label: 'Hub'),
          GlassBottomNavItem(icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Map'),
          GlassBottomNavItem(icon: Icons.chat_bubble_outline, selectedIcon: Icons.chat_bubble, label: 'Ragbot'),
          GlassBottomNavItem(icon: Icons.fact_check_outlined, selectedIcon: Icons.fact_check, label: 'Verify'),
        ],
      ),
    );
  }
}
