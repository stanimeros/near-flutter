import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:flutter_near/services/detour_ratio_test.dart';
import 'dart:math';

class DetourTestMapPage extends StatefulWidget {
  final Map<String, dynamic> city;
  final int k;
  final int userAIdx;
  final int userBIdx;

  const DetourTestMapPage({
    super.key,
    required this.city,
    required this.k,
    required this.userAIdx,
    required this.userBIdx,
  });

  @override
  State<DetourTestMapPage> createState() => _DetourTestMapPageState();
}

class _DetourTestMapPageState extends State<DetourTestMapPage> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  
  // Test data
  List<Point> _userAKNNs = [];
  List<Point> _userBKNNs = [];
  Point? _userASPOI;
  Point? _userBSPOI;
  List<NearCluster> _clusters = [];
  NearCluster? _selectedCluster;
  Map<String, dynamic>? _testResult;

  @override
  void initState() {
    super.initState();
    _runDetourTest();
  }

  Future<void> _runDetourTest() async {
    try {
      // Get test points
      final userAPoint = widget.city['test_points'][widget.userAIdx];
      final userBPoint = widget.city['test_points'][widget.userBIdx];
      
      // Create Point objects
      final userASpatialPoint = Point(userAPoint['lon'], userAPoint['lat']);
      final userBSpatialPoint = Point(userBPoint['lon'], userBPoint['lat']);

      // Generate SPOIs using 2HP approach
      final nearestPointA = await SpatialDb().getKNNs(1, userASpatialPoint.lon, userASpatialPoint.lat, 50, SpatialDb.pois, SpatialDb.cells);
      final userAKNNs = await SpatialDb().getKNNs(widget.k, nearestPointA.first.lon, nearestPointA.first.lat, 50, SpatialDb.pois, SpatialDb.cells);
      
      final nearestPointB = await SpatialDb().getKNNs(1, userBSpatialPoint.lon, userBSpatialPoint.lat, 50, SpatialDb.pois, SpatialDb.cells);
      final userBKNNs = await SpatialDb().getKNNs(widget.k, nearestPointB.first.lon, nearestPointB.first.lat, 50, SpatialDb.pois, SpatialDb.cells);

      // Select random SPOIs
      final spoiSeed = DateTime.now().millisecondsSinceEpoch;
      final spoiRandom = Random(spoiSeed);
      final userASPOI = userAKNNs[spoiRandom.nextInt(userAKNNs.length)];
      final userBSPOI = userBKNNs[spoiRandom.nextInt(userBKNNs.length)];

      // Get clusters
      final clusters = await SpatialDb().getClustersBetweenTwoPoints(userASPOI, userBSPOI);
      
      // Select random cluster
      final meetingSeed = DateTime.now().millisecondsSinceEpoch;
      final meetingRandom = Random(meetingSeed);
      final selectedCluster = clusters[meetingRandom.nextInt(clusters.length)];

      // Calculate detour ratio
      final detourRatio = DetourRatioTest.calculateDetourRatio(
        userAPoint['lat'], userAPoint['lon'],
        userBPoint['lat'], userBPoint['lon'],
        selectedCluster.corePoint.lat, selectedCluster.corePoint.lon,
      );

      // Update state
      setState(() {
        _userAKNNs = userAKNNs;
        _userBKNNs = userBKNNs;
        _userASPOI = userASPOI;
        _userBSPOI = userBSPOI;
        _clusters = clusters;
        _selectedCluster = selectedCluster;
        _testResult = {
          'detour_ratio': detourRatio,
          'spoi_seed': spoiSeed,
          'meeting_seed': meetingSeed,
        };
      });

      // Update map markers
      _updateMapMarkers(userAPoint, userBPoint);
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error running test: $e')),
        );
      }
    }
  }

  void _updateMapMarkers(Map<String, double> userAPoint, Map<String, double> userBPoint) {
    Set<Marker> markers = {};

    // User true locations
    markers.add(Marker(
      markerId: MarkerId('user_a_true'),
      position: LatLng(userAPoint['lat']!, userAPoint['lon']!),
      infoWindow: InfoWindow(title: 'User A (True Location)'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
    ));

    markers.add(Marker(
      markerId: MarkerId('user_b_true'),
      position: LatLng(userBPoint['lat']!, userBPoint['lon']!),
      infoWindow: InfoWindow(title: 'User B (True Location)'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
    ));

    // User A KNN points
    for (int i = 0; i < _userAKNNs.length; i++) {
      markers.add(Marker(
        markerId: MarkerId('user_a_knn_$i'),
        position: LatLng(_userAKNNs[i].lat, _userAKNNs[i].lon),
        infoWindow: InfoWindow(title: 'User A KNN $i'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    }

    // User B KNN points
    for (int i = 0; i < _userBKNNs.length; i++) {
      markers.add(Marker(
        markerId: MarkerId('user_b_knn_$i'),
        position: LatLng(_userBKNNs[i].lat, _userBKNNs[i].lon),
        infoWindow: InfoWindow(title: 'User B KNN $i'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ));
    }

    // Selected SPOIs
    if (_userASPOI != null) {
      markers.add(Marker(
        markerId: MarkerId('user_a_spoi'),
        position: LatLng(_userASPOI!.lat, _userASPOI!.lon),
        infoWindow: InfoWindow(title: 'User A SPOI'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
      ));
    }

    if (_userBSPOI != null) {
      markers.add(Marker(
        markerId: MarkerId('user_b_spoi'),
        position: LatLng(_userBSPOI!.lat, _userBSPOI!.lon),
        infoWindow: InfoWindow(title: 'User B SPOI'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
      ));
    }

    // All clusters
    for (int i = 0; i < _clusters.length; i++) {
      markers.add(Marker(
        markerId: MarkerId('cluster_$i'),
        position: LatLng(_clusters[i].corePoint.lat, _clusters[i].corePoint.lon),
        infoWindow: InfoWindow(title: 'Cluster ${_clusters[i].id}'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
      ));
    }

    // Selected cluster (meeting point)
    if (_selectedCluster != null) {
      markers.add(Marker(
        markerId: MarkerId('meeting_point'),
        position: LatLng(_selectedCluster!.corePoint.lat, _selectedCluster!.corePoint.lon),
        infoWindow: InfoWindow(title: 'Meeting Point (Detour: ${_testResult?['detour_ratio']?.toStringAsFixed(2)})'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }

    setState(() {
      _markers = markers;
    });
    
    // Fit map to show all markers
    _fitMapToMarkers();
  }

  void _fitMapToMarkers() {
    if (_mapController == null || _markers.isEmpty) return;
    
    // Calculate bounds for all markers
    double minLat = _markers.first.position.latitude;
    double maxLat = _markers.first.position.latitude;
    double minLng = _markers.first.position.longitude;
    double maxLng = _markers.first.position.longitude;
    
    for (Marker marker in _markers) {
      minLat = math.min(minLat, marker.position.latitude);
      maxLat = math.max(maxLat, marker.position.latitude);
      minLng = math.min(minLng, marker.position.longitude);
      maxLng = math.max(maxLng, marker.position.longitude);
    }
    
    // Add padding
    double latPadding = (maxLat - minLat) * 0.1;
    double lngPadding = (maxLng - minLng) * 0.1;
    
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - latPadding, minLng - lngPadding),
          northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
        ),
        100.0, // padding
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.city['name']} - k=${widget.k}'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
            GoogleMap(
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
                // Fit map to show all markers
                _fitMapToMarkers();
              },
            initialCameraPosition: CameraPosition(
              target: LatLng(widget.city['center']['lat'], widget.city['center']['lon']),
              zoom: 12.0,
            ),
            markers: _markers,
          ),
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.location_on, color: Colors.blue),
                          Text(' True Locations (2)'),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.location_on, color: Colors.green),
                          Text(' User A KNN Points (${_userAKNNs.length})'),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.location_on, color: Colors.orange),
                          Text(' User B KNN Points (${_userBKNNs.length})'),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.location_on, color: Colors.cyan),
                          Text(' Selected SPOIs (2)'),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.location_on, color: Colors.yellow),
                          Text(' Available Clusters (${_clusters.length})'),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.location_on, color: Colors.red),
                          Text(' Meeting Point'),
                          if (_testResult != null) ...[
                          SizedBox(width: 4),
                          Text('(Detour Ratio: ${_testResult!['detour_ratio'].toStringAsFixed(2)})', 
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _runDetourTest();
        },
        backgroundColor: Colors.blue,
        child: Icon(Icons.refresh),
      ),
    );
  }
}
