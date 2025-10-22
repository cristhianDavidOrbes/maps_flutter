import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/active_route.dart';
import 'models/hotel.dart';
import 'services/hotel_service.dart';
import 'services/gemini_service.dart';
import 'services/route_service.dart';
import 'services/routing_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? initializationError;
  SupabaseClient? supabaseClient;
  String? routingBaseUrl;
  GeminiService? geminiService;
  String? geminiWarning;

  try {
    await dotenv.load(fileName: '.env');
    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
    final geminiApiKey = dotenv.env['GEMINI_API_KEY'];
    routingBaseUrl = dotenv.env['ROUTING_API_URL'];

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

    if (geminiApiKey != null && geminiApiKey.isNotEmpty) {
      geminiService = GeminiService(apiKey: geminiApiKey);
    } else {
      geminiWarning =
          'Configura GEMINI_API_KEY en .env para habilitar el analisis con Gemini.';
    }
  } catch (error, stackTrace) {
    debugPrint('Error inicializando Supabase: $error');
    debugPrintStack(stackTrace: stackTrace);
    initializationError =
        'No fue posible conectar con Supabase. '
        'Se mostraran datos de ejemplo.';
    final geminiApiKey = dotenv.env['GEMINI_API_KEY'];
    if (geminiApiKey != null && geminiApiKey.isNotEmpty) {
      geminiService = GeminiService(apiKey: geminiApiKey);
    } else {
      geminiWarning =
          'Configura GEMINI_API_KEY en .env para habilitar el analisis con Gemini.';
    }
  }

  final hotelService = HotelService(client: supabaseClient);
  final routeService = RouteService(client: supabaseClient);
  final routingService = RoutingService(baseUrl: routingBaseUrl);

  runApp(
    HotelApp(
      initializationError: initializationError,
      hotelService: hotelService,
      routeService: routeService,
      routingService: routingService,
      geminiService: geminiService,
      geminiWarning: geminiWarning,
    ),
  );
}

class HotelApp extends StatelessWidget {
  const HotelApp({
    super.key,
    required this.hotelService,
    required this.routeService,
    required this.routingService,
    this.initializationError,
    this.geminiService,
    this.geminiWarning,
  });

  final HotelService hotelService;
  final RouteService routeService;
  final RoutingService routingService;
  final String? initializationError;
  final GeminiService? geminiService;
  final String? geminiWarning;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Explorador de Hoteles',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: HotelMapPage(
        hotelService: hotelService,
        routeService: routeService,
        routingService: routingService,
        initializationError: initializationError,
        geminiService: geminiService,
        geminiWarning: geminiWarning,
      ),
    );
  }
}

class HotelMapPage extends StatefulWidget {
  const HotelMapPage({
    super.key,
    required this.hotelService,
    required this.routeService,
    required this.routingService,
    this.initializationError,
    this.geminiService,
    this.geminiWarning,
  });

  final HotelService hotelService;
  final RouteService routeService;
  final RoutingService routingService;
  final String? initializationError;
  final GeminiService? geminiService;
  final String? geminiWarning;

  @override
  State<HotelMapPage> createState() => _HotelMapPageState();
}

class _HotelMapPageState extends State<HotelMapPage> {
  final MapController _mapController = MapController();
  LatLng? _userLocation;
  List<Hotel> _hotels = <Hotel>[];
  ActiveRoute? _activeRoute;
  Hotel? _activeHotel;
  bool _initializing = true;
  bool _loadingRoute = false;
  bool _analysisInProgress = false;
  String? _statusMessage;
  String? _userId;
  final ImagePicker _imagePicker = ImagePicker();

  static const LatLng _fallbackCenter = LatLng(19.4326, -99.1332);

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (widget.initializationError != null) {
      setState(() {
        _statusMessage = widget.initializationError;
      });
    }

    final userId = await widget.routeService.ensureUser();
    if (mounted) {
      setState(() {
        _userId = userId;
      });
    }

    final position = await _determinePosition();
    if (position != null && mounted) {
      setState(() {
        _userLocation = position;
      });
    }

    await _loadHotels();
    await _restoreActiveRoute();

    if (mounted) {
      setState(() {
        _initializing = false;
      });
    }
  }

  Future<LatLng?> _determinePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _statusMessage =
              'Activa la ubicacion del dispositivo para encontrar hoteles cercanos.';
        });
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _statusMessage =
                'Se necesita el permiso de ubicacion para mostrar hoteles cercanos.';
          });
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _statusMessage =
              'Habilita la ubicacion desde ajustes para poder usar el mapa.';
        });
        return null;
      }

      final position = await Geolocator.getCurrentPosition();
      return LatLng(position.latitude, position.longitude);
    } catch (error) {
      setState(() {
        _statusMessage = 'No fue posible obtener tu ubicacion ($error).';
      });
      return null;
    }
  }

  Future<void> _loadHotels() async {
    final center =
        _userLocation ?? _activeRoute?.destination ?? _fallbackCenter;

    final hotels = await widget.hotelService.fetchHotelsNearby(
      center: center,
      radiusKm: 15,
    );

    if (!mounted) return;

    setState(() {
      _hotels = hotels;
    });
  }

  Future<void> _restoreActiveRoute() async {
    final userId = _userId;
    if (userId == null) {
      return;
    }

    final storedRoute = await widget.routeService.fetchActiveRoute(userId);
    if (!mounted || storedRoute == null) {
      return;
    }

    final hotel = _hotels.firstWhere(
      (item) => item.id == storedRoute.hotelId,
      orElse: () {
        return Hotel(
          id: storedRoute.hotelId,
          name: 'Destino guardado',
          address: 'Ruta previa',
          location: storedRoute.destination,
          priceRange: 'No disponible',
          category: 'Recordado',
        );
      },
    );

    setState(() {
      _activeRoute = storedRoute;
      _activeHotel = hotel;
      _userLocation ??= storedRoute.origin;
    });

    _fitMapToRoute(storedRoute.path);
  }

  void _fitMapToRoute(List<LatLng> path) {
    if (path.isEmpty) {
      return;
    }

    final points = List<LatLng>.from(path);
    if (_userLocation != null) {
      points.add(_userLocation!);
    }

    if (points.length < 2) {
      _mapController.move(points.first, 15);
      return;
    }

    final bounds = LatLngBounds.fromPoints(points);

    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32)),
    );
  }

  Future<void> _startRoute(Hotel hotel) async {
    final origin = _userLocation;
    if (origin == null) {
      setState(() {
        _statusMessage =
            'Activa tu ubicacion para poder trazar una ruta hacia el hotel.';
      });
      return;
    }

    setState(() {
      _loadingRoute = true;
      _activeHotel = hotel;
    });

    try {
      final path = await widget.routingService.getRoute(
        origin: origin,
        destination: hotel.location,
      );

      final route = ActiveRoute(
        hotelId: hotel.id,
        origin: origin,
        destination: hotel.location,
        path: path,
      );

      setState(() {
        _activeRoute = route;
        _loadingRoute = false;
      });

      _fitMapToRoute(path);

      final userId = _userId;
      if (userId != null) {
        await widget.routeService.saveRoute(userId, route);
      }
    } catch (error) {
      setState(() {
        _loadingRoute = false;
        _statusMessage = 'No se pudo obtener la ruta: $error';
      });
    }
  }

  Future<void> _cancelRoute() async {
    final userId = _userId;
    setState(() {
      _activeRoute = null;
    });

    if (userId != null) {
      await widget.routeService.clearRoute(userId);
    }

    final center = _userLocation ?? _fallbackCenter;
    _mapController.move(center, 13);
  }

  Future<void> _openAnalysisOptions() async {
    final service = widget.geminiService;
    if (service == null) {
      setState(() {
        _statusMessage =
            widget.geminiWarning ??
            'Configura GEMINI_API_KEY en .env para habilitar Gemini.';
      });
      return;
    }

    if (_activeHotel == null) {
      setState(() {
        _statusMessage =
            'Selecciona primero un hotel y traza la ruta antes de analizarlo.';
      });
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => const _ImageSourceSheet(),
    );

    if (source == null || !mounted) {
      return;
    }

    await _captureAndAnalyze(source, service);
  }

  Future<void> _captureAndAnalyze(
    ImageSource source,
    GeminiService service,
  ) async {
    var dialogShown = false;
    try {
      final file = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
      );

      if (file == null || !mounted) {
        return;
      }

      setState(() {
        _analysisInProgress = true;
      });

      if (mounted) {
        dialogShown = true;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _LoadingDialog(),
        );
      }

      final bytes = await file.readAsBytes();
      final result = await service.analyzeHotel(
        imageBytes: bytes,
        hotelName: _activeHotel?.name,
      );

      if (!mounted) {
        return;
      }

      if (dialogShown) {
        final navigator = Navigator.of(context, rootNavigator: true);
        if (navigator.canPop()) {
          navigator.pop();
        }
        dialogShown = false;
      }

      setState(() {
        _analysisInProgress = false;
      });

      _showGeminiResult(result);
    } catch (error) {
      if (!mounted) {
        return;
      }

      if (dialogShown) {
        final navigator = Navigator.of(context, rootNavigator: true);
        if (navigator.canPop()) {
          navigator.pop();
        }
      }
      setState(() {
        _analysisInProgress = false;
        _statusMessage = 'Gemini no pudo analizar la foto: $error';
      });
    }
  }

  void _showGeminiResult(String result) {
    if (!mounted) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) =>
          _GeminiResultSheet(hotel: _activeHotel, result: result),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final messages = <String>[
      if (widget.initializationError != null) widget.initializationError!,
      if (widget.geminiWarning != null) widget.geminiWarning!,
      if (_statusMessage != null) _statusMessage!,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hoteles disponibles'),
        actions: [
          if (widget.geminiService != null)
            IconButton(
              tooltip: 'Analizar hotel con Gemini',
              onPressed: _analysisInProgress ? null : _openAnalysisOptions,
              icon: const Icon(Icons.camera_alt_outlined),
            ),
          if (_activeRoute != null)
            TextButton.icon(
              onPressed: _cancelRoute,
              icon: const Icon(Icons.close),
              label: const Text('Cancelar ruta'),
            ),
        ],
      ),
      floatingActionButton: _userLocation == null
          ? null
          : FloatingActionButton(
              onPressed: () => _mapController.move(_userLocation!, 14),
              child: const Icon(Icons.my_location),
            ),
      body: Stack(
        children: [
          Column(
            children: [
              for (final message in messages) _ErrorBanner(message: message),
              Expanded(
                child: Stack(
                  children: [
                    _HotelMap(
                      controller: _mapController,
                      hotels: _hotels,
                      userLocation: _userLocation,
                      activeRoute: _activeRoute,
                      onMarkerTap: _handleHotelTap,
                      activeHotelId: _activeHotel?.id,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _HotelCarousel(
                        hotels: _hotels,
                        activeHotelId: _activeHotel?.id,
                        loadingRoute: _loadingRoute,
                        onHotelTap: _startRoute,
                        onCancelRoute: _cancelRoute,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleHotelTap(Hotel hotel) {
    _startRoute(hotel);
  }
}

class _HotelMap extends StatelessWidget {
  const _HotelMap({
    required this.controller,
    required this.hotels,
    required this.onMarkerTap,
    this.userLocation,
    this.activeRoute,
    this.activeHotelId,
  });

  final MapController controller;
  final List<Hotel> hotels;
  final ValueChanged<Hotel> onMarkerTap;
  final LatLng? userLocation;
  final ActiveRoute? activeRoute;
  final String? activeHotelId;

  @override
  Widget build(BuildContext context) {
    final center =
        userLocation ??
        activeRoute?.destination ??
        (hotels.isNotEmpty
            ? hotels.first.location
            : _HotelMapPageState._fallbackCenter);

    final hotelMarkers = hotels
        .map(
          (hotel) => Marker(
            point: hotel.location,
            width: 44,
            height: 44,
            child: GestureDetector(
              onTap: () => onMarkerTap(hotel),
              child: _HotelMarkerIcon(isActive: hotel.id == activeHotelId),
            ),
          ),
        )
        .toList();

    final markers = <Marker>[
      if (userLocation != null)
        Marker(
          point: userLocation!,
          width: 42,
          height: 42,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.green[600],
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
              Icons.person_pin_circle,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ...hotelMarkers,
    ];

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
        if (activeRoute != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: activeRoute!.path,
                strokeWidth: 6,
                color: Colors.blueAccent.withOpacity(0.75),
              ),
            ],
          ),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }
}

class _HotelMarkerIcon extends StatelessWidget {
  const _HotelMarkerIcon({this.isActive = false});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isActive ? Colors.orangeAccent : Colors.blueAccent,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: const Icon(Icons.hotel, color: Colors.white, size: 20),
    );
  }
}

class _HotelCarousel extends StatelessWidget {
  const _HotelCarousel({
    required this.hotels,
    required this.onHotelTap,
    required this.onCancelRoute,
    this.activeHotelId,
    this.loadingRoute = false,
  });

  final List<Hotel> hotels;
  final ValueChanged<Hotel> onHotelTap;
  final Future<void> Function() onCancelRoute;
  final String? activeHotelId;
  final bool loadingRoute;

  @override
  Widget build(BuildContext context) {
    if (hotels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 190,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color.fromARGB(200, 0, 0, 0)],
        ),
      ),
      padding: const EdgeInsets.only(bottom: 16, top: 32),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: hotels.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final hotel = hotels[index];
          final isActive = hotel.id == activeHotelId;

          return _HotelCard(
            hotel: hotel,
            isActive: isActive,
            loading: loadingRoute && isActive,
            onTap: () => onHotelTap(hotel),
            onCancelRoute: isActive ? onCancelRoute : null,
          );
        },
      ),
    );
  }
}

class _HotelCard extends StatelessWidget {
  const _HotelCard({
    required this.hotel,
    required this.onTap,
    this.onCancelRoute,
    this.isActive = false,
    this.loading = false,
  });

  final Hotel hotel;
  final VoidCallback onTap;
  final Future<void> Function()? onCancelRoute;
  final bool isActive;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: isActive ? 8 : 4,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          width: 280,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hotel.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  hotel.address,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: loading ? null : onTap,
                        child: loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(isActive ? 'Recalcular' : 'Ver ruta'),
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: onCancelRoute == null
                            ? null
                            : () => onCancelRoute!(),
                        child: const Text('Cancelar'),
                      ),
                    ],
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
      return const Text('Sin resenas', style: TextStyle(color: Colors.grey));
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
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.amber[900]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageSourceSheet extends StatelessWidget {
  const _ImageSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Tomar foto'),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Elegir de la galeria'),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
        ],
      ),
    );
  }
}

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog();

  @override
  Widget build(BuildContext context) {
    return const Dialog(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Analizando imagen...'),
          ],
        ),
      ),
    );
  }
}

class _GeminiResultSheet extends StatelessWidget {
  const _GeminiResultSheet({required this.result, this.hotel});

  final String result;
  final Hotel? hotel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hotel?.name ?? 'Analisis del hotel',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (hotel?.address != null) ...[
              const SizedBox(height: 8),
              Text(
                hotel!.address,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
              ),
            ],
            const SizedBox(height: 16),
            Text(result, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Listo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
