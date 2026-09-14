import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../providers/lite_sos_provider.dart';
import '../../../providers/service_providers.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_toast.dart';
import 'voice_sos_recorder.dart';

/// Content of the SOS composer sheet — presented via `AppBottomSheet`,
/// which supplies the drag indicator, rounded top corners and surface.
class SosComposerSheet extends ConsumerStatefulWidget {
  const SosComposerSheet({super.key});

  @override
  ConsumerState<SosComposerSheet> createState() => _SosComposerSheetState();
}

class _SosComposerSheetState extends ConsumerState<SosComposerSheet> {
  final _controller = TextEditingController();
  bool _sendingLite = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _description {
    final text = _controller.text.trim();
    return text.isEmpty ? 'Emergency assistance needed' : text;
  }

  /// Sends straight through the lite endpoint itself (bypassing the richer
  /// createReport/offline-queue pipeline the primary button uses) — a
  /// single-packet fallback for edge/2G connectivity. Goes through
  /// [LiteSosController], which persists the request locally first and
  /// keeps retrying in the background until it actually gets a
  /// successful response, so a bad connection right now doesn't lose it.
  /// Closes the sheet either way since there's nothing further to
  /// compose — the retry loop runs independently of this screen.
  Future<void> _sendLowData() async {
    setState(() => _sendingLite = true);
    Position position;
    try {
      position = await ref.read(locationServiceProvider).getCurrentPosition();
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Could not get GPS location for Low Data SOS.', kind: AppToastKind.error);
        setState(() => _sendingLite = false);
      }
      return;
    }
    final outcome = await ref.read(liteSosControllerProvider.notifier).submit(
          lat: position.latitude,
          lng: position.longitude,
          description: _description,
        );
    if (!mounted) return;
    Navigator.pop(context);
    AppToast.show(
      context,
      outcome == LiteSosOutcome.sent
          ? 'Low Data SOS sent.'
          : 'Weak signal — SOS saved on device and will keep retrying automatically until it goes through.',
      kind: AppToastKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.emergency_share_rounded, color: AppColors.danger, size: 20),
            const SizedBox(width: 8),
            Text('Send Emergency SOS', style: AppTypography.sectionTitle()),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'We\'ll attach your live GPS location automatically.',
          style: AppTypography.body(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _controller,
          maxLines: 3,
          autofocus: true,
          style: AppTypography.body(),
          decoration: const InputDecoration(
            hintText: 'e.g. Water entering ground floor, family of 4 stranded',
            labelText: 'What\'s happening?',
          ),
        ),
        const SizedBox(height: 22),
        AppButton(
          label: 'Confirm & Send SOS',
          color: AppColors.danger,
          onPressed: _sendingLite ? null : () => Navigator.pop(context, _description),
        ),
        const SizedBox(height: 10),
        AppButton.secondary(
          label: 'Low Data SOS (weak signal)',
          icon: Icons.signal_cellular_alt_rounded,
          isLoading: _sendingLite,
          onPressed: _sendingLite ? null : _sendLowData,
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(child: Divider(color: AppColors.cardBorder)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('OR', style: AppTypography.caption().copyWith(fontWeight: FontWeight.w700)),
            ),
            Expanded(child: Divider(color: AppColors.cardBorder)),
          ],
        ),
        const SizedBox(height: 14),
        const VoiceSosRecorder(),
      ],
    );
  }
}
