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
  Timer? _debounceTimer;
  final Map<String, Set<Marker>> _cellMarkers = {}; // Track markers per cell
  final Set<Polygon> _cellPolygons = {};  // Add this for cell visualization
  static const int poisPerCell = 5;   // Show 50 POIs per cell

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
    if (_mapController == null) return;

    final LatLngBounds visibleBounds = await _mapController!.getVisibleRegion();
    
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
    final swCellX = (visibleBounds.southwest.longitude / Spatialite.gridSize).floor();
    final swCellY = (visibleBounds.southwest.latitude / Spatialite.gridSize).floor();
    final neCellX = (visibleBounds.northeast.longitude / Spatialite.gridSize).floor();
    final neCellY = (visibleBounds.northeast.latitude / Spatialite.gridSize).floor();

    debugPrint('Viewport covers cells: ($swCellX,$swCellY) to ($neCellX,$neCellY)');

    setState(() {
      // Update viewport polygon
      _cellPolygons.removeWhere((p) => p.polygonId == const PolygonId('viewport'));
      _cellPolygons.add(viewportPolygon);

      // Add red polygons for all cells in viewport
      for (int x = swCellX; x <= neCellX; x++) {
        for (int y = swCellY; y <= neCellY; y++) {
          final cellKey = '$x,$y';
          final cellPolygon = Polygon(
            polygonId: PolygonId('cell_$cellKey'),
            points: [
              LatLng(y * Spatialite.gridSize, x * Spatialite.gridSize),
              LatLng(y * Spatialite.gridSize, (x + 1) * Spatialite.gridSize),
              LatLng((y + 1) * Spatialite.gridSize, (x + 1) * Spatialite.gridSize),
              LatLng((y + 1) * Spatialite.gridSize, x * Spatialite.gridSize),
            ],
            strokeColor: Colors.red,
            strokeWidth: 2,
            fillColor: Colors.red.withAlpha(100),
          );
          _cellPolygons.add(cellPolygon);

          // Load POIs for this cell if not already loaded
          if (!_cellMarkers.containsKey(cellKey)) {
            _loadPOIsForCell(x, y, cellKey);
          }
        }
      }
    });
  }

  Future<void> _loadPOIsForCell(int cellX, int cellY, String cellKey) async {
    try {
      final cellBounds = jts.Envelope(
        cellX * Spatialite.gridSize,
        (cellX + 1) * Spatialite.gridSize,
        cellY * Spatialite.gridSize,
        (cellY + 1) * Spatialite.gridSize
      );

      final points = await Spatialite().getPointsInBoundingBox(cellBounds);
      final shuffledPoints = List.from(points)..shuffle();
      final filteredPoints = shuffledPoints.take(poisPerCell).toList();

      if (mounted) {
        final cellMarkers = <Marker>{};
        for (var point in filteredPoints) {
          cellMarkers.add(
            Marker(
              markerId: MarkerId('${point.getX()}-${point.getY()}'),
              position: LatLng(point.getY(), point.getX()),
              icon: BitmapDescriptor.defaultMarker,
              onTap: () => _onMarkerTapped(point),
            ),
          );
        }

        setState(() {
          _cellMarkers[cellKey] = cellMarkers;
          _markers = _cellMarkers.values.expand((markers) => markers).toSet();
        });
      }
    } catch (e) {
      debugPrint('Error loading POIs for cell $cellKey: $e');
    }
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