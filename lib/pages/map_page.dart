import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_near/services/location.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_near/models/meeting.dart';
import 'package:flutter_near/models/near_user.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:flutter_near/widgets/meeting_confirmation_sheet.dart';
import 'dart:async';

enum MapMode {
  normal,
  suggestMeeting,
}

class MapPage extends StatefulWidget {
  final MapMode mode;
  final NearUser? friend;
  final NearUser? currentUser;

  const MapPage({
    super.key,
    this.mode = MapMode.normal,
    this.friend,
    this.currentUser,
  });

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  bool isLoadingLocation = true;  // For initial location loading
  bool isLoadingPOIs = false;     // For POIs loading
  bool isMapCreated = false;
  LatLng? initialPosition;
  bool _isCameraMoving = false;
  Point? _selectedPOI;
  final Map<String, Set<Marker>> _cellMarkers = {}; // Track markers per cell
  final Set<Polygon> _cellPolygons = {};  // Add this for cell visualization
  static const int poisPerCell = 25;   // Show 50 POIs per cell

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

      if (pos != null) {
        setState(() {
          initialPosition = LatLng(pos.latitude, pos.longitude);
          isLoadingLocation = false;
        });

        // Once map is created and location is known, center the box
        if (_mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLng(initialPosition!)
          );
        }
      } else {
        throw Exception('Could not get location');
      }
    } catch (e) {
      setState(() {
        isLoadingLocation = false;
      });
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    isMapCreated = true;
    
    // If we already have location, center the map and box
    if (initialPosition != null) {
      controller.animateCamera(
        CameraUpdate.newLatLng(initialPosition!)
      );
    }
  }

  void _onCameraMove(CameraPosition position) {
    _isCameraMoving = true;
  }

  void _onCameraIdle() {
    if (_isCameraMoving) {
      _isCameraMoving = false;
      _loadPOIsInViewport();
    }
  }

  Future<void> _loadPOIsInViewport() async {
    if (_mapController == null) return;

    final LatLngBounds visibleBounds = await _mapController!.getVisibleRegion();
    final visibleBoundingBox = BoundingBox(
      visibleBounds.southwest.longitude,
      visibleBounds.northeast.longitude,
      visibleBounds.southwest.latitude,
      visibleBounds.northeast.latitude
    );
    
    // Add blue polygon for viewport
    final viewportPolygon = Polygon(
      polygonId: const PolygonId('viewport'),
      points: [
        visibleBounds.southwest,
        LatLng(visibleBounds.southwest.latitude, visibleBounds.northeast.longitude),
        visibleBounds.northeast,
        LatLng(visibleBounds.northeast.latitude, visibleBounds.southwest.longitude),
      ],
      strokeColor: Colors.blue,
      strokeWidth: 2,
      fillColor: Colors.blue.withAlpha(50),
    );

    // Calculate all cells that intersect with viewport
    final cellsInArea = await SpatialDb().getCellsInArea(visibleBoundingBox);

    setState(() {
      // Update viewport polygon
      _cellPolygons.removeWhere((p) => p.polygonId == const PolygonId('viewport'));
      _cellPolygons.add(viewportPolygon);

      // Add red polygons for all cells in viewport
      for (var cell in cellsInArea) {
        final cellKey = '${cell.minLon},${cell.minLat}';
        final cellPolygon = Polygon(
            polygonId: PolygonId('cell_$cellKey'),
            points: [
              LatLng(cell.minLat, cell.minLon),
              LatLng(cell.minLat, cell.maxLon),
              LatLng(cell.maxLat, cell.maxLon),
              LatLng(cell.maxLat, cell.minLon),
            ],
            strokeColor: Colors.red,
            strokeWidth: 2,
            fillColor: Colors.red.withAlpha(100),
          );
          _cellPolygons.add(cellPolygon);

          // Load POIs for this cell if not already loaded
          if (!_cellMarkers.containsKey(cellKey)) {
            _loadPOIsForCell(cellKey, cell);
          }
      }
    });
  }
    
  Future<void> _loadPOIsForCell(String cellKey, BoundingBox cell) async {
    try {
      final points = await SpatialDb().getPointsInBoundingBox(cell);
      final filteredPoints = points.take(poisPerCell).toList();

      final cellMarkers = <Marker>{};
      for (var point in filteredPoints) {
        cellMarkers.add(
          Marker(
            markerId: MarkerId('marker_${point.lon}_${point.lat}'),
            position: LatLng(point.lat, point.lon),
            icon: BitmapDescriptor.defaultMarker,
            onTap: () => _onMarkerTapped(point),
          ),
        );
      }

      setState(() {
        _cellMarkers[cellKey] = cellMarkers;
        _markers = _cellMarkers.values.expand((markers) => markers).toSet();
      });
    } catch (e) {
      debugPrint('Error loading POIs for cell $cellKey: $e');
    }
  }

  void _onMarkerTapped(Point point) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MeetingConfirmationSheet(
        point: point,
        onConfirm: () {
          setState(() => _selectedPOI = point);
          _suggestMeeting();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        title: Text(widget.mode == MapMode.suggestMeeting ? 
          'Suggest Meeting with ${widget.friend?.username}' : 
          'POIs Map'
        ),
        actions: [
          if (widget.mode == MapMode.normal)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearData,
            ),
        ],
      ),
      body: Stack(
        children: [
          if (!isLoadingLocation && initialPosition != null)
            Column(
              children: [
                Expanded(
                  child: GoogleMap(
                    onMapCreated: _onMapCreated,
                    initialCameraPosition: CameraPosition(
                      target: initialPosition!,
                      zoom: 17,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    markers: _markers,
                    polygons: _cellPolygons,
                    onCameraMove: _onCameraMove,
                    onCameraIdle: _onCameraIdle,
                  ),
                ),
              ],
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

  Future<void> _clearData() async {
    setState(() {
      isLoadingPOIs = true;
    });
    
    await SpatialDb().emptyTable(SpatialDb.pois);
    await SpatialDb().emptyTable(SpatialDb.cells);
    
    setState(() {
      _markers = {};
      _cellMarkers.clear();
      _cellPolygons.clear();
      isLoadingPOIs = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All data cleared'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _suggestMeeting() async {
    if (_selectedPOI == null || widget.friend == null || widget.currentUser == null) return;

    final meeting = Meeting(
      id: '', // Firestore will generate
      senderId: widget.currentUser!.uid,
      receiverId: widget.friend!.uid,
      location: GeoPoint(_selectedPOI!.lat, _selectedPOI!.lon),
      time: DateTime.now().add(const Duration(days: 1)),
      status: MeetingStatus.pending,
    );

    // Save to Firestore
    await FirebaseFirestore.instance
      .collection('meetings')
      .add(meeting.toFirestore());

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meeting suggestion sent!')),
      );
    }
  }
} 