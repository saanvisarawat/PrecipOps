import 'package:geolocator/geolocator.dart';

class LocationPermissionDenied implements Exception {
  const LocationPermissionDenied();
}

/// Fine-grained reason a location fix isn't available, for screens (like
/// navigation) that need to show a specific inline state rather than a
/// single generic error — see [LocationService.checkAvailability].
enum LocationAvailability { available, servicesDisabled, permissionDenied, permissionDeniedForever }

class LocationService {
  Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationPermissionDenied();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // On web, an ignored/stuck browser permission prompt never resolves
      // or rejects on its own — without this timeout every caller (the
      // volunteer duty toggle included) would hang indefinitely waiting
      // on it instead of falling back gracefully.
      permission = await Geolocator.requestPermission().timeout(
        const Duration(seconds: 15),
        onTimeout: () => LocationPermission.denied,
      );
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDenied();
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 10));
  }

  /// Checks permission/service state without throwing, so a screen can
  /// render a tailored inline state ("Turn on Location Services" vs
  /// "Location permission required") instead of one generic error.
  Future<LocationAvailability> checkAvailability() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAvailability.servicesDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationAvailability.permissionDeniedForever;
    }
    if (permission == LocationPermission.denied) {
      return LocationAvailability.permissionDenied;
    }
    return LocationAvailability.available;
  }

  /// Continuous position updates for the navigation map/active-navigation
  /// screens. A 5 m distance filter avoids the update-per-inch spam a raw
  /// GPS stream produces while still feeling live at walking/driving
  /// speed.
  Stream<Position> watchPosition({int distanceFilterMeters = 5}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: distanceFilterMeters),
    );
  }
}
