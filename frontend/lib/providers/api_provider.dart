import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_floodops_api.dart';
import '../api/floodops_api.dart';
import '../api/mock/mock_floodops_api.dart';
import '../core/config/env.dart';
import 'api_base_url_provider.dart';

/// The ONLY place the mock/real backend choice is made. Every screen and
/// controller reads [PreciopsApi] through this provider — never
/// instantiates `MockPreciopsApi` directly. Going live is a one-flag
/// change: flip `Env.useMockApi` to false (or pass
/// `--dart-define=USE_MOCK_API=false --dart-define=API_BASE_URL=...`).
///
/// Watches [apiBaseUrlOverrideProvider] so setting a dev override from
/// the Profile screen rebuilds the Dio client against the new host
/// immediately, no restart needed.
final preciopsApiProvider = Provider<PreciopsApi>((ref) {
  final override = ref.watch(apiBaseUrlOverrideProvider);
  final baseUrl = (override != null && override.isNotEmpty) ? override : Env.apiBaseUrl;
  final PreciopsApi api =
      Env.useMockApi ? MockPreciopsApi() : DioPreciopsApi(baseUrl: baseUrl, wsBaseUrl: Env.wsBaseUrl);
  ref.onDispose(api.dispose);
  return api;
});
