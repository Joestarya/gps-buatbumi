class LocationModel {
  final double lat;
  final double lng;

  LocationModel({required this.lat, required this.lng});

  factory LocationModel.fromMap(Map<String, dynamic> m) => LocationModel(
        lat: (m['lat'] ?? 0).toDouble(),
        lng: (m['lng'] ?? 0).toDouble(),
      );

  Map<String, dynamic> toMap() => {'lat': lat, 'lng': lng};
}
