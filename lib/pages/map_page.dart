import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_near/services/meeting_service.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_near/services/location.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_near/models/meeting.dart';
import 'package:flutter_near/models/near_user.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:flutter_near/widgets/meeting_confirmation_sheet.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_near/services/firestore.dart';

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
  final http.Client httpClient = http.Client();
  GoogleMapController? _mapController;
  
  LatLng? initialPosition;
  bool isMapCreated = false;

  Meeting? _suggestedMeeting;  // Track current suggestion

  Set<Marker> _markers = {};
  
  bool _zoomChanged = false;
  double _lastZoomLevel = 0;  // Add this as a class field


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

      // Add the meeting marker
      _markers = {};
      
      // Add current location marker
      Point meetingPoint = Point(
        widget.suggestedMeeting!.location.longitude,
        widget.suggestedMeeting!.location.latitude
      );
      _markers.add(_createPOIMarker(meetingPoint, isCurrentSuggestion: true));
    }
    
    _initializeMap();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _mapController = null;
    httpClient.close();
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
      // If we have a suggested meeting, use its location
      if (widget.suggestedMeeting != null) {
        setState(() {
          initialPosition = LatLng(
            widget.suggestedMeeting!.location.latitude,
            widget.suggestedMeeting!.location.longitude
          );
        });
      } else {
        // Otherwise get current location
        GeoPoint? pos = await LocationService().getCurrentPosition();

        if (pos != null) {
          setState(() {
            initialPosition = LatLng(pos.latitude, pos.longitude);
          });
        } else {
          throw Exception('Could not get location');
        }
      }

      // Once map is created and location is known, center the camera
      if (_mapController != null && initialPosition != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(initialPosition!, 17)  // Added zoom level
        );
      }
    } catch (e) {
      debugPrint('Error in _initializeMap: $e');
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

    _loadPOIsInViewport();
  }

  void _onCameraMove(CameraPosition position) {
    // Check if zoom level has changed
    if (position.zoom != _lastZoomLevel) {
      _zoomChanged = true;
      _lastZoomLevel = position.zoom;
    }
  }

  void _onCameraIdle() {
    if (_zoomChanged) {
      _loadPOIsInViewport();
      _zoomChanged = false;
    }
  }

  Future<void> _loadPOIsInViewport() async {
    if (_mapController == null) return;

    // Keep existing meeting markers
    Set<Marker> meetingMarkers = _markers.where((marker) {
      return marker.markerId.value.contains('meeting_');
    }).toSet();

    // Clear other markers
    _markers = meetingMarkers;

    // First try with the actual user and friend points
    List<Point> points = await SpatialDb().getClustersBetweenTwoPoints(
      widget.currentUser!.getPoint(), 
      widget.friend!.getPoint(),
      httpClient: httpClient
    );

    // Print clusters for debugging
    debugPrint('Loaded ${points.length} clusters between ${widget.currentUser!.username} and ${widget.friend!.username}');
    
    if (points.isNotEmpty) {
      debugPrint('Sample cluster: (${points[0].lon}, ${points[0].lat})');
    }

    for (var point in points) {
      // Skip adding POI markers for points that already have a meeting marker
      bool isExistingMeetingPoint = false;
      for (var marker in meetingMarkers) {
        LatLng markerPos = marker.position;
        if (point.lat == markerPos.latitude && point.lon == markerPos.longitude) {
          isExistingMeetingPoint = true;
          break;
        }
      }
      
      if (!isExistingMeetingPoint) {
        _markers.add(_createPOIMarker(point));
      }
    }
    
    // Make sure the current meeting marker exists
    if (_suggestedMeeting != null) {
      // Check if we already have a marker for the current meeting
      bool hasCurrentMeetingMarker = false;
      Point currentPoint = Point(_suggestedMeeting!.location.longitude, _suggestedMeeting!.location.latitude);
      
      for (var marker in _markers) {
        if (marker.markerId.value == 'meeting_${currentPoint.lon}_${currentPoint.lat}') {
          hasCurrentMeetingMarker = true;
          break;
        }
      }
      
      // If not, add it
      if (!hasCurrentMeetingMarker) {
        _markers.add(_createPOIMarker(currentPoint, isCurrentSuggestion: true));
      }
    }

    setState(() {});
  }

  Marker _createPOIMarker(Point point, {
    bool isCurrentSuggestion = false,
  }) {
    String markerId;
    
    // First check if this point matches the current meeting location
    bool isCurrentMeetingPoint = _suggestedMeeting != null && 
      point.lat == _suggestedMeeting!.location.latitude &&
      point.lon == _suggestedMeeting!.location.longitude;

    // Create appropriate marker ID
    if (isCurrentMeetingPoint) {
      markerId = 'meeting_${point.lon}_${point.lat}';
    } else {
      markerId = 'marker_${point.lon}_${point.lat}';
    }

    // If it's the current meeting point, show with status color
    if (isCurrentMeetingPoint && _suggestedMeeting != null) {
      double hue;
      switch (_suggestedMeeting!.status) {
        case MeetingStatus.suggested:
          hue = BitmapDescriptor.hueBlue; // Blue for suggested
          break;
        case MeetingStatus.accepted:
          hue = BitmapDescriptor.hueGreen; // Green for accepted
          break;
        case MeetingStatus.rejected:
          hue = BitmapDescriptor.hueRed; // Red for rejected
          break;
      }
      return Marker(
        markerId: MarkerId(markerId),
        position: LatLng(point.lat, point.lon),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        onTap: () => _onMarkerTapped(point),
      );
    }

    // Regular POI marker in light blue
    return Marker(
      markerId: MarkerId(markerId),
      position: LatLng(point.lat, point.lon),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan), // Light blue for other POIs
      onTap: () => _onMarkerTapped(point),
    );
  }

  void _onMarkerTapped(Point point) {
    bool isCurrentPoint =
      point.lat == _suggestedMeeting?.location.latitude &&
      point.lon == _suggestedMeeting?.location.longitude;

    // If there's no meeting yet, allow creating new meeting
    if (_suggestedMeeting == null) {
      _showMeetingSheet(point);
      return;
    }

    // If this is not the current meeting point
    if (!isCurrentPoint) {
      // Allow suggesting a new location if meeting is pending
      if (_suggestedMeeting!.status == MeetingStatus.suggested) {
        _showMeetingSheet(point, currentMeeting: _suggestedMeeting);
      }
      return;
    }

    if (isCurrentPoint) {
      // For the current meeting point
      if (_suggestedMeeting!.status == MeetingStatus.suggested) {
        // Show options to accept or reject
        _showMeetingSheet(
          point, 
          currentMeeting: _suggestedMeeting,
          allowReject: true,
          allowAccept: true,
          viewOnly: true
        );
        return;
      } else {
        // For other statuses, just show info
        _showMeetingSheet(
          point, 
          currentMeeting: _suggestedMeeting,
          viewOnly: true
        );
        return;
      }
    }
  }

  void _showMeetingSheet(Point point, {
    Meeting? currentMeeting,
    bool allowReject = false,
    bool allowAccept = false,
    bool viewOnly = false,
  }) {
    final MeetingService meetingService = MeetingService();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MeetingConfirmationSheet(
        point: point,
        currentMeeting: currentMeeting,
        currentUserId: widget.currentUser!.uid,
        viewOnly: viewOnly,
        onReject: allowReject ? () async {
          final success = await meetingService.rejectMeeting(
            _suggestedMeeting!.token,
            currentMeeting: _suggestedMeeting
          );
          
          if (success) {
            setState(() {
              // Update the marker with rejected status
              Point meetingPoint = Point(
                _suggestedMeeting!.location.longitude,
                _suggestedMeeting!.location.latitude
              );
              
              // Update only the current marker
              _markers.removeWhere((m) => m.markerId.value == 'meeting_${meetingPoint.lon}_${meetingPoint.lat}');
              _markers.add(_createPOIMarker(meetingPoint, isCurrentSuggestion: true));
              
              // Don't reload all POIs
            });
          }
        } : null,
        onAccept: allowAccept ? () async {
          final success = await meetingService.acceptMeeting(
            _suggestedMeeting!.token,
            currentMeeting: _suggestedMeeting
          );
          
          if (success) {
            setState(() {
              // Update the marker with accepted status
              Point meetingPoint = Point(
                _suggestedMeeting!.location.longitude,
                _suggestedMeeting!.location.latitude
              );
              
              // Update only the current marker
              _markers.removeWhere((m) => m.markerId.value == 'meeting_${meetingPoint.lon}_${meetingPoint.lat}');
              _markers.add(_createPOIMarker(meetingPoint, isCurrentSuggestion: true));
              
              // Don't reload all POIs
            });
          }
        } : null,
        onConfirm: !viewOnly ? (selectedTime) async {
          if (currentMeeting != null) {
            // Store the previous meeting point before updating
            Point previousPoint = Point(
              currentMeeting.location.longitude,
              currentMeeting.location.latitude
            );
            
            // Update existing meeting with a new suggestion
            final updatedMeeting = await meetingService.suggestMeeting(
              currentMeeting.token,
              point.lon,
              point.lat,
              selectedTime,
              currentMeeting: currentMeeting
            );
            
            if (updatedMeeting != null) {
              // First update the suggested meeting object
              _suggestedMeeting = updatedMeeting;
              
              setState(() {
                // Remove the old meeting marker
                _markers.removeWhere((m) => 
                  m.markerId.value == 'meeting_${previousPoint.lon}_${previousPoint.lat}');
                
                // Add the previous point back as a normal cluster marker (light blue)
                _markers.add(Marker(
                  markerId: MarkerId('marker_${previousPoint.lon}_${previousPoint.lat}'),
                  position: LatLng(previousPoint.lat, previousPoint.lon),
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
                  onTap: () => _onMarkerTapped(previousPoint),
                ));
                
                // Add the new current point marker
                _markers.add(_createPOIMarker(point, isCurrentSuggestion: true));
                
                // Don't reload all POIs, just update the specific markers
              });
            }
          } else {
            // Create a new meeting with location and datetime in a single call
            final suggestedMeeting = await meetingService.createMeeting(
              longitude: point.lon,
              latitude: point.lat,
              datetime: selectedTime
            );
            
            if (suggestedMeeting != null) {
              // Save the meeting in Firestore to enable real-time updates
              await FirestoreService().createMeeting(
                suggestedMeeting.token,
                widget.currentUser!.uid,
                widget.friend!.uid
              );
              
              // First update the suggested meeting object
              _suggestedMeeting = suggestedMeeting;
              
              setState(() {
                // Add the new meeting marker without clearing others
                _markers.add(_createPOIMarker(point, isCurrentSuggestion: true));
                
                // Don't reload all POIs
              });
            }
          }
        } : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (initialPosition == null) {
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
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Meet with ${widget.friend!.username}'),
      ),
      body: Stack(
        children: [
          if (initialPosition != null) Column(
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
                  onCameraMove: _onCameraMove,
                  onCameraIdle: _onCameraIdle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
} 