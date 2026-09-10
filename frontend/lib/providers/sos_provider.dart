import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../api/floodops_api.dart';
import 'api_provider.dart';
import 'connectivity_provider.dart';
import 'service_providers.dart';

enum SosOutcomeKind { submitted, queuedOffline, failed }

class SosOutcome {
  final SosOutcomeKind kind;
  final String? ticketId;
  final String? message;
  final String? assignedVolunteerId;
  const SosOutcome(this.kind, {this.ticketId, this.message, this.assignedVolunteerId});
}

final offlineQueueCountProvider = FutureProvider<int>((ref) async {
  final service = ref.watch(offlineQueueServiceProvider);
  return service.count();
});

class SosController extends Notifier<bool> {
  @override
  bool build() => false; // isSubmitting

  Future<SosOutcome> submit({
    required String description,
    required double latitude,
    required double longitude,
  }) async {
    state = true;
    final clientTimestamp = DateTime.now();
    final request = CreateReportRequest(
      clientId: const Uuid().v4(),
      description: description,
      latitude: latitude,
      longitude: longitude,
      clientTimestamp: clientTimestamp,
    );

    final isOnline = ref.read(isOnlineProvider);
    try {
      if (isOnline) {
        final api = ref.read(preciopsApiProvider);
        final report = await api.createReport(request);
        state = false;
        return SosOutcome(
          SosOutcomeKind.submitted,
          ticketId: report.ticketId,
          assignedVolunteerId: report.assignedVolunteerId,
        );
      } else {
        final queue = ref.read(offlineQueueServiceProvider);
        await queue.enqueue(request);
        ref.invalidate(offlineQueueCountProvider);
        state = false;
        return const SosOutcome(SosOutcomeKind.queuedOffline);
      }
    } catch (e) {
      // Network call failed even though connectivity looked available —
      // fall back to the offline queue so the report is never lost.
      final queue = ref.read(offlineQueueServiceProvider);
      await queue.enqueue(request);
      ref.invalidate(offlineQueueCountProvider);
      state = false;
      return SosOutcome(SosOutcomeKind.queuedOffline, message: e.toString());
    }
  }

  /// Drains the local queue via bulk sync. Called automatically when
  /// connectivity transitions offline -> online (see AppShell) and can
  /// also be triggered manually from the offline queue screen.
  Future<int> syncQueue() async {
    final queue = ref.read(offlineQueueServiceProvider);
    final pending = await queue.getAll();
    if (pending.isEmpty) return 0;
    final api = ref.read(preciopsApiProvider);
    final result = await api.bulkSyncReports(pending);
    await queue.removeByClientIds(result.syncedClientIds);
    // Duplicates are also safe to drop locally — the backend already has
    // an equivalent report.
    await queue.removeByClientIds(result.duplicateClientIds);
    ref.invalidate(offlineQueueCountProvider);
    return result.syncedClientIds.length;
  }
}

final sosControllerProvider = NotifierProvider<SosController, bool>(SosController.new);
