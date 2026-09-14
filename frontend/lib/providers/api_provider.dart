import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_floodops_api.dart';
import '../api/floodops_api.dart';
import '../api/mock/mock_floodops_api.dart';
import '../core/config/env.dart';

/// The ONLY place the mock/real backend choice is made. Every screen and
/// controller reads [PreciopsApi] through this provider — never
/// instantiates `MockPreciopsApi` directly. Going live is a one-flag
/// change: flip `Env.useMockApi` to false (or pass
/// `--dart-define=USE_MOCK_API=false --dart-define=API_BASE_URL=...`).
final preciopsApiProvider = Provider<PreciopsApi>((ref) {
  final PreciopsApi api = Env.useMockApi
      ? MockPreciopsApi()
      : DioPreciopsApi(baseUrl: Env.apiBaseUrl, wsBaseUrl: Env.wsBaseUrl);
  ref.onDispose(api.dispose);
  return api;
});
