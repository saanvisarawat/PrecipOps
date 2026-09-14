/// The single seam for pointing this app at a real backend.
///
/// Defaults to the deployed Render backend — this same web build is served
/// live to real users via Vercel with no build-time `--dart-define`, so the
/// default here has to be a backend everyone can actually reach, not a
/// developer's own localhost. Override for local development instead:
///   - Flutter Web/Desktop      -> `--dart-define=API_BASE_URL=http://127.0.0.1:8000`
///   - Android Emulator         -> `--dart-define=API_BASE_URL=http://10.0.2.2:8000`
///     (10.0.2.2 is the emulator's alias for the host machine's localhost)
///   - Physical device on Wi-Fi -> `--dart-define=API_BASE_URL=http://<PC_IP>:8000`
///     pointed at whatever machine is running uvicorn
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

  static String get apiBaseUrl =>
      _apiBaseUrlOverride.isNotEmpty ? _apiBaseUrlOverride : 'https://floodops-decodesih-3mrj.onrender.com';

  static String get wsBaseUrl =>
      _wsBaseUrlOverride.isNotEmpty ? _wsBaseUrlOverride : 'wss://floodops-decodesih-3mrj.onrender.com';
}
