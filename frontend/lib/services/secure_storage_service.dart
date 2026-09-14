import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps flutter_secure_storage for the auth token and current user.
/// Used for both mock and real auth — the token format doesn't matter to
/// this service, it just persists whatever string it's given.
///
/// On Web, `flutter_secure_storage` encrypts values via the browser's Web
/// Crypto API, which browsers only expose in a "secure context" (HTTPS, or
/// `localhost`) — opening the app from a plain-HTTP LAN address (e.g.
/// testing on a phone against a dev machine's IP) makes every read/write
/// throw, which used to surface as a flat "Registration failed."/"Login
/// failed." with no clue why. This now falls back to a simple in-memory
/// store the first time that happens, so auth still works for the
/// session (just doesn't survive a page reload) instead of failing
/// outright.
class SecureStorageService {
  SecureStorageService() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final Map<String, String> _memoryFallback = {};
  bool _useMemoryFallback = false;

  static const _tokenKey = 'floodops_auth_token';
  static const _userIdKey = 'floodops_user_id';
  static const _userNameKey = 'floodops_user_name';
  static const _userEmailKey = 'floodops_user_email';
  static const _userRoleKey = 'floodops_user_role';
  static const _apiBaseUrlOverrideKey = 'preciops_api_base_url_override';

  Future<void> _write(String key, String value) async {
    if (_useMemoryFallback) {
      _memoryFallback[key] = value;
      return;
    }
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Web Crypto unavailable (insecure context) or another platform
      // storage failure — switch to memory for the rest of this session
      // rather than failing the caller.
      _useMemoryFallback = true;
      _memoryFallback[key] = value;
    }
  }

  Future<String?> _read(String key) async {
    if (_useMemoryFallback) return _memoryFallback[key];
    try {
      return await _storage.read(key: key);
    } catch (_) {
      _useMemoryFallback = true;
      return _memoryFallback[key];
    }
  }

  Future<void> _delete(String key) async {
    if (_useMemoryFallback) {
      _memoryFallback.remove(key);
      return;
    }
    try {
      await _storage.delete(key: key);
    } catch (_) {
      _useMemoryFallback = true;
      _memoryFallback.remove(key);
    }
  }

  Future<void> saveSession({
    required String token,
    required String userId,
    required String fullName,
    required String email,
    required String role,
  }) async {
    await Future.wait([
      _write(_tokenKey, token),
      _write(_userIdKey, userId),
      _write(_userNameKey, fullName),
      _write(_userEmailKey, email),
      _write(_userRoleKey, role),
    ]);
  }

  Future<Map<String, String>?> readSession() async {
    final token = await _read(_tokenKey);
    if (token == null) return null;
    final userId = await _read(_userIdKey);
    final fullName = await _read(_userNameKey);
    final email = await _read(_userEmailKey);
    final role = await _read(_userRoleKey);
    if (userId == null || fullName == null || email == null || role == null) return null;
    return {
      'token': token,
      'userId': userId,
      'fullName': fullName,
      'email': email,
      'role': role,
    };
  }

  Future<void> clearSession() async {
    await Future.wait([
      _delete(_tokenKey),
      _delete(_userIdKey),
      _delete(_userNameKey),
      _delete(_userEmailKey),
      _delete(_userRoleKey),
    ]);
  }

  /// A developer-set override for [Env.apiBaseUrl] — e.g. a physical
  /// device on Wi-Fi pointed at a dev machine's LAN IP, which changes per
  /// test machine/network and so can't be a compile-time `--dart-define`
  /// default. Persisted so it survives an app restart; null/empty means
  /// "use the built-in default."
  Future<void> saveApiBaseUrlOverride(String? url) async {
    if (url == null || url.trim().isEmpty) {
      await _delete(_apiBaseUrlOverrideKey);
    } else {
      await _write(_apiBaseUrlOverrideKey, url.trim());
    }
  }

  Future<String?> readApiBaseUrlOverride() => _read(_apiBaseUrlOverrideKey);
}
