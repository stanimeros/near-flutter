import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class EmptyMapPage extends StatefulWidget {
  const EmptyMapPage({super.key});

  @override
  State<EmptyMapPage> createState() => _EmptyMapPageState();
}

class _EmptyMapPageState extends State<EmptyMapPage> {
  GoogleMapController? _mapController;
  String _debugInfo = '';

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _updateDebugInfo(String info) {
    setState(() {
      _debugInfo = info;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Map'),
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              setState(() {
                _mapController = controller;
                _updateDebugInfo('Map controller created');
              });
            },
            initialCameraPosition: const CameraPosition(
              target: LatLng(37.7749, -122.4194), // San Francisco coordinates
              zoom: 12,
            ),
            mapType: MapType.normal,
            myLocationEnabled: false,
            zoomControlsEnabled: true,
            zoomGesturesEnabled: true,
            tiltGesturesEnabled: false,
            compassEnabled: true,
          ),
          if (_debugInfo.isNotEmpty)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black.withAlpha(100),
                child: Text(
                  _debugInfo,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
} 