import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/hotel.dart';
import 'services/hotel_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? initializationError;
  SupabaseClient? supabaseClient;

  try {
    await dotenv.load(fileName: '.env');
    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

    if (supabaseUrl == null ||
        supabaseUrl.isEmpty ||
        supabaseAnonKey == null ||
        supabaseAnonKey.isEmpty) {
      throw const FormatException(
        'Variables SUPABASE_URL o SUPABASE_ANON_KEY no encontradas',
      );
    }

    final supabase = await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );

    supabaseClient = supabase.client;
  } catch (error, stackTrace) {
    debugPrint('Error inicializando Supabase: $error');
    debugPrintStack(stackTrace: stackTrace);
    initializationError = 'No fue posible conectar con Supabase. '
        'Se mostraran datos de ejemplo.';
  }

  runApp(
    HotelApp(
      initializationError: initializationError,
      service: HotelService(client: supabaseClient),
    ),
  );
}

class HotelApp extends StatelessWidget {
  const HotelApp({
    super.key,
    required this.service,
    this.initializationError,
  });

  final HotelService service;
  final String? initializationError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Explorador de Hoteles',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: HotelMapPage(
        service: service,
        initializationError: initializationError,
      ),
    );
  }
}

class HotelMapPage extends StatefulWidget {
  const HotelMapPage({
    super.key,
    required this.service,
    this.initializationError,
  });

  final HotelService service;
  final String? initializationError;

  @override
  State<HotelMapPage> createState() => _HotelMapPageState();
}

class _HotelMapPageState extends State<HotelMapPage> {
  late Future<List<Hotel>> _hotelsFuture;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _hotelsFuture = widget.service.fetchHotels();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hoteles disponibles'),
      ),
      body: FutureBuilder<List<Hotel>>(
        future: _hotelsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final hotels = snapshot.data ?? <Hotel>[];
          final error = snapshot.error;

          return Column(
            children: [
              if (widget.initializationError != null || error != null)
                _ErrorBanner(
                  message: widget.initializationError ??
                      'Ocurrio un error al cargar los hoteles. '
                          'Mostrando datos de ejemplo.',
                ),
              Expanded(
                child: Stack(
                  children: [
                    _HotelMap(
                      controller: _mapController,
                      hotels: hotels,
                      onMarkerTap: _showHotelSheet,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _HotelCarousel(
                        hotels: hotels,
                        onHotelTap: (hotel) {
                          _animateToHotel(hotel);
                          _showHotelSheet(hotel);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _animateToHotel(Hotel hotel) {
    final zoom = _mapController.camera.zoom;
    _mapController.move(
      hotel.location,
      zoom.isFinite ? zoom : 13,
    );
  }

  void _showHotelSheet(Hotel hotel) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _HotelDetailSheet(hotel: hotel),
    );
  }
}

class _HotelMap extends StatelessWidget {
  const _HotelMap({
    required this.controller,
    required this.hotels,
    required this.onMarkerTap,
  });

  final MapController controller;
  final List<Hotel> hotels;
  final ValueChanged<Hotel> onMarkerTap;

  @override
  Widget build(BuildContext context) {
    final defaultCenter = const LatLng(19.4326, -99.1332);
    final center =
        hotels.isEmpty ? defaultCenter : hotels.first.location;

    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 13,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.maps',
        ),
        if (hotels.isNotEmpty)
          MarkerLayer(
            markers: hotels
                .map<Marker>(
                  (hotel) => Marker(
                    point: hotel.location,
                    width: 42,
                    height: 42,
                    child: GestureDetector(
                      onTap: () => onMarkerTap(hotel),
                      child: const _HotelMarkerIcon(),
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _HotelMarkerIcon extends StatelessWidget {
  const _HotelMarkerIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blueAccent,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: const Icon(
        Icons.hotel,
        color: Colors.white,
        size: 20,
      ),
    );
  }
}

class _HotelCarousel extends StatelessWidget {
  const _HotelCarousel({
    required this.hotels,
    required this.onHotelTap,
  });

  final List<Hotel> hotels;
  final ValueChanged<Hotel> onHotelTap;

  @override
  Widget build(BuildContext context) {
    if (hotels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 160,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Color.fromARGB(180, 0, 0, 0),
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: hotels.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final hotel = hotels[index];
          return _HotelCard(
            hotel: hotel,
            onTap: () => onHotelTap(hotel),
          );
        },
      ),
    );
  }
}

class _HotelCard extends StatelessWidget {
  const _HotelCard({required this.hotel, required this.onTap});

  final Hotel hotel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 260,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  hotel.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  hotel.address,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[700]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _RatingChip(rating: hotel.averageRating),
                    Text(
                      hotel.priceRange,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({this.rating});

  final double? rating;

  @override
  Widget build(BuildContext context) {
    if (rating == null) {
      return const Text(
        'Sin resenas',
        style: TextStyle(color: Colors.grey),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber[600],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.star, color: Colors.white, size: 16),
          const SizedBox(width: 4),
          Text(
            rating!.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _HotelDetailSheet extends StatelessWidget {
  const _HotelDetailSheet({required this.hotel});

  final Hotel hotel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hotel.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            hotel.address,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[700]),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _RatingChip(rating: hotel.averageRating),
              const SizedBox(width: 12),
              Chip(
                label: Text(hotel.category),
                avatar: const Icon(Icons.category, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Rango de precios: ${hotel.priceRange}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (hotel.description != null && hotel.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                hotel.description!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          if (hotel.amenities.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: hotel.amenities
                    .map(
                      (amenity) => Chip(
                        label: Text(amenity),
                        avatar: const Icon(Icons.check, size: 16),
                      ),
                    )
                    .toList(),
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.map),
              label: const Text('Cerrar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber[100],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.amber[900]),
            ),
          ),
        ],
      ),
    );
  }
}
