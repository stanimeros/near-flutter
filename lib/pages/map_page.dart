import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'package:flutter_near/services/location.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_near/models/meeting.dart';
import 'package:flutter_near/models/near_user.dart';
import 'package:flutter_near/services/Spatialite.dart';
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
  String? errorMessage;
  bool _isCameraMoving = false;
  jts.Point? _selectedPOI;
  bool _isLoadingPOIs = false;
  Timer? _debounceTimer;
  final Set<String> _visitedCells = {};  // Track cells we've already loaded
  static const int poisPerCell = 50;   // Show 50 POIs per cell

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
    _debounceTimer?.cancel();
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
      if (!mounted) return;

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
          _loadPOIs(); // This will create the centered box
        }
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
    _mapController = controller;
    isMapCreated = true;
    
    // If we already have location, center the map and box
    if (initialPosition != null) {
      controller.animateCamera(
        CameraUpdate.newLatLng(initialPosition!)
      );
      _loadPOIs();
    }
  }

  void _onCameraMove(CameraPosition position) {
    // Debounce camera movement to prevent too many database queries
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _loadPOIsInViewport();
    });
  }

  void _onCameraIdle() {
    if (_isCameraMoving) {
      _isCameraMoving = false;
      _loadPOIs();
    }
  }

  Future<void> _loadPOIs() async {
    if (!isMapCreated || _mapController == null || !mounted) return;

    setState(() {
      isLoadingPOIs = true;
      _markers = {};
    });

    try {
      LatLngBounds bounds = await _mapController!.getVisibleRegion();
      jts.Envelope searchBox = await Spatialite().createBoundingBox(
        (bounds.northeast.longitude + bounds.southwest.longitude) / 2, 
        (bounds.northeast.latitude + bounds.southwest.latitude) / 2, 
        100
      );

      // First try to get points from DB
      // final zoom = await _mapController!.getZoomLevel();
      List<jts.Point> points = await Spatialite().getPointsInBoundingBox(searchBox);

      // Create markers for filtered points
      for (var point in points) {
        _markers.add(
          Marker(
            markerId: MarkerId('${point.getX()}-${point.getY()}'),
            position: LatLng(point.getY(), point.getX()),
            icon: BitmapDescriptor.defaultMarker,
            onTap: () => _onMarkerTapped(point),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading POIs: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoadingPOIs = false;
        });
      }
    }
  }

  Future<void> _loadPOIsInViewport() async {
    if (_mapController == null || _isLoadingPOIs) return;

    final LatLngBounds visibleBounds = await _mapController!.getVisibleRegion();
    final center = LatLng(
      (visibleBounds.southwest.latitude + visibleBounds.northeast.latitude) / 2,
      (visibleBounds.southwest.longitude + visibleBounds.northeast.longitude) / 2
    );
    
    final currentCellKey = _getCellKey(center.longitude, center.latitude);

    if (_visitedCells.contains(currentCellKey) && _markers.isNotEmpty) {
      return;
    }

    setState(() => _isLoadingPOIs = true);

    try {
      debugPrint('Loading POIs for cell: $currentCellKey');

      final cellX = (center.longitude / Spatialite.gridSize).floor();
      final cellY = (center.latitude / Spatialite.gridSize).floor();
      
      // Create cell bounds with proper coordinate order
      final cellBounds = jts.Envelope(
        cellX * Spatialite.gridSize,                // minX (west longitude)
        (cellX + 1) * Spatialite.gridSize,         // maxX (east longitude)
        cellY * Spatialite.gridSize,               // minY (south latitude)
        (cellY + 1) * Spatialite.gridSize          // maxY (north latitude)
      );

      debugPrint('Cell bounds: ${cellBounds.toString()}');
      final points = await Spatialite().getPointsInBoundingBox(cellBounds);
      final shuffledPoints = List.from(points)..shuffle();
      final filteredPoints = shuffledPoints.take(poisPerCell).toList();

      if (mounted) {
        setState(() {
          _markers.clear();
          for (var point in filteredPoints) {
            _markers.add(
              Marker(
                markerId: MarkerId('${point.getX()}-${point.getY()}'),
                position: LatLng(point.getY(), point.getX()),  // Note: point.getY() is latitude
                icon: BitmapDescriptor.defaultMarker,
                onTap: () => _onMarkerTapped(point),
              ),
            );
          }
          _visitedCells.add(currentCellKey);
        });
      }
    } catch (e) {
      debugPrint('Error loading POIs: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingPOIs = false);
      }
    }
  }

  String _getCellKey(double lon, double lat) {
    // Use same grid size as Spatialite (0.005)
    final cellX = (lon / Spatialite.gridSize).floor();
    final cellY = (lat / Spatialite.gridSize).floor();
    return '$cellX,$cellY';
  }

  void _onMarkerTapped(jts.Point point) {
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
          if (widget.mode == MapMode.suggestMeeting && _selectedPOI != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: ElevatedButton(
                onPressed: _suggestMeeting,
                child: const Text('Suggest Meeting Here'),
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
    
    await Spatialite().emptyTable(Spatialite.pois);
    await Spatialite().emptyTable(Spatialite.cells);
    
    setState(() {
      _markers = {};
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
      location: GeoPoint(_selectedPOI!.getY(), _selectedPOI!.getX()),
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