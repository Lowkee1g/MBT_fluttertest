import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;

/// A Flutter widget that displays an interactive map using MBTiles.
/// 
/// MBTiles is a specification for storing tiled web maps in SQLite databases.
/// This implementation:
/// - On web: Shows OpenStreetMap tiles as MBTiles requires file system access
/// - On mobile/desktop: Loads the actual MBTiles file and displays custom tiles
/// 
/// The widget handles:
/// - Loading MBTiles from assets and copying to app directory
/// - Reading tile data from SQLite database
/// - Converting between XYZ and TMS coordinate systems
/// - Displaying tiles with proper attribution

class MBTilesMapView extends StatefulWidget {
  const MBTilesMapView({super.key});

  @override
  State<MBTilesMapView> createState() => _MBTilesMapViewState();
}

class _MBTilesMapViewState extends State<MBTilesMapView> {
  Database? _database;
  bool _isLoading = false;
  String? _error;
  LatLng _center = const LatLng(55.6761, 12.5683); // Copenhagen, Denmark
  double _zoom = 8.0;

  @override
  void initState() {
    super.initState();
    _initializeMBTiles();
  }

  @override
  void dispose() {
    _database?.close();
    super.dispose();
  }

  Future<void> _initializeMBTiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (kIsWeb) {
        // On web, we'll use a simpler approach - check if MBTiles file is accessible
        await _checkWebMBTilesAvailable();
      } else {
        // On mobile/desktop, implement full MBTiles support
        await _loadMBTilesDatabase();
      }
      
      if (!kIsWeb) {
        await _getMapBounds();
      }
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load MBTiles: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _checkWebMBTilesAvailable() async {
    try {
      // Check if the MBTiles file is accessible as a static asset
      final response = await http.get(Uri.parse('denmark_vfr.mbtiles'));
      if (response.statusCode == 200) {
        if (kDebugMode) {
          print('MBTiles file found in web folder, size: ${response.bodyBytes.length} bytes');
        }
        // We can't easily parse SQLite in web, but we know the file is there
        // For demo purposes, we'll show it's available but use OpenStreetMap
      } else {
        throw Exception('MBTiles file not accessible: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Web MBTiles check failed: $e');
      }
      rethrow;
    }
  }

  Future<void> _loadMBTilesDatabase() async {
    // Copy MBTiles file from assets to app directory
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = '${documentsDirectory.path}/denmark_vfr.mbtiles';
    
    // Check if file already exists, if not copy it
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      final ByteData data = await rootBundle.load('lib/MBtiles/denmark_vfr.mbtiles');
      final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await dbFile.writeAsBytes(bytes);
    }

    // Open the database
    _database = await openDatabase(dbPath, readOnly: true);
  }

  Future<void> _getMapBounds() async {
    if (_database == null) return;
    
    try {
      // Get metadata from the MBTiles file
      final List<Map<String, dynamic>> metadataResult = await _database!.query('metadata');
      final Map<String, String> metadata = {};
      
      for (var row in metadataResult) {
        metadata[row['name']] = row['value'];
      }
      
      // Parse bounds if available
      if (metadata.containsKey('bounds')) {
        final bounds = metadata['bounds']!.split(',').map(double.parse).toList();
        if (bounds.length == 4) {
          final centerLat = (bounds[1] + bounds[3]) / 2;
          final centerLng = (bounds[0] + bounds[2]) / 2;
          _center = LatLng(centerLat, centerLng);
        }
      }
      
      // Set zoom level based on available zoom levels
      if (metadata.containsKey('minzoom')) {
        final minZoom = double.tryParse(metadata['minzoom']!) ?? 0;
        final maxZoom = double.tryParse(metadata['maxzoom'] ?? '18') ?? 18;
        _zoom = (minZoom + maxZoom) / 2;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error reading metadata: $e');
      }
    }
  }

  Future<Uint8List?> _getTile(int x, int y, int z) async {
    if (_database == null) return null;
    
    try {
      // MBTiles uses TMS (Tile Map Service) coordinate system
      // Convert from XYZ to TMS
      final tmsY = (1 << z) - 1 - y;
      
      final List<Map<String, dynamic>> result = await _database!.query(
        'tiles',
        where: 'zoom_level = ? AND tile_column = ? AND tile_row = ?',
        whereArgs: [z, x, tmsY],
      );
      
      if (result.isNotEmpty) {
        return result.first['tile_data'] as Uint8List;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading tile ($x, $y, $z): $e');
      }
    }
    
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading map...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('MBTiles Map'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Error',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _isLoading = true;
                  });
                  _initializeMBTiles();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map View - Denmark Region'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          if (kIsWeb)
            Container(
              width: double.infinity,
              color: Colors.orange.shade50,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.info, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Web: MBTiles file found! Using OpenStreetMap for display (SQLite parsing in web requires additional setup).',
                      style: TextStyle(color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
          if (!kIsWeb && _database != null)
            Container(
              width: double.infinity,
              color: Colors.green.shade50,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'MBTiles loaded successfully! Showing Denmark VFR aeronautical chart.',
                      style: TextStyle(color: Colors.green.shade800),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _center,
                initialZoom: _zoom,
                minZoom: 1,
                maxZoom: 18,
              ),
              children: [
                if (kIsWeb || _database == null)
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.flutter_application_1',
                  ),
                if (!kIsWeb && _database != null)
                  TileLayer(
                    tileProvider: MBTilesTileProvider(_getTile),
                    userAgentPackageName: 'com.example.flutter_application_1',
                    maxZoom: 18,
                  ),
                RichAttributionWidget(
                  attributions: [
                    if (kIsWeb || _database == null)
                      TextSourceAttribution(
                        '© OpenStreetMap contributors',
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Map data © OpenStreetMap contributors')),
                        ),
                      ),
                    if (!kIsWeb && _database != null)
                      TextSourceAttribution(
                        'Denmark VFR MBTiles',
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Denmark VFR Aeronautical Chart')),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "demo_info",
            mini: true,
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('MBTiles Demo'),
                    content: const Text(
                      'This demo shows how MBTiles would work:\n\n'
                      '• On mobile/desktop: Load local .mbtiles file\n'
                      '• Extract tiles from SQLite database\n'
                      '• Display custom map tiles\n\n'
                      'Web version shows OpenStreetMap as fallback.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('OK'),
                      ),
                    ],
                  );
                },
              );
            },
            child: const Icon(Icons.help),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "center",
            mini: true,
            onPressed: () {
              // Center the map on Denmark
              setState(() {
                _center = const LatLng(55.6761, 12.5683);
                _zoom = 8.0;
              });
            },
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }
}

class MBTilesTileProvider extends TileProvider {
  final Future<Uint8List?> Function(int x, int y, int z) getTile;

  MBTilesTileProvider(this.getTile);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return MBTilesImageProvider(
      coordinates: coordinates,
      getTile: getTile,
    );
  }
}

class MBTilesImageProvider extends ImageProvider<MBTilesImageProvider> {
  final TileCoordinates coordinates;
  final Future<Uint8List?> Function(int x, int y, int z) getTile;

  const MBTilesImageProvider({
    required this.coordinates,
    required this.getTile,
  });

  @override
  Future<MBTilesImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<MBTilesImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(MBTilesImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(
      _loadAsync(key, decode),
    );
  }

  Future<ImageInfo> _loadAsync(MBTilesImageProvider key, ImageDecoderCallback decode) async {
    try {
      final tileData = await getTile(coordinates.x, coordinates.y, coordinates.z);
      
      if (tileData != null) {
        final buffer = await ui.ImmutableBuffer.fromUint8List(tileData);
        final codec = await decode(buffer);
        final frameInfo = await codec.getNextFrame();
        return ImageInfo(image: frameInfo.image);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading image: $e');
      }
    }
    
    // Return a transparent image if tile loading fails
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 256, 256),
      Paint()..color = Colors.transparent,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(256, 256);
    return ImageInfo(image: image);
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is MBTilesImageProvider &&
        other.coordinates == coordinates;
  }

  @override
  int get hashCode => coordinates.hashCode;
}

