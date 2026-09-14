import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// Tiny, tasteful "Offline maps" pill — never a full-screen warning. Only
/// rendered by the caller when actually offline.
class OfflineIndicator extends StatelessWidget {
  const OfflineIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 13, color: AppColors.warning),
          const SizedBox(width: 6),
          Text('Offline maps', style: AppTypography.caption(color: AppColors.warning).copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
