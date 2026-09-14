import 'dart:html' as html;

/// `flutter_local_notifications` has no Web backend at all (only Android/
/// iOS/macOS/Linux), so on Flutter Web this uses the browser's native
/// Notification API directly instead.
Future<bool> requestWebNotificationPermission() async {
  if (!html.Notification.supported) return false;
  if (html.Notification.permission == 'granted') return true;
  final permission = await html.Notification.requestPermission();
  return permission == 'granted';
}

void showWebNotification({required String title, required String body}) {
  if (!html.Notification.supported) return;
  if (html.Notification.permission != 'granted') return;
  html.Notification(title, body: body);
}
