import 'package:flutter/material.dart';
import 'package:flutter_near/services/firestore.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_near/services/location.dart';
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
  bool _shouldShowPOIs = true;  // Add this to control POI visibility

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
      
      // Check if we should show POIs
      _shouldShowPOIs = widget.suggestedMeeting!.status == MeetingStatus.pending && 
        widget.suggestedMeeting!.time.isBefore(DateTime.now());

      // Add the meeting marker regardless of POI visibility
      Point meetingPoint = Point(
        widget.suggestedMeeting!.location.longitude,
        widget.suggestedMeeting!.location.latitude
      );
      _markers = {_createPOIMarker(meetingPoint, isCurrentSuggestion: true)};
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
        
        // Add marker if we should show POIs or if it's the meeting point
        if (_shouldShowPOIs || isCurrentSuggestion) {
          cellMarkers.add(_createPOIMarker(point, isCurrentSuggestion: isCurrentSuggestion));
        }
      }

      setState(() {
        _cellMarkers[cellKey] = cellMarkers;
        
        // Combine all markers, ensuring the meeting marker stays visible
        Set<Marker> allMarkers = _cellMarkers.values.expand((markers) => markers).toSet();
        if (_suggestedMeeting != null) {
          Point meetingPoint = Point(
            _suggestedMeeting!.location.longitude,
            _suggestedMeeting!.location.latitude
          );
          allMarkers.add(_createPOIMarker(meetingPoint, isCurrentSuggestion: true));
        }
        _markers = allMarkers;
      });
    } catch (e) {
      debugPrint('Error loading POIs for cell $cellKey: $e');
    }
  }

  Marker _createPOIMarker(Point point, {bool isCurrentSuggestion = false}) {
    if (isCurrentSuggestion && _suggestedMeeting != null) {
      // Use different colors based on meeting status
      double hue;
      switch (_suggestedMeeting!.status) {
        case MeetingStatus.pending:
          hue = BitmapDescriptor.hueYellow;  // Changed from hueOrange to hueYellow for better visibility
        case MeetingStatus.cancelled:
          hue = BitmapDescriptor.hueRed;
        case MeetingStatus.counterProposal:
          hue = BitmapDescriptor.hueViolet;
        case MeetingStatus.accepted:
          hue = BitmapDescriptor.hueGreen;
        case MeetingStatus.rejected:
          hue = BitmapDescriptor.hueRed;
      }
      return Marker(
        markerId: MarkerId('marker_${point.lon}_${point.lat}'),
        position: LatLng(point.lat, point.lon),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        onTap: () => _onMarkerTapped(point),
      );
    }

    // Regular POI marker in green
    return Marker(
      markerId: MarkerId('marker_${point.lon}_${point.lat}'),
      position: LatLng(point.lat, point.lon),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      onTap: () => _onMarkerTapped(point),
    );
  }


  void _onMarkerTapped(Point point) {
    bool isCurrentPoint = _suggestedMeeting != null && 
      point.lat == _suggestedMeeting!.location.latitude &&
      point.lon == _suggestedMeeting!.location.longitude;

    // If meeting is cancelled or past, only allow viewing the meeting marker
    if (!_shouldShowPOIs && !isCurrentPoint) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MeetingConfirmationSheet(
        point: point,
        currentMeeting: isCurrentPoint ? _suggestedMeeting : null,
        isCurrentUser: isCurrentPoint ? 
          _suggestedMeeting!.senderId == widget.currentUser!.uid : true,
        isNewSuggestion: !isCurrentPoint,
        onCancel: () async {
          // Only current user can cancel their pending meeting
          await FirestoreService().updateMeetingStatus(
            _suggestedMeeting!.id,
            MeetingStatus.cancelled
          );

          setState(() {
            _suggestedMeeting!.status = MeetingStatus.cancelled;
            _shouldShowPOIs = false;
            
            _markers.clear();
            _cellMarkers.clear();
            
            Point meetingPoint = Point(
              _suggestedMeeting!.location.longitude,
              _suggestedMeeting!.location.latitude
            );
            _markers.add(_createPOIMarker(meetingPoint, isCurrentSuggestion: true));
          });

          if (context.mounted) {
            Navigator.pop(context);
          }
        },
        onConfirm: (selectedTime) async {
          if (isCurrentPoint) {
            // Friend making counter proposal
            DocumentReference doc = FirebaseFirestore.instance
              .collection('meetings')
              .doc();

            // Mark original meeting as counter-proposed
            await FirestoreService().updateMeetingStatus(
              _suggestedMeeting!.id,
              MeetingStatus.counterProposal
            );

            // Create new pending meeting
            Meeting meeting = Meeting(
              id: doc.id,
              senderId: widget.currentUser!.uid,
              receiverId: widget.friend!.uid,
              location: GeoPoint(point.lat, point.lon),
              time: selectedTime,
              status: MeetingStatus.pending,
            );

            await doc.set(meeting.toFirestore());

            setState(() {
              // Update original meeting marker to purple
              Point previousPoint = Point(
                _suggestedMeeting!.location.longitude,
                _suggestedMeeting!.location.latitude
              );
              _markers.removeWhere((m) => m.markerId.value == 'marker_${previousPoint.lon}_${previousPoint.lat}');
              _markers.add(_createPOIMarker(previousPoint, isCurrentSuggestion: true));

              // Add new pending meeting marker (yellow)
              _markers.removeWhere((m) => m.markerId.value == 'marker_${point.lon}_${point.lat}');
              _markers.add(_createPOIMarker(point, isCurrentSuggestion: true));

              _suggestedMeeting = meeting;
            });
          } else {
            // Current user making new suggestion
            DocumentReference doc = FirebaseFirestore.instance
              .collection('meetings')
              .doc();

            Meeting meeting = Meeting(
              id: doc.id,
              senderId: widget.currentUser!.uid,
              receiverId: widget.friend!.uid,
              location: GeoPoint(point.lat, point.lon),
              time: selectedTime,
              status: MeetingStatus.pending,
            );

            // First update Firestore
            await doc.set(meeting.toFirestore());

            setState(() {
              // First update the current meeting
              _suggestedMeeting = meeting;
              
              // Then clear markers and update POI visibility
              _markers.clear();
              _cellMarkers.clear();
              _shouldShowPOIs = false;

              // Finally add the new marker - now it will use the correct status color
              _markers.add(_createPOIMarker(point, isCurrentSuggestion: true));
            });
          }
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
        title: Text('Meet with ${widget.friend!.username}'),
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
                    polygons: _shouldShowPOIs ? _cellPolygons : {}, // Only show polygons if showing POIs
                    onCameraMove: _onCameraMove,
                    onCameraIdle: _onCameraIdle,
                  ),
                ),
              ],
            ),
          if (isLoadingPOIs && _shouldShowPOIs) // Only show loading if showing POIs
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