import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../providers/api_provider.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/map_pin_marker.dart';
import '../models/nav_destination.dart';
import '../providers/navigation_providers.dart';

/// Destination search backed by the shelters feed — the only real
/// "places" this app knows about (there's no geocoding backend). Falls
/// back to the last synced list when the fetch fails, so previously seen
/// shelters stay pickable offline per the offline-navigation spec.
class DestinationSearchSheet extends ConsumerStatefulWidget {
  const DestinationSearchSheet({super.key});

  static Future<NavDestination?> show(BuildContext context) {
    return AppBottomSheet.show<NavDestination>(context, builder: (_) => const DestinationSearchSheet());
  }

  @override
  ConsumerState<DestinationSearchSheet> createState() => _DestinationSearchSheetState();
}

class _DestinationSearchSheetState extends ConsumerState<DestinationSearchSheet> {
  final _controller = TextEditingController();
  String _query = '';
  bool _loading = true;
  List<NavDestination> _all = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(preciopsApiProvider);
    try {
      final result = await api.getSheltersGeoJson();
      ref.read(sheltersCacheProvider.notifier).state = result.features;
      if (mounted) setState(() => _all = result.features.map(NavDestination.fromShelter).toList());
    } catch (_) {
      final cached = ref.read(sheltersCacheProvider);
      if (mounted) setState(() => _all = cached.map(NavDestination.fromShelter).toList());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<NavDestination> get _filtered {
    if (_query.trim().isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all.where((d) => d.label.toLowerCase().contains(q) || d.subtitle.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Directions', style: AppTypography.sectionTitle()),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            style: AppTypography.body(),
            decoration: const InputDecoration(
              hintText: 'Search shelters or district',
              prefixIcon: Icon(Icons.search_rounded, color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.4)),
                  )
                : _filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: Text('No matching shelters', style: AppTypography.label())),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _filtered.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final d = _filtered[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const MapPinMarker(icon: Icons.home_work_rounded, color: AppColors.accent, size: 34),
                            title: Text(d.label, style: AppTypography.cardTitle().copyWith(fontSize: 15)),
                            subtitle: Text(d.subtitle, style: AppTypography.caption()),
                            onTap: () => Navigator.pop(context, d),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
