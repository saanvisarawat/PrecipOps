import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_typography.dart';
import '../models/travel_mode.dart';

/// Segmented Car/Walking/Cycling/Transit control. Transit stays visible
/// but disabled — there's no transit router behind it — matching the
/// app's existing "coming soon" tile treatment (see HubScreen) rather
/// than hiding the option or faking a result for it.
class TransportModeSelector extends StatelessWidget {
  final TravelMode selected;
  final ValueChanged<TravelMode> onChanged;

  const TransportModeSelector({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: AppRadius.buttonR,
        border: Border.all(color: AppColors.cardBorderSubtle),
      ),
      child: Row(
        children: [
          for (final mode in TravelMode.values) Expanded(child: _ModeTile(mode: mode, selected: mode == selected, onChanged: onChanged)),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final TravelMode mode;
  final bool selected;
  final ValueChanged<TravelMode> onChanged;

  const _ModeTile({required this.mode, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final enabled = mode.isAvailable;
    final color = !enabled
        ? AppColors.textDisabled
        : selected
            ? Colors.black
            : AppColors.textSecondary;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () => onChanged(mode) : null,
          borderRadius: AppRadius.smallR,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected && enabled ? AppColors.accent : Colors.transparent,
              borderRadius: AppRadius.smallR,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(mode.icon, size: 19, color: color),
                const SizedBox(height: 3),
                Text(
                  enabled ? mode.label : 'Soon',
                  style: AppTypography.caption(color: color).copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
