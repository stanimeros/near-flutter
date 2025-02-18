import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:geolocator/geolocator.dart';

class NearUser{
  final String uid;
  final String email;
  String username;
  DateTime? joined;
  GeoPoint? location;
  DateTime? updated;
  String imageURL;
  int kAnonymity;
  List<String> friendsUIDs;

  NearUser({
    required this.uid,
    required this.email,
    required this.username,
    this.joined,
    this.location,
    this.updated,
    this.imageURL = '',
    this.kAnonymity = 10,
    this.friendsUIDs = const []
  });

  factory NearUser.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map;
    return NearUser(
      uid: doc.id,
      username: data['username'] ?? 'username',
      email: data['email'] ?? 'email@email.com',
      joined: data['joined']?.toDate(),
      location: data['location'],
      updated: data['updated']?.toDate(),
      imageURL: data['image'] ?? '',
      kAnonymity: int.tryParse(data['kAnonymity'].toString()) ?? 10,
      friendsUIDs: data['friendsUIDs'] ?? []
    );
  }

  double getDistanceBetweenUser(NearUser friend){
    return Geolocator.distanceBetween(
        location!.latitude,
        location!.longitude,
        friend.location!.latitude,
        friend.location!.longitude
      );
  }

  String getConvertedDistanceBetweenUser(NearUser friend){
    double meters = getDistanceBetweenUser(friend);
    if (meters < 1000){
      return '${meters.toStringAsFixed(2)}m';
    }else {
      return '${(meters/1000).toStringAsFixed(2)}km';
    }
  }

  List<NearUser> getUsersOrderedByLocation(List<NearUser> friends) {
    friends.removeWhere((friend) => friend.location == null);

    friends.sort((a, b) {
      double distanceA = Geolocator.distanceBetween(
        location!.latitude,
        location!.longitude,
        a.location!.latitude,
        a.location!.longitude
      );

      double distanceB = Geolocator.distanceBetween(
        location!.latitude,
        location!.longitude,
        b.location!.latitude,
        b.location!.longitude
      );

      return distanceA.compareTo(distanceB);
    });

    return friends;
  }

  getPoint(){
    return Point(location!.longitude, location!.latitude);
  }
}