import 'package:latlong2/latlong.dart';

import '../../../api/models/shelter_models.dart';

/// A place the user can navigate to. Today the only real destination
/// source is the shelters feed (there is no geocoding backend); this
/// model stays generic so a future search/geocode source can populate it
/// the same way.
class NavDestination {
  final String label;
  final String subtitle;
  final LatLng point;
  final String? shelterId;

  const NavDestination({
    required this.label,
    required this.subtitle,
    required this.point,
    this.shelterId,
  });

  factory NavDestination.fromShelter(ShelterFeature shelter) => NavDestination(
        label: shelter.name,
        subtitle: '${shelter.district} • ${shelter.availableSpace} spaces left',
        point: LatLng(shelter.latitude, shelter.longitude),
        shelterId: shelter.id,
      );
}
