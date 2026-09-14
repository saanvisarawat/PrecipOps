import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runtime override for [Env.apiBaseUrl] — set from the Profile screen's
/// "Backend Server (Dev)" row, persisted via [SecureStorageService].
/// null/empty means "use the built-in default" (the deployed Render
/// backend, or an emulator/localhost `--dart-define`). Overriding here
/// lets a physical device on Wi-Fi point at a dev machine's LAN IP
/// without a rebuild — that IP changes per test machine/network, so it
/// can never be a good compile-time default.
final apiBaseUrlOverrideProvider = StateProvider<String?>((ref) => null);
