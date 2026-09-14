import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True network connectivity (Wi-Fi or mobile data reachable at the OS
/// level). Drives both the offline SOS queue (module 2) and the
/// zero-connectivity SMS fallback (module 3).
final connectivityStreamProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

final isOnlineProvider = Provider<bool>((ref) {
  final conn = ref.watch(connectivityStreamProvider);
  return conn.maybeWhen(
    data: (results) => results.any((r) => r != ConnectivityResult.none),
    orElse: () => true,
  );
});
