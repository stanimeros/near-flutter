import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class LocationService{

  Future<bool> permissionsProcess() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.');
    } 
    return true;
  }

  Future<GeoPoint?> getCurrentPosition() async{
    if (await permissionsProcess()){
      Position? pos = await Geolocator.getCurrentPosition();
      GeoPoint loc = GeoPoint(pos.latitude, pos.longitude);
      return loc;
    }
    return null;
  }
}