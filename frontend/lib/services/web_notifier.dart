// Conditional export: the real browser-Notification-API implementation on
// Web, a no-op stub everywhere else (native platforms use
// `flutter_local_notifications` instead — see `notification_service.dart`).
export 'web_notifier_stub.dart' if (dart.library.html) 'web_notifier_web.dart';
