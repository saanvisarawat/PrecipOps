import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models/report_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/service_providers.dart';
import '../../providers/sos_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/app_toast.dart';

/// Real, working offline queue view — every report shown here is read
/// straight out of the on-device sqflite database written by
/// [OfflineQueueService], not mocked.
class OfflineQueueScreen extends ConsumerStatefulWidget {
  const OfflineQueueScreen({super.key});

  @override
  ConsumerState<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends ConsumerState<OfflineQueueScreen> {
  List<CreateReportRequest>? _queued;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final queue = ref.read(offlineQueueServiceProvider);
    final items = await queue.getAll();
    if (mounted) setState(() => _queued = items);
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final synced = await ref.read(sosControllerProvider.notifier).syncQueue();
    await _load();
    if (mounted) {
      setState(() => _syncing = false);
      AppToast.show(
        context,
        synced > 0 ? 'Synced $synced report(s).' : 'Nothing to sync yet.',
        kind: synced > 0 ? AppToastKind.success : AppToastKind.neutral,
      );
    }
  }

  Future<void> _sendSms(CreateReportRequest r) async {
    final sms = ref.read(smsFallbackServiceProvider);
    await sms.sendFallbackSms(
      latitude: r.latitude,
      longitude: r.longitude,
      description: r.description,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(isOnlineProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Offline SOS Queue')),
      body: _queued == null
          ? ListView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: AppSkeleton(height: 88, borderRadius: AppRadius.cardR),
                  ),
              ],
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.comfortable,
                    AppSpacing.screenPadding,
                    AppSpacing.xs,
                  ),
                  child: AppCard(
                    color: AppColors.surfaceRaised,
                    child: Row(
                      children: [
                        Icon(
                          isOnline ? Icons.cloud_done_outlined : Icons.cloud_off,
                          color: isOnline ? AppColors.accent : AppColors.warning,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            isOnline
                                ? 'Online — queued reports sync automatically.'
                                : 'Offline — reports stay queued on this device until connection returns.',
                            style: AppTypography.body(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _queued!.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.inbox_outlined, color: AppColors.textTertiary, size: 28),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'No queued reports',
                                style: AppTypography.body(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(AppSpacing.screenPadding),
                          itemCount: _queued!.length,
                          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, i) {
                            final r = _queued![i];
                            return AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.description, style: AppTypography.cardTitle().copyWith(fontSize: 14.5)),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${r.latitude.toStringAsFixed(5)}, ${r.longitude.toStringAsFixed(5)}'
                                    ' • queued ${DateFormat.MMMd().add_Hm().format(r.clientTimestamp)}',
                                    style: AppTypography.caption(),
                                  ),
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: AppButton.tertiary(
                                      label: 'Send via SMS instead',
                                      icon: Icons.sms_outlined,
                                      onPressed: () => _sendSms(r),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenPadding),
                  child: AppButton(
                    label: _syncing ? 'Syncing…' : 'Sync now',
                    icon: Icons.sync,
                    isLoading: _syncing,
                    onPressed: (_queued!.isEmpty || _syncing) ? null : _sync,
                  ),
                ),
              ],
            ),
    );
  }
}
