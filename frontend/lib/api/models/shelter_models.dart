class ShelterFeature {
  final String id;
  final String name;
  final String district;
  final double latitude;
  final double longitude;
  final int capacity;
  final int currentOccupancy;
  final String address;

  const ShelterFeature({
    required this.id,
    required this.name,
    required this.district,
    required this.latitude,
    required this.longitude,
    required this.capacity,
    required this.currentOccupancy,
    this.address = '',
  });

  int get availableSpace => capacity - currentOccupancy;
  double get occupancyRatio => capacity == 0 ? 0 : currentOccupancy / capacity;

  factory ShelterFeature.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>;
    final coords = geometry['coordinates'] as List;
    final props = json['properties'] as Map<String, dynamic>;
    return ShelterFeature(
      id: json['id'] as String,
      name: props['name'] as String,
      district: props['district'] as String,
      longitude: (coords[0] as num).toDouble(),
      latitude: (coords[1] as num).toDouble(),
      capacity: props['capacity'] as int,
      currentOccupancy: props['current_occupancy'] as int,
      address: props['address'] as String? ?? '',
    );
  }

  /// GeoJSON Feature representation — mirrors GET /api/shelters/geojson.
  Map<String, dynamic> toJson() => {
        'type': 'Feature',
        'id': id,
        'geometry': {
          'type': 'Point',
          'coordinates': [longitude, latitude],
        },
        'properties': {
          'name': name,
          'district': district,
          'capacity': capacity,
          'current_occupancy': currentOccupancy,
          'address': address,
        },
      };
}

class ShelterFeatureCollection {
  final List<ShelterFeature> features;
  const ShelterFeatureCollection(this.features);

  Map<String, dynamic> toJson() => {
        'type': 'FeatureCollection',
        'features': features.map((f) => f.toJson()).toList(),
      };
}
