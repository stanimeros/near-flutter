import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'package:flutter_near/services/db_helper.dart';
import 'package:flutter_near/services/location.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_near/algorithms/kmeans.dart';
import 'package:flutter_near/algorithms/dbscan.dart';
import 'package:flutter_near/algorithms/hierarchical.dart';
import 'package:simple_cluster/simple_cluster.dart';

enum ClusteringAlgorithm {
  none,
  random,
  kMeans1,
  kMeans2,
  dbscan,
  hierarchical
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polygon> _polygons = {};
  bool isLoadingLocation = true;  // For initial location loading
  bool isLoadingPOIs = false;     // For POIs loading
  bool isMapCreated = false;
  LatLng? initialPosition;
  String? errorMessage;
  ClusteringAlgorithm selectedAlgorithm = ClusteringAlgorithm.none;
  bool _isCameraMoving = false;

  static const int targetPoints = 20;  // Desired number of points
  static const double minDistance = 0.0003;  // Min distance between points
  static const double targetRadiusMeters = 50.0;
  static const double metersPerDegree = 111000.0; // At equator

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeMap();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _mapController = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _mapController?.dispose();
      _mapController = null;
    }
  }

  Future<void> _initializeMap() async {
    try {
      // First get location
      GeoPoint? pos = await LocationService().getCurrentPosition();
      if (!mounted) return;

      if (pos != null) {
        setState(() {
          initialPosition = LatLng(pos.latitude, pos.longitude);
          isLoadingLocation = false;
        });
      } else {
        throw Exception('Could not get location');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> _updateCellsVisualization() async {
    debugPrint('=== Starting cell visualization update ===');
    final startTime = DateTime.now();

    if (!isMapCreated || _mapController == null) return;

    try {
      final boundsStart = DateTime.now();
      LatLngBounds bounds = await _mapController!.getVisibleRegion();
      debugPrint('Got bounds in ${DateTime.now().difference(boundsStart).inMilliseconds}ms');

      jts.Envelope boundingBox = jts.Envelope(
        bounds.southwest.longitude,
        bounds.northeast.longitude, 
        bounds.southwest.latitude,
        bounds.northeast.latitude
      );

      final cellsStart = DateTime.now();
      final downloadedCells = DbHelper.db.getGeometriesIn(DbHelper.cells, envelope: boundingBox);
      debugPrint('Got cells in ${DateTime.now().difference(cellsStart).inMilliseconds}ms');

      final drawStart = DateTime.now();
      setState(() {
        _polygons.clear();

        // Add current view area polygon
        _polygons.add(
          Polygon(
            polygonId: const PolygonId('currentArea'),
            points: [
              bounds.northeast,
              LatLng(bounds.northeast.latitude, bounds.southwest.longitude),
              bounds.southwest,
              LatLng(bounds.southwest.latitude, bounds.northeast.longitude),
            ],
            strokeWidth: 2,
            strokeColor: Colors.red,
            fillColor: Colors.red.withAlpha(32),
          ),
        );

        // Convert bounds to grid coordinates
        int minX = (bounds.southwest.longitude / DbHelper.gridSize).floor();
        int maxX = (bounds.northeast.longitude / DbHelper.gridSize).floor();
        int minY = (bounds.southwest.latitude / DbHelper.gridSize).floor();
        int maxY = (bounds.northeast.latitude / DbHelper.gridSize).floor();

        // Add cell polygons
        for (int x = minX; x <= maxX; x++) {
          for (int y = minY; y <= maxY; y++) {
            bool isDownloaded = false;
            for (var geom in downloadedCells) {
              if (geom != null) {
                jts.Point point = geom as jts.Point;
                if (point.getX() == x && point.getY() == y) {
                  isDownloaded = true;
                  break;
                }
              }
            }
            
            // Calculate cell corners
            double minLon = x * DbHelper.gridSize;
            double maxLon = (x + 1) * DbHelper.gridSize;
            double minLat = y * DbHelper.gridSize;
            double maxLat = (y + 1) * DbHelper.gridSize;

            _polygons.add(
              Polygon(
                polygonId: PolygonId('cell_${x}_$y'),
                points: [
                  LatLng(maxLat, maxLon), // NE
                  LatLng(maxLat, minLon), // NW
                  LatLng(minLat, minLon), // SW
                  LatLng(minLat, maxLon), // SE
                ],
                strokeWidth: 1,
                strokeColor: isDownloaded ? Colors.blue : Colors.grey,
                fillColor: isDownloaded ? 
                  Colors.blue.withAlpha(32) : 
                  Colors.grey.withAlpha(16),
              ),
            );
          }
        }
      });
      debugPrint('Drew cells in ${DateTime.now().difference(drawStart).inMilliseconds}ms');
      
      debugPrint('=== Finished visualization in ${DateTime.now().difference(startTime).inMilliseconds}ms ===');
    } catch (e) {
      debugPrint('Error updating cells visualization: $e');
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    isMapCreated = true;
    _updateCellsVisualization(); // Show cells when map is ready
  }

  void _onCameraMove(CameraPosition position) {
    _isCameraMoving = true;
  }

  void _onCameraIdle() {
    if (_isCameraMoving) {
      _isCameraMoving = false;
      _loadPOIs();
      _updateCellsVisualization(); // Update cells when camera stops
    }
  }

  Future<void> _loadPOIs() async {
    if (!isMapCreated || _mapController == null || !mounted) return;

    setState(() {
      isLoadingPOIs = true;
      _markers = {};
      _polygons = {};
    });

    try {
      // Get current center instead of bounds
      LatLngBounds bounds = await _mapController!.getVisibleRegion();
      LatLng center = LatLng(
        (bounds.northeast.latitude + bounds.southwest.latitude) / 2,
        (bounds.northeast.longitude + bounds.southwest.longitude) / 2
      );
      
      // Calculate degree offset for 50m radius
      double latOffset = targetRadiusMeters / metersPerDegree;
      double lonOffset = targetRadiusMeters / (metersPerDegree * cos(center.latitude * pi / 180));

      // Create bounds from center point
      LatLng northeast = LatLng(
        center.latitude + latOffset,
        center.longitude + lonOffset
      );
      LatLng southwest = LatLng(
        center.latitude - latOffset,
        center.longitude - lonOffset
      );
      
      // Show current area in red
      _polygons.add(
        Polygon(
          polygonId: const PolygonId('currentArea'),
          points: [
            northeast,
            LatLng(northeast.latitude, southwest.longitude),
            southwest,
            LatLng(southwest.latitude, northeast.longitude),
          ],
          strokeWidth: 2,
          strokeColor: Colors.red,
          fillColor: Colors.red.withAlpha(50),
        ),
      );

      // Use the 50m radius bounds for querying POIs
      jts.Envelope boundingBox = jts.Envelope(
        southwest.longitude,
        northeast.longitude,
        southwest.latitude,
        northeast.latitude,
      );

      // First try to get points from DB
      List<jts.Point> points = await DbHelper().getPointsInBoundingBox(boundingBox);

      List<jts.Point> filteredPoints = [];
      final zoom = await _mapController!.getZoomLevel();
      
      switch (selectedAlgorithm) {
        case ClusteringAlgorithm.none:
          filteredPoints = points;
          break;

        case ClusteringAlgorithm.random:
          points.shuffle();
          filteredPoints = points.take(targetPoints).toList();
          break;
          
        case ClusteringAlgorithm.kMeans1:
          final k = max(3, min(15, points.length ~/ 10));
          final kmeans1 = KMeansCluster1(k: k);
          filteredPoints = kmeans1.filterPOIs(points);
          break;
          
        case ClusteringAlgorithm.kMeans2:
          final k = max(3, min(15, points.length ~/ 10));
          final kmeans2 = KMeansCluster2(k: k);
          filteredPoints = kmeans2.filterPOIs(points);
          break;
          
        case ClusteringAlgorithm.dbscan:
          double epsilon = minDistance * (20 / zoom);
          final dbscan = DBSCANCluster(
            epsilon: epsilon,
            minPoints: max(2, min(5, points.length ~/ 50)),
          );
          filteredPoints = dbscan.filterPOIs(points);
          break;
          
        case ClusteringAlgorithm.hierarchical:
          final minClusters = max(3, min(15, points.length ~/ targetPoints));
          final hierarchical = HierarchicalCluster(
            minClusters: minClusters,
            linkageType: LINKAGE.AVERAGE,
          );
          filteredPoints = hierarchical.filterPOIs(points);
          break;
      }

      // Create markers for filtered points
      for (var point in filteredPoints) {
        _markers.add(
          Marker(
            markerId: MarkerId('${point.getX()}-${point.getY()}'),
            position: LatLng(point.getY(), point.getX()),
            icon: _getMarkerIcon(selectedAlgorithm),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _markers = _markers;
          _polygons = _polygons;
          isLoadingPOIs = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("${filteredPoints.length} POIs displayed"),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          isLoadingPOIs = false;
        });
      }
    }
  }

  BitmapDescriptor _getMarkerIcon(ClusteringAlgorithm algorithm) {
    switch (algorithm) {
      case ClusteringAlgorithm.none:
        return BitmapDescriptor.defaultMarker;
      case ClusteringAlgorithm.random:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      case ClusteringAlgorithm.kMeans1:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
      case ClusteringAlgorithm.kMeans2:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      case ClusteringAlgorithm.dbscan:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
      case ClusteringAlgorithm.hierarchical:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: $errorMessage'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initializeMap,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (isLoadingLocation || initialPosition == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomLoader(),
              SizedBox(height: 16),
              Text('Getting location...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('POIs Map'),
        actions: [
          // Clear DB Button
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear all data',
            onPressed: () async {
              setState(() {
                isLoadingPOIs = true;
              });
              
              await DbHelper().emptyTable(DbHelper.pois);
              
              setState(() {
                _markers = {};
                _polygons = {};
                isLoadingPOIs = false;
              });

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All data cleared'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 8),
          Theme(
            data: Theme.of(context).copyWith(
              popupMenuTheme: PopupMenuThemeData(
                textStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            child: DropdownButton<ClusteringAlgorithm>(
              value: selectedAlgorithm,
              dropdownColor: Theme.of(context).colorScheme.surface,
              onChanged: (ClusteringAlgorithm? newValue) {
                if (newValue != null && mounted) {
                  setState(() {
                    selectedAlgorithm = newValue;
                  });
                  _loadPOIs();
                }
              },
              items: ClusteringAlgorithm.values.map((ClusteringAlgorithm algorithm) {
                return DropdownMenuItem<ClusteringAlgorithm>(
                  value: algorithm,
                  child: Text(
                    algorithm.toString().split('.').last,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Stack(
        children: [
          if (!isLoadingLocation && initialPosition != null)
            GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: initialPosition!,
                zoom: 17,
              ),
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              markers: _markers,
              polygons: _polygons,
              onCameraMove: _onCameraMove,
              onCameraIdle: _onCameraIdle,
            ),
          if (isLoadingPOIs)
            Container(
              color: Colors.black.withAlpha(100),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CustomLoader(),
                    SizedBox(height: 16),
                    Text(
                      'Loading POIs...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
} 