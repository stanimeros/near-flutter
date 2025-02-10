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

class _MapPageState extends State<MapPage> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  bool isLoading = true;
  bool isMapCreated = false;
  LatLng? initialPosition;
  String? errorMessage;
  ClusteringAlgorithm selectedAlgorithm = ClusteringAlgorithm.none;

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    try {
      GeoPoint? pos = await LocationService().getCurrentPosition();
      if (pos != null && mounted) {
        setState(() {
          initialPosition = LatLng(pos.latitude, pos.longitude);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          isLoading = false;
        });
      }
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    if (!mounted) return;
    setState(() {
      _mapController = controller;
      isMapCreated = true;
    });
    _loadPOIs();
  }

  Future<void> _loadPOIs() async {
    if (!isMapCreated || _mapController == null || !mounted) return;

    setState(() {
      isLoading = true;
    });

    try {
      LatLngBounds bounds = await _mapController!.getVisibleRegion();
      jts.Envelope boundingBox = jts.Envelope(
        bounds.southwest.longitude,
        bounds.northeast.longitude,
        bounds.southwest.latitude,
        bounds.northeast.latitude,
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
          // Show all points if less than 50, otherwise sample them
          if (points.length > 50) {
            points.shuffle();
            filteredPoints = points.take(50).toList();
          } else {
            filteredPoints = points;
          }
          break;
          
        case ClusteringAlgorithm.kMeans1:
          final kmeans1 = KMeansCluster1(k: 5);
          filteredPoints = kmeans1.filterPOIs(points);
          break;
          
        case ClusteringAlgorithm.kMeans2:
          final kmeans2 = KMeansCluster2(k: 5);
          filteredPoints = kmeans2.filterPOIs(points);
          break;
          
        case ClusteringAlgorithm.dbscan:
          final dbscan = DBSCANCluster(epsilon: 0.001, minPoints: 3);
          filteredPoints = dbscan.filterPOIs(points);
          break;
          
        case ClusteringAlgorithm.hierarchical:
          final hierarchical = HierarchicalCluster(minClusters: 5);
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
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          isLoading = false;
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
      return Center(child: Text('Error: $errorMessage'));
    }

    if (initialPosition == null) {
      return const Scaffold(
        body: Center(
          child: CustomLoader(),
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
                if (newValue != null) {
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPOIs,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: initialPosition!,
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: _markers,
            onCameraIdle: _loadPOIs,
          ),
          if (isLoading)
            const Positioned.fill(
              child: Center(
                child: CustomLoader(),
              ),
            ),
        ],
      ),
    );
  }
} 