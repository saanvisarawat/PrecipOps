import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_role.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../dashboard/shell_screen.dart';
import '../predictor/predictor_dashboard_screen.dart';
import '../responder/responder_dashboard_screen.dart';
import 'login_screen.dart';

/// The app's actual root: no more guest-first bypass. Everyone signs in,
/// then lands on exactly one of three dashboards decided by [AppRole] —
/// this is "genuinely three different dashboards behind one login screen."
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    if (auth.isRestoring) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.4)),
      );
    }

    if (!auth.isLoggedIn) {
      return const LoginScreen();
    }

    switch (AppRoleX.fromLegacy(auth.user!.role)) {
      case AppRole.predictor:
        return const PredictorDashboardScreen();
      case AppRole.responder:
        return const ResponderDashboardScreen();
      case AppRole.citizen:
        return const ShellScreen();
    }
  }
}
