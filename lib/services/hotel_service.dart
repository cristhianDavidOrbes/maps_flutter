import 'dart:developer';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/hotel.dart';

/// Data access layer that retrieves hotels from Supabase.
class HotelService {
  HotelService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  static const _defaultTable = 'hotels';

  Future<List<Hotel>> fetchHotels({String table = _defaultTable}) async {
    final client = _client;
    if (client == null) {
      log('Supabase no inicializado, retornando datos de ejemplo');
      return _fallbackHotels();
    }

    try {
      final data = await client
          .from(table)
          .select(
            'id, name, address, latitude, longitude, price_range, category, description, amenities, image_urls, average_rating',
          );

      return (data as List<dynamic>)
          .map((row) => Hotel.fromJson(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (error, stackTrace) {
      log(
        'Supabase error loading hotels: ${error.message}',
        stackTrace: stackTrace,
      );
      return _fallbackHotels();
    } catch (error, stackTrace) {
      log('Unexpected error loading hotels: $error', stackTrace: stackTrace);
      return _fallbackHotels();
    }
  }

  Future<List<Hotel>> fetchHotelsNearby({
    required LatLng center,
    double radiusKm = 10,
    String table = _defaultTable,
  }) async {
    final client = _client;
    if (client == null) {
      return _fallbackHotels();
    }

    try {
      final deltaLat = radiusKm / 111.0;
      final latRadians = center.latitude * math.pi / 180.0;
      final cosLat = math.cos(latRadians).abs();
      final safeCosLat = cosLat < 0.0001 ? 0.0001 : cosLat;
      final deltaLng = radiusKm / (111.0 * safeCosLat);

      final minLat = center.latitude - deltaLat;
      final maxLat = center.latitude + deltaLat;
      final minLng = center.longitude - deltaLng;
      final maxLng = center.longitude + deltaLng;

      final data = await client
          .from(table)
          .select()
          .gte('latitude', minLat)
          .lte('latitude', maxLat)
          .gte('longitude', minLng)
          .lte('longitude', maxLng);

      if (data is! List) {
        return _fallbackHotels();
      }

      final hotels = data
          .map((row) => Hotel.fromJson(row as Map<String, dynamic>))
          .toList();

      if (hotels.isEmpty) {
        return _fallbackHotels();
      }

      return hotels;
    } catch (error, stackTrace) {
      log('Error fetching nearby hotels: $error', stackTrace: stackTrace);
      return _fallbackHotels();
    }
  }

  List<Hotel> _fallbackHotels() => <Hotel>[
    Hotel(
      id: 'demo-1',
      name: 'Hotel Mirador Centro',
      address: 'Av. Reforma 123, Ciudad de Mexico',
      location: const LatLng(19.4353, -99.1417),
      priceRange: '\$90 - \$150',
      category: '4 estrellas',
      description:
          'Hotel centrico con desayuno incluido, ideal para viajes de trabajo.',
      amenities: const ['Wi-Fi', 'Desayuno', 'Sala de juntas'],
      imageUrls: const [],
      averageRating: 4.3,
    ),
    Hotel(
      id: 'demo-2',
      name: 'Hotel Playa Dorada',
      address: 'Zona Hotelera, Cancun, Q.R.',
      location: const LatLng(21.1619, -86.8515),
      priceRange: '\$150 - \$260',
      category: 'Resort 5 estrellas',
      description:
          'Resort frente al mar con albercas infinitas y club de playa.',
      amenities: const ['Wi-Fi', 'Spa', 'Buffet', 'Piscina'],
      imageUrls: const [],
      averageRating: 4.8,
    ),
    Hotel(
      id: 'demo-3',
      name: 'Posada Colonial',
      address: 'Centro historico, Oaxaca',
      location: const LatLng(17.0609, -96.7253),
      priceRange: '\$45 - \$80',
      category: 'Boutique 3 estrellas',
      description:
          'Posada acogedora con decoracion tradicional y terraza panoramica.',
      amenities: const ['Wi-Fi', 'Terraza', 'Desayuno continental'],
      imageUrls: const [],
      averageRating: 4.5,
    ),
  ];
}
