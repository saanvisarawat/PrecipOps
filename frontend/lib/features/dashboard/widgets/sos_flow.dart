import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/kerala_districts.dart';
import '../../../providers/service_providers.dart';
import '../../../providers/sos_provider.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/app_toast.dart';
import 'sos_composer_sheet.dart';

/// Opens the SOS composer, then actually submits it via [SosController] —
/// the single place every "Report SOS" entry point in the app should call
/// through, so a real report always gets filed (and, on success, an
/// [SosOutcome] the caller can use to track the resulting ticket) rather
/// than only closing the sheet.
///
/// Returns null if the user dismissed the composer without confirming.
Future<SosOutcome?> submitSosViaComposer(BuildContext context, WidgetRef ref) async {
  final description = await AppBottomSheet.show<String>(
    context,
    builder: (_) => const SosComposerSheet(),
  );
  if (description == null || !context.mounted) return null;

  double lat, lng;
  try {
    final pos = await ref.read(locationServiceProvider).getCurrentPosition();
    lat = pos.latitude;
    lng = pos.longitude;
  } catch (_) {
    // No GPS fix — still file the report rather than block on location,
    // using a plausible fallback point so it isn't dropped at (0, 0).
    final fallback = KeralaDistricts.defaultDistrict;
    lat = fallback.lat;
    lng = fallback.lon;
  }

  final outcome = await ref.read(sosControllerProvider.notifier).submit(
        description: description,
        latitude: lat,
        longitude: lng,
      );
  if (!context.mounted) return outcome;

  final message = switch (outcome.kind) {
    SosOutcomeKind.submitted => 'SOS sent — nearby officials have been notified.',
    SosOutcomeKind.queuedOffline => 'Weak signal — SOS saved on device and will send automatically.',
    SosOutcomeKind.failed => "Couldn't send SOS — please try again.",
  };
  AppToast.show(
    context,
    message,
    kind: outcome.kind == SosOutcomeKind.submitted ? AppToastKind.success : AppToastKind.neutral,
  );
  return outcome;
}
