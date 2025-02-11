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
    if (!isMapCreated || _mapController == null) return;

    try {
      LatLngBounds bounds = await _mapController!.getVisibleRegion();
      const gridSize = 0.001; // Same as DbHelper.gridSize

      // Create JTS envelope from bounds
      jts.Envelope boundingBox = jts.Envelope(
        bounds.southwest.longitude,
        bounds.northeast.longitude, 
        bounds.southwest.latitude,
        bounds.northeast.latitude
      );

      // Get downloaded cells
      final downloadedCells = await DbHelper().getCellsInArea(boundingBox);

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
        int minX = (bounds.southwest.longitude / gridSize).floor();
        int maxX = (bounds.northeast.longitude / gridSize).floor();
        int minY = (bounds.southwest.latitude / gridSize).floor();
        int maxY = (bounds.northeast.latitude / gridSize).floor();

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
            double minLon = x * gridSize;
            double maxLon = (x + 1) * gridSize;
            double minLat = y * gridSize;
            double maxLat = (y + 1) * gridSize;

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
      LatLngBounds bounds = await _mapController!.getVisibleRegion();
      
      // Add padding to the bounding box (about 10% inset)
      double latPadding = (bounds.northeast.latitude - bounds.southwest.latitude) * 0.1;
      double lngPadding = (bounds.northeast.longitude - bounds.southwest.longitude) * 0.1;
      
      // Create padded bounds for visualization
      LatLng paddedNE = LatLng(
        bounds.northeast.latitude - latPadding,
        bounds.northeast.longitude - lngPadding
      );
      LatLng paddedSW = LatLng(
        bounds.southwest.latitude + latPadding,
        bounds.southwest.longitude + lngPadding
      );
      
      // Show current area in red
      _polygons.add(
        Polygon(
          polygonId: const PolygonId('currentArea'),
          points: [
            paddedNE,
            LatLng(paddedNE.latitude, paddedSW.longitude),
            paddedSW,
            LatLng(paddedSW.latitude, paddedNE.longitude),
          ],
          strokeWidth: 2,
          strokeColor: Colors.red,
          fillColor: Colors.red.withAlpha(50),
        ),
      );

      // Use the padded bounds for querying POIs
      jts.Envelope boundingBox = jts.Envelope(
        paddedSW.longitude,
        paddedNE.longitude,
        paddedSW.latitude,
        paddedNE.latitude,
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