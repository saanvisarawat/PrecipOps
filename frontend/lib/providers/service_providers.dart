import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/fcm_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/offline_queue_service.dart';
import '../services/secure_storage_service.dart';
import '../services/sms_fallback_service.dart';

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final offlineQueueServiceProvider = Provider<OfflineQueueService>((ref) {
  return OfflineQueueService();
});

final smsFallbackServiceProvider = Provider<SmsFallbackService>((ref) {
  return SmsFallbackService();
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService();
});

/// Whether `Firebase.initializeApp()` succeeded at launch — overridden in
/// `main.dart` with the real result. Defaults to false so anything that
/// reads it outside the real app entry point still behaves safely.
final firebaseReadyProvider = Provider<bool>((ref) => false);
