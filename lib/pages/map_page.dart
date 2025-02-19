import 'dart:math';
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
  
  LatLng? initialPosition;
  bool isMapCreated = false;

  Meeting? _suggestedMeeting;  // Track current suggestion

  Set<Marker> _markers = {};
  bool _shouldShowPOIs = true;  // Add this to control POI visibility
  
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
      
      // Show POIs only if:
      // 1. Meeting is pending or counter-proposal AND
      // 2. Current user is not the last person who proposed
      _shouldShowPOIs = (widget.suggestedMeeting!.status == MeetingStatus.pending || 
                         widget.suggestedMeeting!.status == MeetingStatus.counterProposal) &&
                        widget.suggestedMeeting!.senderId != widget.currentUser!.uid;

      // Add the meeting marker and any previous locations
      _markers = {};
      
      // Add previous location markers
      for (var prevLocation in widget.suggestedMeeting!.previousLocations) {
        Point prevPoint = Point(prevLocation.longitude, prevLocation.latitude);
        _markers.add(_createPOIMarker(prevPoint, isPreviousPoint: true));
      }
      
      // Add current location marker
      Point meetingPoint = Point(
        widget.suggestedMeeting!.location.longitude,
        widget.suggestedMeeting!.location.latitude
      );
      _markers.add(_createPOIMarker(meetingPoint, isCurrentSuggestion: true));
    } else {
      // If no meeting exists, show POIs for creating new meeting
      _shouldShowPOIs = true;
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
    if (_mapController == null || !_shouldShowPOIs) return;

    _markers.clear();

    // Only show polygons and load cells if we're showing POIs
    if (_shouldShowPOIs) {
      final zoomLevel = await _mapController!.getZoomLevel();
      final zoom = max(1, zoomLevel.toInt() - 12);
      final points = await SpatialDb().getClustersBetweenTwoPoints(widget.currentUser!.getPoint(), widget.friend!.getPoint(), zoom);

      for (var point in points) {
        _markers.add(_createPOIMarker(point));
      }
    }

    // Add markers for current and previous locations
    if (_suggestedMeeting != null) {
      // Add marker for current location
      Point currentPoint = Point(_suggestedMeeting!.location.longitude, _suggestedMeeting!.location.latitude);
      _markers.add(_createPOIMarker(currentPoint, isCurrentSuggestion: true));

      // Add markers for previous locations
      for (var prevLocation in _suggestedMeeting!.previousLocations) {
        Point prevPoint = Point(prevLocation.longitude, prevLocation.latitude);
        _markers.add(_createPOIMarker(prevPoint, isPreviousPoint: true));
      }
    }

    setState(() {});
  }

  Marker _createPOIMarker(Point point, {
    bool isCurrentSuggestion = false,
    bool isPreviousPoint = false,
  }) {
    // First check if this point matches the current meeting location
    bool isCurrentMeetingPoint = _suggestedMeeting != null && 
      point.lat == _suggestedMeeting!.location.latitude &&
      point.lon == _suggestedMeeting!.location.longitude;

    // Then check if this point is in the previous locations
    bool isInPreviousLocations = _suggestedMeeting?.previousLocations.any((loc) => 
      loc.latitude == point.lat && loc.longitude == point.lon) ?? false;

    // If it's the current meeting point, show with status color
    if (isCurrentMeetingPoint && _suggestedMeeting != null) {
      double hue;
      switch (_suggestedMeeting!.status) {
        case MeetingStatus.pending:
          hue = BitmapDescriptor.hueOrange;
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

    // If it's a previous location point, show in azure
    if (isInPreviousLocations) {
      return Marker(
        markerId: MarkerId('marker_${point.lon}_${point.lat}'),
        position: LatLng(point.lat, point.lon),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        onTap: () => _onMarkerTapped(point),
      );
    }

    // Otherwise it's a regular POI marker in green
    return Marker(
      markerId: MarkerId('marker_${point.lon}_${point.lat}'),
      position: LatLng(point.lat, point.lon),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      onTap: () => _onMarkerTapped(point),
    );
  }

  void _onMarkerTapped(Point point) {
    bool isCurrentPoint =
      point.lat == _suggestedMeeting?.location.latitude &&
      point.lon == _suggestedMeeting?.location.longitude;

    bool isInPreviousLocations = _suggestedMeeting?.previousLocations.any((loc) => 
      loc.latitude == point.lat && loc.longitude == point.lon) ?? false;

    bool isLastProposer = widget.currentUser!.uid == _suggestedMeeting?.senderId;

    // If there's no meeting yet, allow creating new meeting
    if (_suggestedMeeting == null) {
      _showMeetingSheet(point, isNewSuggestion: true);
      return;
    }

    // If this is not the current meeting point
    if (!isCurrentPoint && !isInPreviousLocations) {
      // Allow counter-proposal only for the person who didn't make the last proposal
      if (!isLastProposer && 
          (_suggestedMeeting!.status == MeetingStatus.pending || 
           _suggestedMeeting!.status == MeetingStatus.counterProposal)) {
        _showMeetingSheet(
          point, 
          isNewSuggestion: true,
          isCounterProposal: true
        );
      }
      return;
    }

    if (isCurrentPoint) {
      // For the current meeting point
      if (_suggestedMeeting!.status == MeetingStatus.pending || 
          _suggestedMeeting!.status == MeetingStatus.counterProposal) {
        if (widget.currentUser!.uid == _suggestedMeeting!.senderId) {
          // The person who made the last proposal can cancel
          _showMeetingSheet(
            point, 
            isNewSuggestion: false,
            allowCancel: true
          );
          return;
        } else {
          // The person who didn't make the last proposal can accept or reject
          _showMeetingSheet(
            point, 
            isNewSuggestion: false,
            allowReject: true,
            allowAccept: true
          );
          return;
        }
      } else {
        // For other statuses, just show info
        _showMeetingSheet(
          point, 
          isNewSuggestion: false,
          viewOnly: true
        );
        return;
      }
    }
  }

  void _showMeetingSheet(Point point, {
    bool isNewSuggestion = false,
    bool allowCancel = false,
    bool allowReject = false,
    bool allowAccept = false,
    bool viewOnly = false,
    bool isCounterProposal = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MeetingConfirmationSheet(
        point: point,
        currentMeeting: isNewSuggestion ? null : _suggestedMeeting,
        currentUserId: widget.currentUser!.uid,
        isNewSuggestion: isNewSuggestion,
        isCounterProposal: isCounterProposal,
        onCancel: allowCancel ? () async {
          await FirestoreService().updateMeetingStatus(
            _suggestedMeeting!.id,
            MeetingStatus.cancelled
          );

          setState(() {
            _suggestedMeeting!.status = MeetingStatus.cancelled;
            _shouldShowPOIs = false;
            
            // Keep existing markers but update the current one's status
            Point meetingPoint = Point(
              _suggestedMeeting!.location.longitude,
              _suggestedMeeting!.location.latitude
            );
            
            // Update only the current marker
            _markers.removeWhere((m) => m.markerId.value == 'marker_${meetingPoint.lon}_${meetingPoint.lat}');
            _markers.add(_createPOIMarker(meetingPoint, isCurrentSuggestion: true));
          });

          if (context.mounted) {
            Navigator.pop(context);
          }
        } : null,
        onReject: allowReject ? () async {
          await FirestoreService().updateMeetingStatus(
            _suggestedMeeting!.id,
            MeetingStatus.rejected
          );

          setState(() {
            _suggestedMeeting!.status = MeetingStatus.rejected;
            _shouldShowPOIs = false;
            
            // Clear all markers first
            _markers.clear();
            
            // Add previous location markers
            for (var prevLocation in _suggestedMeeting!.previousLocations) {
              Point prevPoint = Point(prevLocation.longitude, prevLocation.latitude);
              _markers.add(_createPOIMarker(prevPoint, isPreviousPoint: true));
            }
            
            // Add current location marker with rejected status
            Point meetingPoint = Point(
              _suggestedMeeting!.location.longitude,
              _suggestedMeeting!.location.latitude
            );
            _markers.add(_createPOIMarker(meetingPoint, isCurrentSuggestion: true));
          });

          if (context.mounted) {
            Navigator.pop(context);
          }
        } : null,
        onAccept: allowAccept ? () async {
          await FirestoreService().updateMeetingStatus(
            _suggestedMeeting!.id,
            MeetingStatus.accepted
          );

          setState(() {
            _suggestedMeeting!.status = MeetingStatus.accepted;
            _shouldShowPOIs = false;
            
            // Clear all markers first
            _markers.clear();
            
            // Add previous location markers
            for (var prevLocation in _suggestedMeeting!.previousLocations) {
              Point prevPoint = Point(prevLocation.longitude, prevLocation.latitude);
              _markers.add(_createPOIMarker(prevPoint, isPreviousPoint: true));
            }
            
            // Add current location marker with accepted status
            Point meetingPoint = Point(
              _suggestedMeeting!.location.longitude,
              _suggestedMeeting!.location.latitude
            );
            _markers.add(_createPOIMarker(meetingPoint, isCurrentSuggestion: true));
          });

          if (context.mounted) {
            Navigator.pop(context);
          }
        } : null,
        onConfirm: !viewOnly ? (selectedTime) async {
          if (isCounterProposal) {
            List<GeoPoint> previousLocations = [
              ..._suggestedMeeting!.previousLocations,
              _suggestedMeeting!.location,
            ];

            await FirebaseFirestore.instance
              .collection('meetings')
              .doc(_suggestedMeeting!.id)
              .update({
                'status': MeetingStatus.counterProposal.name,
                'location': GeoPoint(point.lat, point.lon),
                'time': Timestamp.fromDate(selectedTime),
                'previousLocations': previousLocations,
                'senderId': widget.currentUser!.uid,
                'receiverId': widget.friend!.uid,
              });

            setState(() {
              _suggestedMeeting!.status = MeetingStatus.counterProposal;
              _suggestedMeeting!.location = GeoPoint(point.lat, point.lon);
              _suggestedMeeting!.previousLocations = previousLocations;
              _suggestedMeeting!.senderId = widget.currentUser!.uid;
              _suggestedMeeting!.receiverId = widget.friend!.uid;
              _shouldShowPOIs = false;
              
              // Update markers to show history
              _markers.clear();
              
              // Add previous location markers
              for (var prevLocation in previousLocations) {
                Point prevPoint = Point(prevLocation.longitude, prevLocation.latitude);
                _markers.add(_createPOIMarker(prevPoint, isPreviousPoint: true));
              }
              
              // Add current location marker
              _markers.add(_createPOIMarker(point, isCurrentSuggestion: true));
            });
          } else {
            // Making new suggestion
            DocumentReference doc = FirebaseFirestore.instance
              .collection('meetings')
              .doc();

            Meeting meeting = Meeting(
              id: doc.id,
              senderId: widget.currentUser!.uid,
              receiverId: widget.friend!.uid,
              location: GeoPoint(point.lat, point.lon),
              time: selectedTime,
              createdAt: DateTime.now(),
              status: MeetingStatus.pending,
            );

            await doc.set(meeting.toFirestore());

            setState(() {
              _suggestedMeeting = meeting;
              _shouldShowPOIs = false;
              
              _markers.clear();
              _markers.add(_createPOIMarker(point, isCurrentSuggestion: true));
            });
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