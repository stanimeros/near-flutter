import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:flutter_near/services/detour_ratio_test.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';

class DetourTestMapPage extends StatefulWidget {
  final Map<String, dynamic> city;
  final int k;
  final int userIdx;

  const DetourTestMapPage({
    super.key,
    required this.city,
    required this.k,
    required this.userIdx,
  });

  @override
  State<DetourTestMapPage> createState() => _DetourTestMapPageState();
}

class _DetourTestMapPageState extends State<DetourTestMapPage> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  
  // Test data
  Point? _userSPOI;
  List<Map<String, dynamic>> _contacts = [];
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
      final userPoint = widget.city['test_points'][widget.userIdx];
      
      // Create Point object
      final userSpatialPoint = Point(userPoint['lon'], userPoint['lat']);

      // Generate SPOIs using 2HP approach
      final nearestPoint = await SpatialDb().getKNNs(1, userSpatialPoint.lon, userSpatialPoint.lat, 50, SpatialDb.pois, SpatialDb.cells);
      final userKNNs = await SpatialDb().getKNNs(widget.k, nearestPoint.first.lon, nearestPoint.first.lat, 50, SpatialDb.pois, SpatialDb.cells);

      if (userKNNs.isEmpty) {
        throw Exception('No KNN points found for user');
      }

      // Process all other test points as contacts
      final contacts = <Map<String, dynamic>>[];
      final spoiSeed = DateTime.now().millisecondsSinceEpoch;
      final spoiRandom = Random(spoiSeed);
      final userSPOI = userKNNs[spoiRandom.nextInt(userKNNs.length)];

      for (int contactIdx = 0; contactIdx < widget.city['test_points'].length; contactIdx++) {
        if (contactIdx == widget.userIdx) continue; // Skip self

        final contactPoint = widget.city['test_points'][contactIdx];
        final contactSpatialPoint = Point(contactPoint['lon'], contactPoint['lat']);

        // Generate SPOI for contact
        final nearestPointContact = await SpatialDb().getKNNs(
          1,
          contactSpatialPoint.lon,
          contactSpatialPoint.lat,
          50,
          SpatialDb.pois,
          SpatialDb.cells,
        );

        final contactKNNs = await SpatialDb().getKNNs(
          widget.k,
          nearestPointContact.first.lon,
          nearestPointContact.first.lat,
          50,
          SpatialDb.pois,
          SpatialDb.cells,
        );

        if (contactKNNs.isEmpty) continue;

        final contactSPOI = contactKNNs[spoiRandom.nextInt(contactKNNs.length)];
        
        // Calculate distances
        final trueDistance = Geolocator.distanceBetween(
          userPoint['lat'], userPoint['lon'],
          contactPoint['lat'], contactPoint['lon'],
        );
        final nearDistance = Geolocator.distanceBetween(
          userSPOI.lat, userSPOI.lon,
          contactSPOI.lat, contactSPOI.lon,
        );

        contacts.add({
          'contact_id': 'U${contactIdx + 1}',
          'true_location': {'lat': contactPoint['lat'], 'lon': contactPoint['lon']},
          'generated_spoi': {'lat': contactSPOI.lat, 'lon': contactSPOI.lon},
          'true_distance_m': trueDistance,
          'near_distance_m': nearDistance,
          'reported_rank': contacts.length + 1,
        });
      }

      if (contacts.isEmpty) {
        throw Exception('No valid contacts found');
      }

      // Get clusters between the user's SPOI and the first contact's SPOI
      final firstContact = contacts.first;
      final clusters = await SpatialDb().getClustersBetweenTwoPoints(
        userSPOI,
        Point(
          firstContact['generated_spoi']['lon'],
          firstContact['generated_spoi']['lat'],
        ),
      );
      
      if (clusters.isEmpty) {
        throw Exception('No clusters found between SPOIs');
      }
      
      // Select random cluster
      final meetingSeed = DateTime.now().millisecondsSinceEpoch;
      final meetingRandom = Random(meetingSeed);
      final selectedCluster = clusters[meetingRandom.nextInt(clusters.length)];

      // Calculate detour ratios for each user-contact pair
      final detourRatios = <String, double>{};
      var totalDetourRatio = 0.0;
      
      for (final contact in contacts) {
        final detourRatio = DetourRatioTest.calculateDetourRatio(
          userPoint['lat'], userPoint['lon'],
          contact['true_location']['lat'], contact['true_location']['lon'],
          selectedCluster.corePoint.lat, selectedCluster.corePoint.lon,
        );
        final pairKey = '${widget.userIdx + 1}-${contact['contact_id'].substring(1)}'; // e.g., "1-2" for U1-U2
        detourRatios[pairKey] = detourRatio;
        totalDetourRatio += detourRatio;
      }

      // Calculate average detour ratio
      final avgDetourRatio = contacts.isEmpty ? 0.0 : totalDetourRatio / contacts.length;

      // Update state
      setState(() {
        _userSPOI = userSPOI;
        _contacts = contacts;
        _clusters = clusters;
        _selectedCluster = selectedCluster;
        _testResult = {
          'detour_ratios': detourRatios,
          'avg_detour_ratio': avgDetourRatio,
          'spoi_seed': spoiSeed,
          'meeting_seed': meetingSeed,
        };
      });

      // Update map markers
      _updateMapMarkers(userPoint);
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error running test: $e')),
        );
      }
    }
  }

  void _updateMapMarkers(Map<String, double> userPoint) {
    Set<Marker> markers = {};

    // User true location
    markers.add(Marker(
      markerId: MarkerId('user_true'),
      position: LatLng(userPoint['lat']!, userPoint['lon']!),
      infoWindow: InfoWindow(title: 'User (True Location)'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
    ));

    // Contact true locations
    for (final contact in _contacts) {
      markers.add(Marker(
        markerId: MarkerId('${contact['contact_id']}_true'),
        position: LatLng(contact['true_location']['lat'], contact['true_location']['lon']),
        infoWindow: InfoWindow(title: '${contact['contact_id']} (True Location)'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ));
    }


    // User SPOI
    if (_userSPOI != null) {
      markers.add(Marker(
        markerId: MarkerId('user_spoi'),
        position: LatLng(_userSPOI!.lat, _userSPOI!.lon),
        infoWindow: InfoWindow(title: 'User SPOI'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
      ));
    }

    // Contact SPOIs
    for (final contact in _contacts) {
      markers.add(Marker(
        markerId: MarkerId('${contact['contact_id']}_spoi'),
        position: LatLng(contact['generated_spoi']['lat'], contact['generated_spoi']['lon']),
        infoWindow: InfoWindow(title: '${contact['contact_id']} SPOI'),
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
        infoWindow: InfoWindow(title: 'Meeting Point (Avg Detour: ${_testResult?['avg_detour_ratio']?.toStringAsFixed(2)})'),
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
                          Text(' True Locations (${_contacts.length + 1})'),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.location_on, color: Colors.cyan),
                          Text(' Selected SPOIs (${_contacts.length + 1})'),
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
                          Text('(Avg Detour Ratio: ${_testResult!['avg_detour_ratio'].toStringAsFixed(2)})', 
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
