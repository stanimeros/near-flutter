import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class LocationService{

  Future<String?> askForPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Location services are disabled.';
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return 'Location permissions are denied';
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return 'Location permissions are permanently denied, we cannot request permissions.';
    } 
    return null;
  }

  Future<GeoPoint?> getCurrentPosition() async{
    String? permissionStatus = await askForPermissions();
    if (permissionStatus == null){
      Position? pos = await Geolocator.getCurrentPosition();
      GeoPoint loc = GeoPoint(pos.latitude, pos.longitude);
      return loc;
    }
    return null;
  }
}