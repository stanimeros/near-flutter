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
  Set<Polygon> _cityPolygons = {}; // Add this to store city polygons
  
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

    // Load city polygons and POIs when map is created
    _loadCityPolygonsInViewport();
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
      _loadCityPolygonsInViewport();
      _loadPOIsInViewport();
      _zoomChanged = false;
    }
  }

  // New method to load city polygons
  Future<void> _loadCityPolygonsInViewport() async {
    if (_mapController == null) return;

    try {
      final bounds = await _mapController!.getVisibleRegion();
      final BoundingBox bbox = BoundingBox(
        bounds.southwest.longitude,
        bounds.northeast.longitude,
        bounds.southwest.latitude,
        bounds.northeast.latitude
      );
      
      // Get city polygons from the API
      final cities = await SpatialDb().getCitiesInBoundingBox(bbox, httpClient: httpClient);
      
      // Print city information for debugging
      debugPrint('Loaded ${cities.length} cities in the viewport');
      if (cities.isNotEmpty) {
        debugPrint('Cities found: ${cities.map((city) => city['name']).join(', ')}');
      }
      
      // Create polygon set
      Set<Polygon> polygons = {};
      
      for (var city in cities) {
        // Parse GeoJSON coordinates
        final geometry = city['geometry'];
        if (geometry['type'] == 'Polygon') {
          List<List<dynamic>> coordinates = List<List<dynamic>>.from(geometry['coordinates'][0]);
          
          // Convert coordinates to LatLng list
          List<LatLng> polygonPoints = coordinates.map((coord) {
            return LatLng(coord[1], coord[0]);
          }).toList();
          
          // Create a polygon for each city
          polygons.add(
            Polygon(
              polygonId: PolygonId('city_${city['id']}'),
              points: polygonPoints,
              strokeWidth: 2,
              strokeColor: Colors.blue,
              fillColor: Colors.blue.withAlpha(100),
              consumeTapEvents: true,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('City: ${city['name']}'))
                );
              }
            )
          );
        }
      }
      
      setState(() {
        _cityPolygons = polygons;
      });
      
    } catch (e) {
      debugPrint('Error loading city polygons: $e');
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
      _markers.add(_createPOIMarker(point));
    }

    // Add marker for current meeting location
    if (_suggestedMeeting != null) {
      // Add marker for current location
      Point currentPoint = Point(_suggestedMeeting!.location.longitude, _suggestedMeeting!.location.latitude);
      _markers.add(_createPOIMarker(currentPoint, isCurrentSuggestion: true));
    }

    setState(() {});
  }

  Marker _createPOIMarker(Point point, {
    bool isCurrentSuggestion = false,
    bool isPreviousPoint = false,
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
          hue = BitmapDescriptor.hueOrange;
          break;
        case MeetingStatus.accepted:
          hue = BitmapDescriptor.hueGreen;
          break;
        case MeetingStatus.rejected:
          hue = BitmapDescriptor.hueRed;
          break;
      }
      return Marker(
        markerId: MarkerId(markerId),
        position: LatLng(point.lat, point.lon),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        onTap: () => _onMarkerTapped(point),
      );
    }

    // If it's a previous location point, show in azure
    if (isPreviousPoint) {
      return Marker(
        markerId: MarkerId(markerId),
        position: LatLng(point.lat, point.lon),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        onTap: () => _onMarkerTapped(point),
      );
    }

    // Otherwise it's a regular POI marker in green
    return Marker(
      markerId: MarkerId(markerId),
      position: LatLng(point.lat, point.lon),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
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
              
              // Reload POIs to show clusters
              _loadPOIsInViewport();
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
              
              // Reload POIs to show clusters
              _loadPOIsInViewport();
            });
          }
        } : null,
        onConfirm: !viewOnly ? (selectedTime) async {
          if (currentMeeting != null) {
            // Update existing meeting with a new suggestion
            final updatedMeeting = await meetingService.suggestMeeting(
              currentMeeting.token,
              point.lon,
              point.lat,
              selectedTime,
              currentMeeting: currentMeeting
            );
            
            if (updatedMeeting != null) {
              setState(() {
                _suggestedMeeting = updatedMeeting;
                // Update marker but don't clear all markers
                _markers.removeWhere((m) => 
                  m.markerId.value == 'meeting_${updatedMeeting.location.longitude}_${updatedMeeting.location.latitude}');
                _markers.add(_createPOIMarker(point, isCurrentSuggestion: true));
                
                // Reload POIs to show clusters
                _loadPOIsInViewport();
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
              
              setState(() {
                _suggestedMeeting = suggestedMeeting;                
                // Update marker but don't clear all markers
                _markers.removeWhere((m) => 
                  m.markerId.value == 'meeting_${suggestedMeeting.location.longitude}_${suggestedMeeting.location.latitude}');
                _markers.add(_createPOIMarker(point, isCurrentSuggestion: true));
                
                // Reload POIs to show clusters
                _loadPOIsInViewport();
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
                  polygons: _cityPolygons, // Add the city polygons
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