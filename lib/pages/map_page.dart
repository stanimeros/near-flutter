import 'package:flutter/material.dart';
import 'package:flutter_near/services/firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_near/services/location.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_near/models/meeting.dart';
import 'package:flutter_near/models/near_user.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:flutter_near/widgets/meeting_confirmation_sheet.dart';
import 'dart:async';

class MapPage extends StatefulWidget {
  final NearUser? friend;
  final NearUser? currentUser;
  final Meeting? suggestedMeeting;  // Add this to show existing suggestion

  const MapPage({
    super.key,
    this.friend,
    this.currentUser,
    this.suggestedMeeting,
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
  final Map<String, Set<Marker>> _cellMarkers = {}; // Track markers per cell
  final Set<Polygon> _cellPolygons = {};  // Add this for cell visualization
  static const int poisPerCell = 25;   // Show 50 POIs per cell
  Meeting? _suggestedMeeting;  // Track current suggestion

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Add suggested meeting marker if exists
    if (widget.suggestedMeeting != null) {
      _suggestedMeeting = widget.suggestedMeeting;
      initialPosition = LatLng(
        widget.suggestedMeeting!.location.latitude,
        widget.suggestedMeeting!.location.longitude
      );
    }
    
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
        bool isCurrentSuggestion = _suggestedMeeting != null && 
          point.lat == _suggestedMeeting!.location.latitude &&
          point.lon == _suggestedMeeting!.location.longitude;
        
        cellMarkers.add(_createPOIMarker(point, isCurrentSuggestion: isCurrentSuggestion));
      }

      setState(() {
        _cellMarkers[cellKey] = cellMarkers;
        _markers = _cellMarkers.values.expand((markers) => markers).toSet();
      });
    } catch (e) {
      debugPrint('Error loading POIs for cell $cellKey: $e');
    }
  }

  Marker _createPOIMarker(Point point, {bool isCurrentSuggestion = false}) {
    return Marker(
      markerId: MarkerId('marker_${point.lon}_${point.lat}'),
      position: LatLng(point.lat, point.lon),
      icon: isCurrentSuggestion ? 
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue) :
        BitmapDescriptor.defaultMarker,
      onTap: () => _onMarkerTapped(point),
    );
  }

  void _onMarkerTapped(Point point) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MeetingConfirmationSheet(
        point: point,
        onConfirm: () async {
          // If there's a previous suggestion, update its status
          if (_suggestedMeeting != null) {
            await FirestoreService().updateMeetingStatus(
              _suggestedMeeting!.id, 
              MeetingStatus.counterProposal
            );
          }

          // Create new meeting suggestion
          DocumentReference doc = FirebaseFirestore.instance
            .collection('meetings')
            .doc();

          // Create new meeting suggestion
          Meeting meeting = Meeting(
            id: doc.id,
            senderId: widget.currentUser!.uid,
            receiverId: widget.friend!.uid,
            location: GeoPoint(point.lat, point.lon),
            time: DateTime.now().add(const Duration(days: 1)),
            status: MeetingStatus.pending,
          );

          // Save to Firestore
          await doc.set(meeting.toFirestore());

          setState(() {
            // Remove previous suggestion marker
            if (_suggestedMeeting != null) {
              Point previusPoint = Point(_suggestedMeeting!.location.longitude, _suggestedMeeting!.location.latitude);
              _markers.removeWhere((m) => m.markerId.value == 'marker_${previusPoint.lon}_${previusPoint.lat}');
              _markers.add(_createPOIMarker(previusPoint, isCurrentSuggestion: false));
            }

            // Update markers to show new suggestion
            _markers.removeWhere((m) => m.markerId.value == 'marker_${point.lon}_${point.lat}');
            _markers.add(_createPOIMarker(point, isCurrentSuggestion: true));

            // Update current suggestion
            _suggestedMeeting = meeting;
          });
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
        title: Text('POIs Map'),
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
} 