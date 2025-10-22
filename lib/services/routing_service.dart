import 'dart:convert';
import 'dart:developer';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoutingService {
  RoutingService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl?.replaceAll(RegExp(r'/+$'), '') ?? _defaultRoutingUrl;

  static const _defaultRoutingUrl =
      'https://router.project-osrm.org/route/v1/driving';

  final http.Client _client;
  final String _baseUrl;

  Future<List<LatLng>> getRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson',
    );

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) {
        log('Routing API returned ${response.statusCode}: ${response.body}');
        throw Exception('Ruta no disponible');
      }

      final jsonBody = json.decode(response.body) as Map<String, dynamic>;
      final routes = jsonBody['routes'];
      if (routes is! List || routes.isEmpty) {
        throw Exception('No se encontraron rutas');
      }

      final geometry = routes.first['geometry'];
      final coordinates = geometry is Map<String, dynamic>
          ? geometry['coordinates']
          : null;

      if (coordinates is! List) {
        throw Exception('Datos de ruta invalidos');
      }

      final path = <LatLng>[];
      for (final point in coordinates) {
        if (point is List && point.length >= 2) {
          final lon = (point[0] as num?)?.toDouble();
          final lat = (point[1] as num?)?.toDouble();
          if (lat != null && lon != null) {
            path.add(LatLng(lat, lon));
          }
        }
      }

      if (path.isEmpty) {
        throw Exception('Ruta vacia');
      }

      return path;
    } catch (error, stackTrace) {
      log('Routing API error: $error', stackTrace: stackTrace);
      rethrow;
    }
  }
}
