import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_floodops_api.dart';
import '../api/floodops_api.dart';
import 'api_provider.dart';
import 'service_providers.dart';

/// Guest-first: citizens never need this. Only Volunteer/Official login
/// touches this provider, and only then is a (mock, for now) JWT written
/// to flutter_secure_storage.
class AuthState {
  final UserProfile? user;
  final String? token;
  final bool isLoading;
  final String? error;
  /// True until the initial `_restoreSession()` check (secure-storage read)
  /// completes — lets `RootGate` show a spinner instead of flashing the
  /// login screen while a previously-saved session might still be loading.
  final bool isRestoring;

  const AuthState({this.user, this.token, this.isLoading = false, this.error, this.isRestoring = true});

  bool get isLoggedIn => user != null && token != null;

  AuthState copyWith({
    UserProfile? user,
    String? token,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? isRestoring,
  }) =>
      AuthState(
        user: user ?? this.user,
        token: token ?? this.token,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
        isRestoring: isRestoring ?? this.isRestoring,
      );
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restoreSession();
    return const AuthState();
  }

  /// `DioPreciopsApi` doesn't accept a fixed token at construction (the
  /// provider that builds it runs before login ever happens) — it reads
  /// `_authToken` fresh on every request via an interceptor. This keeps
  /// that field in sync whenever the session token changes.
  void _syncApiToken(String? token) {
    final api = ref.read(preciopsApiProvider);
    if (api is DioPreciopsApi) api.setAuthToken(token);
  }

  Future<void> _restoreSession() async {
    final storage = ref.read(secureStorageServiceProvider);
    final session = await storage.readSession();
    if (session == null) {
      state = state.copyWith(isRestoring: false);
      return;
    }
    _syncApiToken(session['token']);
    state = state.copyWith(
      token: session['token'],
      user: UserProfile(
        id: session['userId']!,
        fullName: session['fullName']!,
        email: session['email']!,
        role: UserRoleX.fromWire(session['role']!),
      ),
      isRestoring: false,
    );
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final api = ref.read(preciopsApiProvider);
      final res = await api.login(LoginRequest(email: email, password: password));
      _syncApiToken(res.token);
      await _persist(res);
      state = state.copyWith(user: res.user, token: res.token, isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Login failed. Please try again.');
      return false;
    }
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final api = ref.read(preciopsApiProvider);
      final res = await api.register(RegisterRequest(
        fullName: fullName,
        email: email,
        password: password,
        role: role,
      ));
      _syncApiToken(res.token);
      await _persist(res);
      state = state.copyWith(user: res.user, token: res.token, isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Registration failed. Please try again.');
      return false;
    }
  }

  Future<void> _persist(AuthResponse res) async {
    final storage = ref.read(secureStorageServiceProvider);
    await storage.saveSession(
      token: res.token,
      userId: res.user.id,
      fullName: res.user.fullName,
      email: res.user.email,
      role: res.user.role.wire,
    );
  }

  Future<void> logout() async {
    final storage = ref.read(secureStorageServiceProvider);
    await storage.clearSession();
    _syncApiToken(null);
    // AuthState()'s default isRestoring:true is meant for the app's very
    // first boot, cleared once by _restoreSession() — that never runs
    // again after logout, so leaving it at the default left RootGate
    // stuck showing its loading spinner forever instead of the login
    // screen.
    state = const AuthState(isRestoring: false);
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
