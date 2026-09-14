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

  /// A snapshot of an en-route volunteer's last polled position — like
  /// [fromShelter], this is a one-time route target, not a live-updating
  /// one, so directions reflect where the volunteer *was* when the citizen
  /// tapped "Get Directions," not a continuously re-routed live escort.
  factory NavDestination.toVolunteer(String volunteerName, LatLng point) => NavDestination(
        label: volunteerName,
        subtitle: 'Volunteer — en route to you',
        point: point,
      );
}
