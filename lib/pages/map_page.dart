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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeMap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_mapController != null) {
      _mapController!.dispose();
      _mapController = null;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (_mapController != null) {
        _mapController!.dispose();
        _mapController = null;
      }
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

  void _onMapCreated(GoogleMapController controller) {
    if (!mounted) return;
    
    _mapController?.dispose();
    
    setState(() {
      _mapController = controller;
      isMapCreated = true;
    });
    
    _loadPOIs();  // Remove the delay, load immediately
  }

  void _onCameraMove(CameraPosition position) {
    _isCameraMoving = true;
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
      
      _polygons.add(
        Polygon(
          polygonId: const PolygonId('boundingBox'),
          points: [
            paddedNE,
            LatLng(paddedNE.latitude, paddedSW.longitude),
            paddedSW,
            LatLng(paddedSW.latitude, paddedNE.longitude),
          ],
          strokeWidth: 2,
          strokeColor: Colors.red,
          fillColor: Colors.red.withAlpha(100),
        ),
      );

      // Use the padded bounds for querying POIs
      jts.Envelope boundingBox = jts.Envelope(
        paddedSW.longitude,
        paddedNE.longitude,
        paddedSW.latitude,
        paddedNE.latitude,
      );

      List<jts.Point> points = await DbHelper().getPointsInBoundingBox(boundingBox, DbHelper.pois);
      
      if (points.isEmpty) {
        await DbHelper().downloadPointsFromOSM(boundingBox);
        points = await DbHelper().getPointsInBoundingBox(boundingBox, DbHelper.pois);
      }

      List<jts.Point> filteredPoints = [];
      Set<Marker> markers = {};
      
      // Filter POIs based on selected algorithm
      switch (selectedAlgorithm) {
        case ClusteringAlgorithm.none:
          // Show all points if less than 100
          // if (points.length > 100) {
          //   points.shuffle();
          //   filteredPoints = points.take(100).toList();
          // } else {
          //   filteredPoints = points;
          // }
          filteredPoints = points;
          break;
          
        case ClusteringAlgorithm.kMeans1:
          final kmeans1 = KMeansCluster1(k: points.length > 100 ? 10 : 5);
          filteredPoints = kmeans1.filterPOIs(points);
          break;
          
        case ClusteringAlgorithm.kMeans2:
          final kmeans2 = KMeansCluster2(k: points.length > 100 ? 10 : 5);
          filteredPoints = kmeans2.filterPOIs(points);
          break;
          
        case ClusteringAlgorithm.dbscan:
          // Adjusted epsilon based on map zoom level
          final zoom = await _mapController!.getZoomLevel();
          final epsilon = zoom > 16 ? 0.0003 : 0.0006; // Adjusted values
          final dbscan = DBSCANCluster(
            epsilon: epsilon,
            minPoints: points.length > 100 ? 3 : 2, // Reduced minPoints
          );
          filteredPoints = dbscan.filterPOIs(points);
          break;
          
        case ClusteringAlgorithm.hierarchical:
          final hierarchical = HierarchicalCluster(
            minClusters: points.length > 100 ? 15 : 8,
            linkageType: LINKAGE.AVERAGE, // Try AVERAGE instead of SINGLE
          );
          filteredPoints = hierarchical.filterPOIs(points);
          break;
      }

      // Create markers for filtered points
      for (var point in filteredPoints) {
        markers.add(
          Marker(
            markerId: MarkerId('${point.getX()}-${point.getY()}'),
            position: LatLng(point.getY(), point.getX()),
            icon: _getMarkerIcon(selectedAlgorithm),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _markers = markers;
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
              onCameraIdle: () {
                if (_isCameraMoving) {  // Only reload if camera was moving
                  _isCameraMoving = false;
                  _loadPOIs();
                }
              },
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