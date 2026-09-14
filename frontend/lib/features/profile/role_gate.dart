import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models/auth_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';

/// Wraps role-gated screens (Volunteer/Official) with a friendly
/// "sign in required" state instead of a hard dead-end, satisfying the
/// "everything must demo with zero backend" and "no screen hard-fails"
/// requirements even for logged-out visitors who navigate here directly.
class RoleGate extends StatelessWidget {
  final List<UserRole> allowed;
  final UserRole? currentRole;
  final String featureName;
  final Widget child;

  const RoleGate({
    super.key,
    required this.allowed,
    required this.currentRole,
    required this.featureName,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (currentRole != null && allowed.contains(currentRole)) {
      return child;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: const Icon(Icons.lock_outline_rounded, size: 26, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              currentRole == null
                  ? 'Sign in required'
                  : 'Not available for ${currentRole!.label}s',
              style: AppTypography.sectionTitle(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              currentRole == null
                  ? '${allowed.map((r) => r.label).join(' or ')} sign-in is needed to open $featureName.'
                  : '$featureName is only available to ${allowed.map((r) => r.label).join(' or ')} accounts.',
              style: AppTypography.body(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.comfortable),
            if (currentRole == null)
              AppButton(
                label: 'Sign In',
                expand: false,
                onPressed: () => context.push('/login'),
              ),
          ],
        ),
      ),
    );
  }
}
