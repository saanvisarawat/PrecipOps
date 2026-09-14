/// Non-web fallback for `web_notifier_web.dart` — `dart:html` doesn't
/// exist on native platforms, so this no-op stub is what gets compiled in
/// there instead (see the conditional export in `web_notifier.dart`).
Future<bool> requestWebNotificationPermission() async => false;

void showWebNotification({required String title, required String body}) {}
