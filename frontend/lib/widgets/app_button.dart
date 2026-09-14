import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_motion.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_typography.dart';

enum AppButtonVariant { primary, secondary, tertiary }

/// The ONLY button used for actions in this app. Three variants:
///   primary   — emerald gradient fill, the one CTA per screen.
///   secondary — dark elevated surface with a hairline border.
///   tertiary  — text + optional icon, no fill.
/// Built directly on Material/InkWell — screens must never reach for a
/// raw `ElevatedButton`/`OutlinedButton`/`TextButton` for an action.
class AppButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final AppButtonVariant variant;
  final Color? color;
  final bool expand;

  const AppButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.variant = AppButtonVariant.primary,
    this.color,
    this.expand = true,
  });

  const AppButton.secondary({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.color,
    this.expand = true,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.tertiary({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.color,
    this.expand = false,
  }) : variant = AppButtonVariant.tertiary;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null || widget.isLoading;

    switch (widget.variant) {
      case AppButtonVariant.primary:
        return _buildPrimary(disabled);
      case AppButtonVariant.secondary:
        return _buildSecondary(disabled);
      case AppButtonVariant.tertiary:
        return _buildTertiary(disabled);
    }
  }

  Widget _content({required Color foreground, required double size}) {
    return Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isLoading)
          SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: foreground),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: 18, color: foreground),
        if (widget.isLoading || widget.icon != null) const SizedBox(width: 9),
        Flexible(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.button(color: foreground).copyWith(fontSize: size),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimary(bool disabled) {
    final fill = widget.color ?? AppColors.accent;
    final pressedFill = widget.color?.withValues(alpha: 0.85) ?? AppColors.accentPressed;
    final onFill = fill.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    return Opacity(
      opacity: disabled && !widget.isLoading ? 0.45 : 1,
      child: AnimatedScale(
        scale: _pressed ? AppMotion.pressScale : 1,
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          decoration: BoxDecoration(
            borderRadius: AppRadius.buttonR,
            // Flat premium fill — no gradient, no glow shadow.
            color: _pressed ? pressedFill : fill,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadius.buttonR,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: disabled ? null : widget.onPressed,
              onHighlightChanged: (v) => setState(() => _pressed = v),
              splashColor: Colors.black.withValues(alpha: 0.08),
              highlightColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(minHeight: 54, minWidth: 64),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                child: _content(foreground: onFill, size: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondary(bool disabled) {
    final foreground = widget.color ?? AppColors.textPrimary;
    return Opacity(
      opacity: disabled && !widget.isLoading ? 0.45 : 1,
      child: AnimatedScale(
        scale: _pressed ? AppMotion.pressScale : 1,
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        child: Material(
          color: _pressed ? AppColors.surfaceHigh : AppColors.surfaceRaised,
          borderRadius: AppRadius.buttonR,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: disabled ? null : widget.onPressed,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            splashColor: AppColors.accentGlow,
            highlightColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(minHeight: 54, minWidth: 64),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: AppRadius.buttonR,
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: _content(foreground: foreground, size: 15),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTertiary(bool disabled) {
    final foreground = widget.color ?? AppColors.accent;
    return Opacity(
      opacity: disabled && !widget.isLoading ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.smallR,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: disabled ? null : widget.onPressed,
          splashColor: AppColors.accentGlow,
          highlightColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: _content(foreground: foreground, size: 14),
          ),
        ),
      ),
    );
  }
}
