import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// The single seam for pointing this app at a real backend.
///
/// Defaults to a local `uvicorn app.main:app --host 0.0.0.0 --port 8000`
/// run of the Preciops FastAPI backend (PS 26071 isn't deployed anywhere
/// public yet), picking the right localhost address per platform:
///   - Flutter Web/Desktop     -> http://127.0.0.1:8000
///   - Android Emulator        -> http://10.0.2.2:8000 (its alias for the
///                                 host machine's localhost)
///   - Physical device on Wi-Fi -> not auto-detectable (there's no host
///     loopback across two separate machines) — override explicitly with
///     `--dart-define=API_BASE_URL=http://<PC_IP>:8000` pointed at
///     whatever machine is running uvicorn.
///
/// Pass `--dart-define=USE_MOCK_API=true` to opt into the mock for
/// offline demoing instead. No screen imports this file directly except
/// `providers/api_provider.dart`, which is the only place the mock/real
/// choice is made.
class Env {
  Env._();

  static const bool useMockApi = bool.fromEnvironment(
    'USE_MOCK_API',
    defaultValue: false,
  );

  static const String _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  static const String _wsBaseUrlOverride = String.fromEnvironment('WS_BASE_URL', defaultValue: '');

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static String get apiBaseUrl =>
      _apiBaseUrlOverride.isNotEmpty ? _apiBaseUrlOverride : (_isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000');

  static String get wsBaseUrl =>
      _wsBaseUrlOverride.isNotEmpty ? _wsBaseUrlOverride : (_isAndroid ? 'ws://10.0.2.2:8000' : 'ws://127.0.0.1:8000');
}
