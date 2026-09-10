import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../services/lite_sos_queue_service.dart';
import 'api_provider.dart';

enum LiteSosOutcome { sent, queuedRetrying }

final liteSosQueueServiceProvider = Provider<LiteSosQueueService>((ref) {
  return LiteSosQueueService();
});

/// Pending count for the Lite SOS retry queue — mirrors
/// `offlineQueueCountProvider`'s shape for the richer SOS flow.
final liteSosPendingCountProvider = FutureProvider<int>((ref) async {
  return ref.watch(liteSosQueueServiceProvider).count();
});

/// Drives POST /api/reports/lite with real "keep pinging until 200 OK"
/// behavior: every submission is persisted locally first (so it survives
/// the app being killed on a bad connection), an immediate send is
/// attempted, and — whether that immediate attempt succeeds or not — a
/// background retry loop keeps periodically retrying every row still in
/// the queue until each one gets a successful response, then removes it.
/// Also resumes any lite SOS left over from a previous session the
/// moment the app launches (see where this provider is watched in
/// `ShellScreen`).
class LiteSosController extends Notifier<bool> {
  static const _retryInterval = Duration(seconds: 8);
  Timer? _retryTimer;

  @override
  bool build() {
    ref.onDispose(() => _retryTimer?.cancel());
    _ensureRetryLoop();
    return false; // isSubmitting
  }

  Future<LiteSosOutcome> submit({
    required double lat,
    required double lng,
    required String description,
  }) async {
    state = true;
    final request = LiteSosRequest(
      clientId: const Uuid().v4(),
      latitude: lat,
      longitude: lng,
      description: description,
    );
    await ref.read(liteSosQueueServiceProvider).enqueue(request);
    ref.invalidate(liteSosPendingCountProvider);

    final sent = await _trySend(request);
    state = false;
    _ensureRetryLoop();
    return sent ? LiteSosOutcome.sent : LiteSosOutcome.queuedRetrying;
  }

  Future<bool> _trySend(LiteSosRequest request) async {
    try {
      await ref.read(preciopsApiProvider).sendLiteSos(
            lat: request.latitude,
            lng: request.longitude,
            description: request.description,
          );
      await ref.read(liteSosQueueServiceProvider).remove(request.clientId);
      ref.invalidate(liteSosPendingCountProvider);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _ensureRetryLoop() {
    if (_retryTimer != null) return;
    _retryTimer = Timer.periodic(_retryInterval, (timer) async {
      final pending = await ref.read(liteSosQueueServiceProvider).getAll();
      if (pending.isEmpty) {
        timer.cancel();
        _retryTimer = null;
        return;
      }
      for (final request in pending) {
        await _trySend(request);
      }
    });
  }
}

final liteSosControllerProvider = NotifierProvider<LiteSosController, bool>(LiteSosController.new);
