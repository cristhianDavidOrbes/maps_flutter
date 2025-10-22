import 'package:latlong2/latlong.dart';

/// Domain model representing a hotel with its geolocation and metadata.
class Hotel {
  Hotel({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    required this.priceRange,
    required this.category,
    this.description,
    this.amenities = const <String>[],
    this.imageUrls = const <String>[],
    this.averageRating,
  });

  final String id;
  final String name;
  final String address;
  final LatLng location;
  final String priceRange;
  final String category;
  final String? description;
  final List<String> amenities;
  final List<String> imageUrls;
  final double? averageRating;

  factory Hotel.fromJson(Map<String, dynamic> json) {
    final latitude = (json['latitude'] as num?)?.toDouble();
    final longitude = (json['longitude'] as num?)?.toDouble();

    if (latitude == null || longitude == null) {
      throw const FormatException('Hotel requires latitude and longitude');
    }

    final amenitiesRaw = json['amenities'];
    final imageUrlsRaw = json['image_urls'];

    return Hotel(
      id: json['id']?.toString() ?? '',
      name: (json['name'] as String?)?.trim() ?? 'Hotel sin nombre',
      address:
          (json['address'] as String?)?.trim() ?? 'Direccion no disponible',
      location: LatLng(latitude, longitude),
      priceRange: (json['price_range'] as String?)?.trim() ?? 'No especificado',
      category: (json['category'] as String?)?.trim() ?? 'Sin categoria',
      description: (json['description'] as String?)?.trim(),
      amenities: amenitiesRaw is List
          ? amenitiesRaw.map((element) => element.toString()).toList()
          : const <String>[],
      imageUrls: imageUrlsRaw is List
          ? imageUrlsRaw.map((element) => element.toString()).toList()
          : const <String>[],
      averageRating: (json['average_rating'] as num?)?.toDouble(),
    );
  }
}
