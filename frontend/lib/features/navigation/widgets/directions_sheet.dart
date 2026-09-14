import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../controllers/navigation_state.dart';
import '../models/route_option.dart';
import '../providers/navigation_providers.dart';
import '../utils/format.dart';
import 'destination_search_sheet.dart';
import 'transport_mode_selector.dart';

/// The persistent Apple-Maps-style draggable sheet: collapsed shows the
/// ETA/distance/GO summary, dragged-up reveals mode selection, stops and
/// route alternatives. Unlike [AppBottomSheet] (a dismissible modal),
/// this stays anchored over the map for the life of the navigation
/// screen, so it's a standalone `DraggableScrollableSheet` rather than a
/// reuse of that component.
class DirectionsSheet extends ConsumerWidget {
  final VoidCallback onGo;

  const DirectionsSheet({super.key, required this.onGo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navigationControllerProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.24,
      minChildSize: 0.24,
      maxChildSize: 0.66,
      snap: true,
      snapSizes: const [0.24, 0.66],
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: AppRadius.sheetTopR,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised.withValues(alpha: 0.94),
                borderRadius: AppRadius.sheetTopR,
                border: const Border(
                  top: BorderSide(color: AppColors.cardBorder),
                  left: BorderSide(color: AppColors.cardBorder),
                  right: BorderSide(color: AppColors.cardBorder),
                ),
                boxShadow: AppColors.softShadow(opacity: 0.35, blur: 24),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(AppSpacing.comfortable, AppSpacing.sm, AppSpacing.comfortable, AppSpacing.section),
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4.5,
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      decoration: BoxDecoration(color: AppColors.cardBorder, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  if (nav.destination == null) const _SearchPrompt(),
                  if (nav.destination != null) ..._directionsContent(context, ref, nav),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _directionsContent(BuildContext context, WidgetRef ref, NavigationState nav) {
    final controller = ref.read(navigationControllerProvider.notifier);
    final selected = nav.selectedRoute;

    return [
      _SummaryRow(nav: nav, onGo: selected == null ? null : onGo, onClose: controller.clearDestination),
      const SizedBox(height: AppSpacing.section),
      Text('Directions', style: AppTypography.sectionTitle()),
      const SizedBox(height: AppSpacing.sm),
      TransportModeSelector(selected: nav.mode, onChanged: controller.setMode),
      const SizedBox(height: AppSpacing.md),
      _WaypointList(nav: nav),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          _DepartureChip(label: 'Leave Now', selected: true, enabled: true, onTap: () {}),
          const SizedBox(width: AppSpacing.compact),
          _DepartureChip(label: 'Depart At', selected: false, enabled: false, onTap: () {}),
        ],
      ),
      const SizedBox(height: AppSpacing.section),
      if (nav.isCalculating)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.4)),
        )
      else if (nav.error != null)
        _ErrorNote(message: nav.error!)
      else if (nav.selectedRoute != null)
        // Routing only ever surfaces the single shortest-distance route
        // (see RoutingService) — there's no alternative to pick between,
        // so this just confirms which one is loaded rather than offering a
        // chooser.
        _RouteRow(route: nav.selectedRoute!),
    ];
  }
}

class _SearchPrompt extends ConsumerWidget {
  const _SearchPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: AppRadius.buttonR,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final destination = await DestinationSearchSheet.show(context);
          if (destination != null) {
            ref.read(navigationControllerProvider.notifier).setDestination(destination);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: AppColors.textTertiary),
              const SizedBox(width: AppSpacing.sm),
              Text('Search shelters or district', style: AppTypography.body(color: AppColors.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final NavigationState nav;
  final VoidCallback? onGo;
  final VoidCallback onClose;

  const _SummaryRow({required this.nav, required this.onGo, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final route = nav.selectedRoute;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nav.destination!.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.cardTitle().copyWith(fontSize: 16),
              ),
              const SizedBox(height: 4),
              if (route != null)
                Text(
                  '${route.durationLabel} • ETA ${formatEta(route.eta)} • ${route.distanceLabel}'
                  '${route.isOfflineEstimate ? ' • offline estimate' : ''}',
                  style: AppTypography.label(color: route.isOfflineEstimate ? AppColors.warning : AppColors.textSecondary),
                )
              else if (nav.isCalculating)
                Text('Calculating route…', style: AppTypography.label())
              else if (nav.error != null)
                Text(nav.error!, style: AppTypography.label(color: AppColors.danger)),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (onGo != null) SizedBox(width: 88, child: AppButton(label: 'GO', onPressed: onGo, expand: false)),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary),
          onPressed: onClose,
          tooltip: 'Cancel directions',
        ),
      ],
    );
  }
}

class _WaypointList extends ConsumerWidget {
  final NavigationState nav;
  const _WaypointList({required this.nav});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(navigationControllerProvider.notifier);
    return Container(
      decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: AppRadius.cardR),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          _WaypointRow(icon: Icons.my_location_rounded, label: 'My Location', color: AppColors.accent),
          for (var i = 0; i < nav.stops.length; i++)
            _WaypointRow(
              icon: Icons.circle,
              iconSize: 10,
              label: nav.stops[i].label,
              color: AppColors.textSecondary,
              onRemove: () => controller.removeStop(i),
            ),
          _WaypointRow(icon: Icons.flag_rounded, label: nav.destination?.label ?? 'Destination', color: AppColors.dangerStrong),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final stop = await DestinationSearchSheet.show(context);
                if (stop != null) controller.addStop(stop);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.add_rounded, color: AppColors.accent, size: 18),
                    SizedBox(width: 10),
                    Text('Add Stop', style: TextStyle(fontFamily: 'Inter', color: AppColors.accent, fontWeight: FontWeight.w600, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaypointRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double iconSize;
  final VoidCallback? onRemove;

  const _WaypointRow({required this.icon, required this.label, required this.color, this.iconSize = 16, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: iconSize),
          const SizedBox(width: 14),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.body())),
          if (onRemove != null)
            InkWell(onTap: onRemove, child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}

class _DepartureChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _DepartureChip({required this.label, required this.selected, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withValues(alpha: 0.16) : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.accent : AppColors.cardBorderSubtle),
        ),
        child: Text(
          enabled ? label : '$label — needs live traffic data',
          style: AppTypography.caption(color: selected ? AppColors.accent : AppColors.textSecondary).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final RouteOption route;

  const _RouteRow({required this.route});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.1), borderRadius: AppRadius.smallR),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.route_outlined, color: AppColors.accent, size: 16),
          const SizedBox(width: 12),
          Text(route.durationLabel, style: AppTypography.cardTitle().copyWith(fontSize: 15)),
          const SizedBox(width: 8),
          Text('• ${route.distanceLabel}', style: AppTypography.label()),
          const Spacer(),
          Text('Shortest route', style: AppTypography.caption(color: AppColors.accent)),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  final String message;
  const _ErrorNote({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: AppRadius.smallR,
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
          const SizedBox(width: AppSpacing.compact),
          Expanded(child: Text(message, style: AppTypography.label(color: AppColors.danger))),
        ],
      ),
    );
  }
}
