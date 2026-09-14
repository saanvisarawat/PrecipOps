import 'dart:ui';

import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_motion.dart';

class GlassBottomNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const GlassBottomNavItem({required this.icon, required this.selectedIcon, required this.label});
}

/// The ONLY bottom navigation used in this app — a floating glass bar,
/// inset from the screen edges, with a blurred translucent surface and a
/// hairline border. Never a flat edge-to-edge `BottomNavigationBar`, and
/// never a solid green bar — selection reads through a small accent dot
/// under the label, not a loud background fill or an icon glow.
class GlassBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<GlassBottomNavItem> items;

  const GlassBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              color: AppColors.glassSurface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppColors.glassBorder, width: 1),
              boxShadow: AppColors.softShadow(opacity: 0.28, blur: 20),
            ),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavItem(
                      item: items[i],
                      selected: i == selectedIndex,
                      onTap: () => onDestinationSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final GlassBottomNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.textTertiary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: AppColors.accentGlow,
        highlightColor: Colors.transparent,
        child: SizedBox(
          height: 66,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.06 : 1.0,
                duration: AppMotion.fast,
                curve: AppMotion.curve,
                child: Icon(selected ? item.selectedIcon : item.icon, color: color, size: 22),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: AppMotion.fast,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10.5,
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
                child: Text(item.label),
              ),
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: AppMotion.fast,
                width: selected ? 14 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
