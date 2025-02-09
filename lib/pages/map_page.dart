import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'package:flutter_near/common/db_helper.dart';
import 'package:flutter_near/common/location_service.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  bool isLoading = true;
  bool isMapCreated = false;
  LatLng? initialPosition;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    try {
      GeoPoint? position = await LocationService().getCurrentPosition();
      if (position != null && mounted) {
        setState(() {
          initialPosition = LatLng(position.latitude, position.longitude);
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        setState(() {
          initialPosition = const LatLng(0, 0); // Default position if location fails
          isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    if (_mapController != null) {
      _mapController!.dispose();
    }
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    if (!isMapCreated) {
      _mapController = controller;
      isMapCreated = true;
      _loadPOIs();
    }
  }

  Future<void> _loadPOIs() async {
    if (_mapController == null) return;

    setState(() {
      isLoading = true;
    });

    try {
      LatLngBounds bounds = await _mapController!.getVisibleRegion();
      
      jts.Envelope boundingBox = jts.Envelope(
        bounds.southwest.longitude,
        bounds.northeast.longitude,
        bounds.southwest.latitude,
        bounds.northeast.latitude,
      );

      List<jts.Point> pois = await DbHelper().getPointsInBoundingBox(
        boundingBox,
        DbHelper.pois,
      );

      Set<Marker> markers = {};
      for (int i = 0; i < pois.length; i++) {
        markers.add(
          Marker(
            markerId: MarkerId('poi_$i'),
            position: LatLng(
              pois[i].getY(),
              pois[i].getX(),
            ),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _markers = markers;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading POIs: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (initialPosition == null) {
      return const Scaffold(
        body: Center(
          child: CustomLoader(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('POIs Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPOIs,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: initialPosition!,
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: _markers,
            onCameraIdle: _loadPOIs,
          ),
          if (isLoading)
            const Positioned.fill(
              child: Center(
                child: CustomLoader(),
              ),
            ),
        ],
      ),
    );
  }
} 