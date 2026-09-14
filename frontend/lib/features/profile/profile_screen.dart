import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models/auth_models.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/api_base_url_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/secure_storage_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_button.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          children: [
            if (!auth.isLoggedIn) ...[
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: const Icon(Icons.person_outline, size: 34, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Not signed in', style: AppTypography.screenTitle(), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                'Preciops now requires an account for every role — sign in to '
                'reach your Predictor, Responder or Citizen dashboard.',
                style: AppTypography.body(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.section),
              AppButton(label: 'Sign In', onPressed: () => context.push('/login')),
              const SizedBox(height: AppSpacing.sm),
              AppButton.secondary(
                label: 'Create an Account',
                onPressed: () => context.push('/register'),
              ),
            ] else ...[
              AppCard(
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                      child: Text(
                        auth.user!.fullName.isNotEmpty ? auth.user!.fullName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(auth.user!.fullName, style: AppTypography.cardTitle().copyWith(fontSize: 16)),
                          Text(auth.user!.email, style: AppTypography.label()),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              auth.user!.role.label,
                              style: AppTypography.caption(color: AppColors.accent).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.section),
            ],
            Text('MENU', style: AppTypography.caption().copyWith(letterSpacing: 1)),
            const SizedBox(height: AppSpacing.compact),
            _SettingsSection(
              rows: [
                _SettingsRowData(
                  icon: Icons.map_outlined,
                  title: 'Offline Maps',
                  subtitle: 'Download districts for offline navigation',
                  onTap: () => context.push('/offline-maps'),
                ),
                _SettingsRowData(
                  icon: Icons.dns_outlined,
                  title: 'Backend Server (Dev)',
                  subtitle: ref.watch(apiBaseUrlOverrideProvider)?.isNotEmpty == true
                      ? ref.watch(apiBaseUrlOverrideProvider)!
                      : '${Env.apiBaseUrl} (default)',
                  onTap: () => _showBackendUrlDialog(context, ref),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.section),
            if (auth.isLoggedIn) ...[
              if (auth.user!.role == UserRole.volunteer || auth.user!.role == UserRole.official) ...[
                _SettingsSection(
                  rows: [
                    if (auth.user!.role == UserRole.volunteer) ...[
                      _SettingsRowData(
                        icon: Icons.shield_outlined,
                        title: 'Responder Dashboard',
                        subtitle: 'Tactical map, routing, protocol & analytics',
                        onTap: () => context.push('/responder'),
                      ),
                      _SettingsRowData(
                        icon: Icons.volunteer_activism_outlined,
                        title: 'Volunteer Command Hub',
                        subtitle: 'Duty status, skills, assigned tasks, masked calling',
                        onTap: () => context.push('/volunteer-hub'),
                      ),
                    ],
                    if (auth.user!.role == UserRole.official) ...[
                      _SettingsRowData(
                        icon: Icons.satellite_alt_outlined,
                        title: 'Predictor Dashboard',
                        subtitle: '4-Pillar HUD, inundation map, time-lapse',
                        onTap: () => context.push('/predictor'),
                      ),
                      _SettingsRowData(
                        icon: Icons.list_alt_outlined,
                        title: 'Legacy SOS Dashboard',
                        subtitle: 'Every citizen report, manual dispatch',
                        onTap: () => context.push('/sos-dashboard'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.section),
              ],
              AppButton.secondary(
                label: 'Sign Out',
                icon: Icons.logout,
                color: AppColors.danger,
                onPressed: () => ref.read(authProvider.notifier).logout(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lets a developer point this build at a different backend at runtime —
/// no rebuild needed — which matters most for a physical device on Wi-Fi:
/// the dev machine's LAN IP changes per test network, so it can't be a
/// good compile-time `--dart-define` default. Quick-select chips cover
/// the three documented targets from [Env]'s doc comment; the text field
/// takes anything else (e.g. a LAN IP). Persisted via
/// [SecureStorageService] so it survives an app restart.
Future<void> _showBackendUrlDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(apiBaseUrlOverrideProvider);
  final controller = TextEditingController(text: current ?? '');
  const presets = [
    ('Deployed (default)', ''),
    ('Android Emulator', 'http://10.0.2.2:8000'),
    ('Web/Desktop — localhost', 'http://127.0.0.1:8000'),
  ];

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Backend Server (Dev)', style: AppTypography.sectionTitle()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Overrides the default backend for local testing — e.g. a physical '
              'device on Wi-Fi pointed at your dev machine\'s LAN IP.',
              style: AppTypography.body(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, url) in presets)
                  ActionChip(
                    label: Text(label, style: AppTypography.label()),
                    backgroundColor: AppColors.surfaceHigh,
                    side: const BorderSide(color: AppColors.cardBorder),
                    onPressed: () => setDialogState(() => controller.text = url),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: controller,
              style: AppTypography.body(),
              decoration: const InputDecoration(
                hintText: 'http://192.168.x.x:8000',
                labelText: 'Custom base URL (blank = default)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel', style: AppTypography.label()),
          ),
          TextButton(
            onPressed: () async {
              final value = controller.text.trim();
              ref.read(apiBaseUrlOverrideProvider.notifier).state = value.isEmpty ? null : value;
              await SecureStorageService().saveApiBaseUrlOverride(value.isEmpty ? null : value);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text('Save', style: AppTypography.label(color: AppColors.accent).copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ),
  );
}

class _SettingsRowData {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsRowData({required this.icon, required this.title, required this.subtitle, required this.onTap});
}

/// A grouped iOS-Settings-style section — one rounded surface holding
/// several rows, separated by hairlines rather than each being its own
/// floating card.
class _SettingsSection extends StatelessWidget {
  final List<_SettingsRowData> rows;
  const _SettingsSection({required this.rows});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _SettingsRow(data: rows[i]),
            if (i != rows.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Divider(height: 1),
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final _SettingsRowData data;
  const _SettingsRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        splashColor: AppColors.accentGlow,
        highlightColor: AppColors.accent.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.icon, color: AppColors.accent, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.title, style: AppTypography.cardTitle().copyWith(fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(data.subtitle, style: AppTypography.caption()),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
