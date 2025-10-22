import 'package:latlong2/latlong.dart';

class ActiveRoute {
  ActiveRoute({
    required this.hotelId,
    required this.origin,
    required this.destination,
    required this.path,
  });

  final String hotelId;
  final LatLng origin;
  final LatLng destination;
  final List<LatLng> path;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'hotel_id': hotelId,
    'origin_lat': origin.latitude,
    'origin_lng': origin.longitude,
    'destination_lat': destination.latitude,
    'destination_lng': destination.longitude,
    'polyline': path
        .map((point) => <double>[point.latitude, point.longitude])
        .toList(),
  };

  factory ActiveRoute.fromJson(Map<String, dynamic> json) {
    final originLat = (json['origin_lat'] as num?)?.toDouble();
    final originLng = (json['origin_lng'] as num?)?.toDouble();
    final destinationLat = (json['destination_lat'] as num?)?.toDouble();
    final destinationLng = (json['destination_lng'] as num?)?.toDouble();

    if (originLat == null ||
        originLng == null ||
        destinationLat == null ||
        destinationLng == null) {
      throw const FormatException('Invalid route coordinates');
    }

    final polylineRaw = json['polyline'];
    final path = polylineRaw is List
        ? polylineRaw
              .map((point) {
                if (point is List && point.length == 2) {
                  final lat = (point[0] as num?)?.toDouble();
                  final lng = (point[1] as num?)?.toDouble();
                  if (lat != null && lng != null) {
                    return LatLng(lat, lng);
                  }
                }
                return null;
              })
              .whereType<LatLng>()
              .toList()
        : const <LatLng>[];

    return ActiveRoute(
      hotelId: json['hotel_id']?.toString() ?? '',
      origin: LatLng(originLat, originLng),
      destination: LatLng(destinationLat, destinationLng),
      path: path,
    );
  }
}
