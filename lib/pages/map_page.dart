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

  static const double targetBoxSize = 50.0;
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

  Future<jts.Envelope> getTargetBoundingBox() async {
    LatLngBounds bounds = await _mapController!.getVisibleRegion();
    LatLng center = LatLng(
      (bounds.northeast.latitude + bounds.southwest.latitude) / 2,
      (bounds.northeast.longitude + bounds.southwest.longitude) / 2
    );
    
    // Calculate 50m box
    double latOffset = targetBoxSize / metersPerDegree;
    double lonOffset = targetBoxSize / (metersPerDegree * cos(center.latitude * pi / 180));

    // Create 50m bounding box
    jts.Envelope searchBox = jts.Envelope(
      center.longitude - lonOffset,
      center.longitude + lonOffset,
      center.latitude - latOffset,
      center.latitude + latOffset,
    );

    return searchBox;
  }

  Future<void> _updateCellsVisualization() async {
    if (!isMapCreated || _mapController == null) return;
    final startTime = DateTime.now();

    try {
      // Get current center for 50m box
      jts.Envelope searchBox = await getTargetBoundingBox();

      debugPrint('Getting cells from DB...');
      // Get cells from DB directly using SQL for better performance
      final downloadedCells = DbHelper.db.select(
        'SELECT cell_x, cell_y FROM ${DbHelper.cells.fixedName}'
      );
      
      debugPrint('Getting points in search box...');
      // Get points in search box for green cells
      List<jts.Point> pointsInBox = await DbHelper().getPointsInBoundingBox(searchBox);
      final greenCellKeys = pointsInBox.map((point) => 
        '${(point.getX() / DbHelper.gridSize).floor()},${(point.getY() / DbHelper.gridSize).floor()}'
      ).toSet();

      setState(() {
        _polygons.clear();
      });

      setState(() {
        // 1. Add all downloaded cells (blue)
        downloadedCells.forEach((row) {
          final x = row.get('cell_x') as int;
          final y = row.get('cell_y') as int;
          
          double minLon = x * DbHelper.gridSize;
          double maxLon = (x + 1) * DbHelper.gridSize;
          double minLat = y * DbHelper.gridSize;
          double maxLat = (y + 1) * DbHelper.gridSize;

          // Check if this cell should be green (in search box) or blue (just downloaded)
          final isInSearchBox = greenCellKeys.contains('$x,$y');
          
          _polygons.add(
            Polygon(
              polygonId: PolygonId('cell_${x}_$y'),
              points: [
                LatLng(maxLat, maxLon),
                LatLng(maxLat, minLon),
                LatLng(minLat, minLon),
                LatLng(minLat, maxLon),
              ],
              strokeWidth: 1,
              strokeColor: isInSearchBox ? Colors.green : Colors.blue,
              fillColor: isInSearchBox ? 
                Colors.green.withAlpha(50) : 
                Colors.blue.withAlpha(50),
            ),
          );
        });

        // 2. Show the 50m search box outline in red
        _polygons.add(
          Polygon(
            polygonId: const PolygonId('searchArea'),
            points: [
              LatLng(searchBox.getMinY(), searchBox.getMinX()),
              LatLng(searchBox.getMaxY(), searchBox.getMinX()),
              LatLng(searchBox.getMaxY(), searchBox.getMaxX()),
              LatLng(searchBox.getMinY(), searchBox.getMaxX()),
            ],
            strokeWidth: 2,
            strokeColor: Colors.red,
            fillColor: Colors.red.withAlpha(50),
          ),
        );
      });
    } catch (e) {
      debugPrint('Error updating cells visualization: $e');
    }
    final endTime = DateTime.now();
    debugPrint('Visualization time taken: ${endTime.difference(startTime).inMilliseconds}ms');
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
    });

    try {
      // Get current center and bounds
      jts.Envelope searchBox = await getTargetBoundingBox();

      // First try to get points from DB
      final zoom = await _mapController!.getZoomLevel();
      List<jts.Point> points = await DbHelper().getPointsInBoundingBox(searchBox);

      // Dynamic clustering parameters
      int pointCount = points.length;
      debugPrint('Found $pointCount points');

      // Calculate target markers based on zoom
      double zoomFactor = (zoom - 15) / 5;  // 0.0 at zoom 15, 1.0 at zoom 20
      zoomFactor = max(0.0, min(1.0, zoomFactor));  
      int targetCount = (5 + (10 * zoomFactor)).round();  // 5 at zoom 15, 15 at zoom 20
      targetCount = min(pointCount, targetCount);

      // Minimum distance decreases with zoom
      double minDistanceMeters = targetBoxSize / (5 + (10 * zoomFactor));  // 15m at zoom 20, 50m at zoom 15

      debugPrint('Target: $targetCount points, min distance: ${minDistanceMeters.round()}m');

      List<jts.Point> filteredPoints = [];
      switch (selectedAlgorithm) {
        case ClusteringAlgorithm.none:
          filteredPoints = points;
          break;

        case ClusteringAlgorithm.random:
          filteredPoints = points.length > targetCount ? 
            points.take(targetCount).toList() : points;
          break;
          
        case ClusteringAlgorithm.kMeans1:
          // K-means works best with exact k value
          final kmeans = KMeansCluster1(k: targetCount);
          filteredPoints = kmeans.filterPOIs(points);
          break;
          
        case ClusteringAlgorithm.kMeans2: 
          // K-means works best with exact k value
          final kmeans = KMeansCluster2(k: targetCount);
          filteredPoints = kmeans.filterPOIs(points);
          break;
          
        case ClusteringAlgorithm.dbscan:
          // DBSCAN needs epsilon and minPoints tuned to get close to target
          // Adjust epsilon based on point density to get closer to target count
          double pointDensity = points.length / (targetBoxSize * targetBoxSize);
          double adjustedEpsilon = minDistanceMeters * sqrt(targetCount / max(1.0, pointDensity));
          
          final dbscan = DBSCANCluster(
            epsilon: adjustedEpsilon / metersPerDegree,
            minPoints: max(2, min(4, points.length ~/ (targetCount * 2))),
            targetCount: targetCount,
          );
          filteredPoints = dbscan.filterPOIs(points);
          break;
          
        case ClusteringAlgorithm.hierarchical:
          // Hierarchical needs slightly more clusters to get close to target
          final adjustedClusters = targetCount;
          final hierarchical = HierarchicalCluster(
            minClusters: adjustedClusters,
            linkageType: LINKAGE.AVERAGE,
          );
          filteredPoints = hierarchical.filterPOIs(points);
          break;
      }

      debugPrint('Found ${points.length} points, target: $targetCount, filtered to: ${filteredPoints.length}');

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

      // Update visualization after loading POIs
      await _updateCellsVisualization();
      
    } catch (e) {
      debugPrint('Error loading POIs: $e');
    } finally {
      if (mounted) {
        setState(() {
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
              await DbHelper().emptyTable(DbHelper.cells);
              
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